//
//  CameraModeViewModel.swift
//  FridgeFit
//

import Combine
import Foundation
import OSLog
import UIKit
@preconcurrency import WebRTC

/// Backs Camera Mode: this iPhone acting as a remote fridge camera.
///
/// Capture only ever starts from `activate()`, which the view calls in
/// response to the user opening this screen, and only after
/// `CameraAccess.request()` has returned `.granted`. There is no path here
/// that starts the camera in the background or without that permission - and
/// `deactivate()` on disappear/background stops it, because iOS does not
/// permit background camera capture and pretending otherwise would just
/// leave a stalled session.
@MainActor
final class CameraModeViewModel: ObservableObject {
    @Published private(set) var status: DeviceConnectionStatus = .offline
    @Published private(set) var connectedControllerName: String?
    @Published private(set) var cameraPosition: RemoteControlMessage.CameraPosition = .back
    @Published private(set) var isActive = false
    /// True once frames are actually coming out of the capture session, so
    /// the screen can say "starting" rather than showing black and implying
    /// it is streaming.
    @Published private(set) var isReceivingFrames = false
    @Published private(set) var lastCaptureSummary: String?
    /// Written only through `report(_:)` and `clearError()`, so
    /// `errorIsResolvableInSettings` can never describe a different error than
    /// the one on screen.
    @Published private(set) var errorMessage: String?
    /// True when the current error is one the user can fix in iOS Settings,
    /// so the error card can offer to take them there instead of only naming
    /// the place.
    @Published private(set) var errorIsResolvableInSettings = false

    /// The local track, for the preview. `nil` until capture starts.
    @Published private(set) var localVideoTrack: RTCVideoTrack?

    let identity: DeviceIdentity

    private let registry: any DeviceRegistry
    private let transport: any SignalingTransport
    private let heartbeat: DeviceHeartbeat
    private let logger = Logger(subsystem: "com.Fridge.FridgeFit", category: "CameraMode")

    private var cameraSource: CameraVideoSource?
    private var coordinator: WebRTCSessionCoordinator?
    private var frameProbe: Task<Void, Never>?

    init(
        identity: DeviceIdentity,
        registry: any DeviceRegistry = FirestoreDeviceRegistry(),
        transport: any SignalingTransport = FirestoreSignalingTransport()
    ) {
        self.identity = identity
        self.registry = registry
        self.transport = transport
        self.heartbeat = DeviceHeartbeat(registry: registry, deviceId: identity.deviceId, status: .available)
    }

    /// Releases local timers without the main-actor hop an isolated deinit
    /// needs - see `ConnectedDevicesViewModel.deinit` for why that hop is
    /// unsafe here.
    ///
    /// The camera session itself is stopped by `deactivate()`, which the view
    /// calls on disappear and on backgrounding. This is only a backstop for
    /// the frame probe.
    nonisolated deinit {
        frameProbe?.cancel()
    }

    var connectivityCaveat: String { WebRTCConfiguration.current.connectivityCaveat }

    // MARK: - Error reporting

    /// Shows a domain error, carrying over whether Settings can resolve it.
    private func report(_ error: RemoteCameraError) {
        errorMessage = error.message
        errorIsResolvableInSettings = error.isResolvableInSettings
    }

    /// Shows a message that describes a failure no Settings switch can fix -
    /// a capture session that would not start, a transfer that failed.
    private func report(_ message: String) {
        errorMessage = message
        errorIsResolvableInSettings = false
    }

    private func clearError() {
        errorMessage = nil
        errorIsResolvableInSettings = false
    }

    var canSwitchCamera: Bool {
        guard let cameraSource else { return false }
        return CameraVideoSource.hasCamera(at: cameraSource.position.other)
    }

    // MARK: - Lifecycle

    /// Asks for camera permission, starts capture, and advertises this device
    /// as an available camera.
    func activate() async {
        guard !isActive else { return }
        clearError()

        guard CameraVideoSource.isCameraAvailable else {
            report(RemoteCameraError.cameraUnavailable)
            return
        }
        switch await CameraAccess.request() {
        case .granted:
            break
        case .denied:
            report(RemoteCameraError.cameraPermissionDenied)
            return
        case .unavailable:
            report(RemoteCameraError.cameraUnavailable)
            return
        }

        let source = CameraVideoSource()
        do {
            try await source.start(position: .back)
        } catch let error as CameraVideoSource.CaptureError {
            report("Couldn't start the camera: \(error.describedReason)")
            return
        } catch {
            report("Couldn't start the camera: \(error.localizedDescription)")
            return
        }

        cameraSource = source
        localVideoTrack = source.videoTrack
        cameraPosition = source.position
        isActive = true
        status = .available

        await registerAsCamera()
        heartbeat.start()
        startListening(using: source)
        startFrameProbe(for: source)
    }

    /// Stops the session and the camera, and stops advertising.
    func deactivate() async {
        guard isActive else { return }
        isActive = false

        frameProbe?.cancel()
        frameProbe = nil
        isReceivingFrames = false

        await coordinator?.disconnect(reason: "the camera device left Camera Mode")
        coordinator?.stopListening()
        coordinator = nil

        await cameraSource?.stop()
        cameraSource = nil
        localVideoTrack = nil

        heartbeat.stop()
        status = .offline
        connectedControllerName = nil
    }

    private func registerAsCamera() async {
        DeviceIdentity.storeRole(.camera)
        do {
            try await registry.register(device: identity.asRegisteredDevice(role: .camera))
        } catch {
            report(ConnectedDevicesViewModel.describe(error))
        }
    }

    private func startListening(using source: CameraVideoSource) {
        let session = WebRTCSessionCoordinator(
            identity: identity,
            role: .callee,
            transport: transport,
            makePeerConnection: { WebRTCClient(localVideoTrack: source.videoTrack) }
        )
        session.setEventHandler { [weak self] event in
            self?.handle(event)
        }
        session.startListeningForIncomingSessions()
        coordinator = session
    }

    /// Watches for the first frame out of the capture session.
    ///
    /// `startCapture` succeeding doesn't mean frames are flowing - an
    /// interrupted session reports no error and simply produces nothing. The
    /// UI distinguishes the two states rather than claiming to stream.
    private func startFrameProbe(for source: CameraVideoSource) {
        frameProbe?.cancel()
        frameProbe = Task { [weak self] in
            while !Task.isCancelled {
                if source.hasFrames {
                    self?.isReceivingFrames = true
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    // MARK: - Session events

    private func handle(_ event: WebRTCSessionCoordinator.Event) {
        switch event {
        case .statusChanged(let newStatus):
            status = newStatus
            heartbeat.setStatus(newStatus)

        case .peerIdentified(_, let deviceName):
            connectedControllerName = deviceName

        case .controlMessage(let message):
            Task { await self.handle(controlMessage: message) }

        case .binaryFrame:
            // The camera never receives image data; the controller is purely
            // a consumer. Ignored rather than treated as an error.
            break

        case .videoConfirmed:
            break

        case .failed(let error):
            report(error)

        case .ended(let reason):
            connectedControllerName = nil
            status = isActive ? .available : .offline
            heartbeat.setStatus(status)
            logger.info("Session ended: \(reason, privacy: .public)")
        }
    }

    private func handle(controlMessage message: RemoteControlMessage) async {
        switch message {
        case .capturePhoto(let requestId):
            await respondToCapture(requestId: requestId)

        case .cameraSwitch:
            await switchCamera(announce: true)

        case .ping:
            try? coordinator?.send(.pong)

        case .pong, .captureStarted, .captureCompleted, .captureFailed, .cameraSwitched, .sessionEnd:
            // Camera-to-controller messages, or already handled by the
            // coordinator. Nothing to do on this side.
            break

        case .unrecognized(let type):
            logger.info("Ignoring unrecognised control message \"\(type, privacy: .public)\"")
        }
    }

    // MARK: - Capture

    /// Encodes the current frame and pushes it over the data channel.
    ///
    /// The `captureCompleted` header goes first so the controller knows how
    /// many chunks to expect and can show progress; the binary frames follow.
    private func respondToCapture(requestId: String) async {
        guard let cameraSource, let coordinator else {
            try? coordinator?.send(.captureFailed(requestId: requestId, reason: "the camera is not running"))
            return
        }

        try? coordinator.send(.captureStarted(requestId: requestId))

        do {
            let image = try cameraSource.captureStill()
            let payload = try SnapshotImageEncoder.encode(image)
            let transferId = UUID()
            let frames = try ImageTransferFrame.chunk(payload: payload, transferId: transferId)

            try coordinator.send(.captureCompleted(
                requestId: requestId,
                transferId: transferId.uuidString,
                byteCount: payload.count,
                chunkCount: frames.count
            ))
            try await coordinator.sendImage(frames: frames)

            lastCaptureSummary = "Sent \(payload.count / 1024) KB in \(frames.count) chunks"
            logger.info("Sent snapshot: \(payload.count) bytes in \(frames.count) chunks")
        } catch {
            let reason = Self.describeCaptureFailure(error)
            try? coordinator.send(.captureFailed(requestId: requestId, reason: reason))
            report("Couldn't send the photo: \(reason)")
            logger.error("Snapshot send failed: \(reason, privacy: .public)")
        }
    }

    func switchCamera(announce: Bool) async {
        guard let cameraSource else { return }
        do {
            let newPosition = try await cameraSource.switchCamera()
            cameraPosition = newPosition
            if announce {
                try? coordinator?.send(.cameraSwitched(position: newPosition))
            }
        } catch let error as CameraVideoSource.CaptureError {
            report("Couldn't switch camera: \(error.describedReason)")
        } catch {
            report("Couldn't switch camera: \(error.localizedDescription)")
        }
    }

    private static func describeCaptureFailure(_ error: Error) -> String {
        switch error {
        case let error as CameraVideoSource.CaptureError:
            return error.describedReason
        case let error as SnapshotImageEncoder.EncodeError:
            return error.describedReason
        case let error as RemoteCameraError:
            return error.message
        case let error as ImageTransferFrame.FrameError:
            return String(describing: error)
        default:
            return error.localizedDescription
        }
    }
}
