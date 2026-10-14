//
//  RemoteCameraViewModel.swift
//  FridgeFit
//

import Combine
import Foundation
import OSLog
import UIKit
@preconcurrency import WebRTC

/// Backs the Remote Camera screen: this iPhone watching the other one's
/// camera and driving its shutter.
///
/// Nothing here touches the pantry. A received snapshot lives in memory, can
/// be saved to the app's own Documents folder for testing, and can be handed
/// to a `FoodRecognitionService` - which by default reports that recognition
/// isn't implemented. No ingredient is ever written from this screen.
@MainActor
final class RemoteCameraViewModel: ObservableObject {
    @Published private(set) var availableCameras: [RegisteredDevice] = []
    @Published private(set) var status: DeviceConnectionStatus = .offline
    @Published private(set) var connectedCameraName: String?
    /// Separate from `status` on purpose. `status` reflects ICE; this only
    /// becomes true when a frame has actually been decoded, so the screen
    /// never claims to be showing video it isn't receiving.
    @Published private(set) var isReceivingVideo = false
    @Published private(set) var remoteVideoTrack: RTCVideoTrack?

    @Published private(set) var snapshot: UIImage?
    @Published private(set) var isAwaitingSnapshot = false
    @Published private(set) var transferProgress: String?
    @Published private(set) var savedSnapshotName: String?
    @Published private(set) var recognition: FoodRecognitionResult?
    @Published private(set) var recognitionUnavailableExplanation: String?
    @Published var errorMessage: String?

    // MARK: Detection

    /// User toggle. Turning it off stops sampling immediately; video is
    /// unaffected either way.
    @Published var isDetectionEnabled = true {
        didSet {
            guard isDetectionEnabled != oldValue else { return }
            applyDetectionEnabled()
        }
    }
    /// Latest detections, paired with the frame geometry they were measured
    /// against so the overlay can map them correctly.
    ///
    /// Raw model output, in the model's own vocabulary. Kept because it is
    /// what the geometry is measured against; the UI draws `ingredients`.
    @Published private(set) var detections: DetectionFrame = .empty
    /// The same frame normalised into candidate ingredients - filtered,
    /// deduplicated and flagged for review. This is what the overlay shows.
    @Published private(set) var ingredients: IngredientDetectionFrame = .empty
    @Published private(set) var detectionStatus: DetectionStatus = .waitingForVideo
    /// Which model is running, once one has loaded.
    @Published private(set) var detectionSource: DetectionSource?
    /// Set when the preferred ingredient model could not be loaded and the
    /// COCO fallback is running instead.
    @Published private(set) var detectorFallbackReason: String?

    /// How many decoded video frames have reached a renderer.
    ///
    /// Exists to tell two very different failures apart when the preview is
    /// blank: frames arriving but not being drawn (a renderer problem) versus
    /// no frames at all (a transport or encoder problem). "Connected" and
    /// "Video live" cannot distinguish them, because both are set from the
    /// *first* frame and never revisited.
    ///
    /// Counted by `RemoteVideoFrameTap`, which is a second `RTCVideoRenderer`
    /// on the same track as the on-screen view - so a rising count is proof
    /// the track is delivering frames to renderers. Only updates while
    /// detection is running, since that is what pumps it.
    @Published private(set) var videoFrameStatistics: VideoFrameStatistics?

    /// What the *on-screen* renderer has been handed.
    ///
    /// Deliberately separate from `videoFrameStatistics`, which counts frames
    /// reaching `RemoteVideoFrameTap` - a different renderer on the same
    /// track. When the preview is blank, the two together say which half is
    /// at fault: the tap counting while this stays at zero means the view was
    /// never attached or its track stopped; both counting means frames are
    /// being delivered and not drawn.
    @Published private(set) var renderedVideoStatus: RenderedVideoStatus?

    func recordRenderedVideo(_ status: RenderedVideoStatus) {
        renderedVideoStatus = status
    }

    /// Result of the hybrid analysis of the captured photo: detector boxes
    /// fused with Apple Vision classification, plus packaging text.
    ///
    /// Deliberately separate from `ingredients`, which is the live overlay.
    /// This runs once per captured still and never on the video path, so
    /// live rendering is never waiting on it.
    @Published private(set) var snapshotAnalysis: SnapshotAnalysis?
    /// What the analysis is doing, for the progress indicator.
    @Published private(set) var analysisPhase: SnapshotAnalysisPhase = .idle
    /// Why the hybrid analysis is unavailable, when it is. `nil` otherwise.
    @Published private(set) var snapshotAnalysisUnavailable: String?
    /// Identity of the photo currently on screen.
    ///
    /// Paired with `SnapshotAnalysis.snapshotId` so results can never be
    /// shown against a photo they were not computed from.
    @Published private(set) var snapshotId: UUID?

    var isAnalyzingSnapshot: Bool { analysisPhase.isBusy }

    /// Whether `snapshotAnalysis` describes the photo currently displayed.
    ///
    /// A second capture landing mid-analysis invalidates the previous result;
    /// the boxes would still be real, just measured against other pixels.
    var isAnalysisCurrent: Bool {
        guard let analysis = snapshotAnalysis, let snapshotId else { return false }
        return analysis.snapshotId == snapshotId
    }

    /// The analysis to display, or `nil` when it does not match the photo.
    var currentAnalysis: SnapshotAnalysis? { isAnalysisCurrent ? snapshotAnalysis : nil }

    let identity: DeviceIdentity

    private let registry: any DeviceRegistry
    private let transport: any SignalingTransport
    private let recognitionService: any FoodRecognitionService
    /// Overrides how the peer connection is built. `nil` in the app, where a
    /// real `WebRTCClient` is created per session; supplied by tests so the
    /// whole screen can be driven with a `MockPeerConnection`.
    private let peerConnectionOverride: (@MainActor () -> any PeerConnectionControlling)?
    private let heartbeat: DeviceHeartbeat
    private let now: () -> Date
    private let logger = Logger(subsystem: "com.Fridge.FridgeFit", category: "RemoteCamera")

    private var coordinator: WebRTCSessionCoordinator?
    private var webRTCClient: WebRTCClient?
    private var deviceSubscription: RemoteSubscription?
    private let assembler = ImageTransferAssembler()

    private var pendingCaptureRequestId: String?
    private var expectedChunkCount: Int?
    private var captureTimeout: Task<Void, Never>?
    /// When the current capture was requested, for the duration log line.
    private var captureStartedAt: Date?
    /// Resumed when a requested photo arrives or the request fails, so
    /// `captureAndAnalyse` can await a capture that completes through the
    /// data-channel callback rather than a return value.
    private var captureContinuation: CheckedContinuation<UIImage, Error>?

    /// Builds the detector and everything needed to interpret it. Injectable
    /// so tests can substitute a stub detector or a different policy. `nil`
    /// means "no detection on this instance".
    private let makeDetector: (() throws -> ResolvedDetector)?
    /// Created on first use, then reused for the life of the view model -
    /// loading the model costs tens of milliseconds and shouldn't happen per
    /// session.
    private var resolvedDetector: ResolvedDetector?
    /// Apple's built-in classifier, created on first use. Holds no model of
    /// its own - `VNClassifyImageRequest` is part of the OS - so this is
    /// cheap to keep around.
    private var visionClassifier: AppleVisionIngredientClassifier?
    private var detectionTap: RemoteVideoFrameTap?
    /// The track the tap is currently attached to, so attach and detach stay
    /// balanced across reconnects and camera switches.
    private var tappedTrack: RTCVideoTrack?

    /// How long to wait for a capture round trip before giving up.
    ///
    /// Encode plus a few hundred kilobytes over a LAN data channel is well
    /// under a second; 20 seconds covers a slow link without leaving the
    /// button spinning forever if the camera died mid-transfer.
    static let captureTimeout: Duration = .seconds(20)

    init(
        identity: DeviceIdentity,
        registry: any DeviceRegistry = FirestoreDeviceRegistry(),
        transport: any SignalingTransport = FirestoreSignalingTransport(),
        recognitionService: any FoodRecognitionService = UnimplementedFoodRecognitionService(),
        now: @escaping () -> Date = { Date() },
        makePeerConnection: (@MainActor () -> any PeerConnectionControlling)? = nil,
        makeDetector: (() throws -> ResolvedDetector)? = { try IngredientDetectorFactory.makeBest() }
    ) {
        self.identity = identity
        self.registry = registry
        self.transport = transport
        self.recognitionService = recognitionService
        self.now = now
        self.peerConnectionOverride = makePeerConnection
        self.makeDetector = makeDetector
        self.heartbeat = DeviceHeartbeat(registry: registry, deviceId: identity.deviceId, status: .available)
    }

    /// Releases the device listener and capture timer without the main-actor
    /// hop an isolated deinit needs - see `ConnectedDevicesViewModel.deinit`
    /// for why that hop is unsafe here.
    nonisolated deinit {
        deviceSubscription?.cancel()
        captureTimeout?.cancel()
        // Stops any in-flight inference from delivering into a deallocated
        // view model. Detaching from the track needs the main actor, so that
        // is left to `stopDetection`, which every teardown path calls.
        detectionTap?.cancel()
    }

    var connectivityCaveat: String { WebRTCConfiguration.current.connectivityCaveat }
    var isConnected: Bool { coordinator?.activeSessionId != nil }
    var canRequestCapture: Bool { isConnected && isReceivingVideo && !isAwaitingSnapshot }

    // MARK: - Lifecycle

    /// Registers this device as a controller and starts discovering cameras.
    func start() async {
        DeviceIdentity.storeRole(.controller)
        do {
            try await registry.register(
                device: identity.asRegisteredDevice(role: .controller, at: now())
            )
        } catch {
            errorMessage = ConnectedDevicesViewModel.describe(error)
        }
        heartbeat.start()
        observeDevices()
        recognitionUnavailableExplanation = recognitionService.unavailableExplanation
    }

    func stop() async {
        deviceSubscription?.cancel()
        deviceSubscription = nil
        await disconnect()
        heartbeat.stop()
    }

    private func observeDevices() {
        deviceSubscription?.cancel()
        deviceSubscription = registry.observeDevices(
            onChange: { [weak self] devices in
                guard let self else { return }
                // Self is excluded, so this install can never connect to
                // itself even when it is registered in both roles. Stale
                // heartbeats are filtered so a crashed camera disappears.
                self.availableCameras = devices
                    .filter { $0.deviceId != self.identity.deviceId }
                    .filter { $0.deviceRole == .camera }
                    .filter { $0.isPresent(now: self.now()) }
                    .sorted { $0.lastSeenAt > $1.lastSeenAt }
            },
            onError: { [weak self] error in
                self?.errorMessage = ConnectedDevicesViewModel.describe(error)
            }
        )
    }

    // MARK: - Connecting

    func connect(to camera: RegisteredDevice) async {
        guard !isConnected else { return }
        guard camera.deviceId != identity.deviceId else {
            errorMessage = RemoteCameraError.sessionNotAddressedToThisDevice.message
            return
        }
        errorMessage = nil
        resetSnapshotState()

        let makePeerConnection: @MainActor () -> any PeerConnectionControlling
        if let peerConnectionOverride {
            makePeerConnection = peerConnectionOverride
        } else {
            let client = WebRTCClient()
            client.onRemoteVideoTrack = { [weak self] track in
                self?.adoptRemoteVideoTrack(track)
            }
            webRTCClient = client
            makePeerConnection = { client }
        }

        let session = WebRTCSessionCoordinator(
            identity: identity,
            role: .caller,
            transport: transport,
            makePeerConnection: makePeerConnection
        )
        session.setEventHandler { [weak self] event in
            self?.handle(event)
        }
        coordinator = session
        connectedCameraName = camera.deviceName

        await session.connect(toCameraDeviceId: camera.deviceId, cameraDeviceName: camera.deviceName)
    }

    func disconnect() async {
        captureTimeout?.cancel()
        captureTimeout = nil
        stopDetection()
        await coordinator?.disconnect(reason: "the controller disconnected")
        coordinator = nil
        webRTCClient = nil
        remoteVideoTrack = nil
        isReceivingVideo = false
        connectedCameraName = nil
        status = .disconnected
        assembler.reset()
        heartbeat.setStatus(.available)
    }

    /// Tears the session down and immediately starts a new one with the same
    /// camera. A fresh session is correct here - a failed or dropped session
    /// cannot be revived, its signaling document is already closed.
    func reconnect(to camera: RegisteredDevice) async {
        await disconnect()
        await connect(to: camera)
    }

    // MARK: - Detection

    /// Takes ownership of the remote video track.
    ///
    /// Publishes it for `WebRTCVideoView` to render and attaches the
    /// detection tap. Called from `WebRTCClient.onRemoteVideoTrack`.
    ///
    /// The tap goes on as soon as the track exists rather than waiting for
    /// `videoConfirmed` - frames may already be flowing, and waiting would
    /// throw away the first second of detections.
    func adoptRemoteVideoTrack(_ track: RTCVideoTrack) {
        remoteVideoTrack = track
        startDetection(on: track)
    }

    /// Ingredient display names this build can detect, grouped by category.
    ///
    /// Read from whichever taxonomy is loaded, so it describes the model that
    /// is actually running rather than a hard-coded list.
    func detectableIngredients(in category: IngredientGroup) -> [String] {
        resolvedDetector?.taxonomy.displayNames(in: category) ?? []
    }

    /// Total ingredient terms the running model knows.
    var detectableIngredientCount: Int {
        resolvedDetector?.taxonomy.ingredientCount ?? 0
    }

    /// Ingredients currently drawn.
    var detectionCount: Int { ingredients.ingredients.count }

    /// How many of those need the user to confirm them.
    var reviewCount: Int { ingredients.reviewCount }

    /// Attaches the frame tap to `track`.
    ///
    /// The tap is a second `RTCVideoRenderer` on the same track the
    /// `RTCMTLVideoView` is drawing - WebRTC fans frames out to every
    /// attached renderer, so this costs the video pipeline nothing beyond one
    /// extra callback.
    private func startDetection(on track: RTCVideoTrack) {
        // Reconnecting or switching camera hands us a new track; the old tap
        // has to come off the old one first.
        stopDetection()

        guard isDetectionEnabled else {
            detectionStatus = .off
            return
        }
        guard let makeDetector else {
            detectionStatus = .unavailable(reason: "Detection isn't configured in this build.")
            return
        }

        let active: ResolvedDetector
        if let resolvedDetector {
            active = resolvedDetector
        } else {
            do {
                // The factory already prefers the ingredient model and falls
                // back to COCO on its own, so reaching the catch here means
                // neither model could be loaded.
                active = try makeDetector()
                resolvedDetector = active
                detectionSource = active.source
                detectorFallbackReason = active.fallbackReason
                if let reason = active.fallbackReason {
                    logger.error("Running the COCO fallback: \(reason, privacy: .public)")
                }
            } catch let error as YOLODetectionError {
                // No usable model at all. The screen says so and keeps
                // playing video; it never substitutes fake detections.
                detectionStatus = .unavailable(reason: error.message)
                logger.error("Detector unavailable: \(error.message, privacy: .public)")
                return
            } catch {
                detectionStatus = .unavailable(reason: error.localizedDescription)
                return
            }
        }

        let tap = RemoteVideoFrameTap(
            detector: active.detector,
            onResult: { [weak self] frame in
                self?.handle(detectionFrame: frame)
            },
            onFailure: { [weak self] error in
                self?.handle(detectionError: error)
            }
        )
        track.add(tap)
        detectionTap = tap
        tappedTrack = track
        refreshDetectionStatus()
    }

    /// Detaches the tap and clears results.
    ///
    /// Called on disconnect, on session end, and before re-attaching to a new
    /// track. Clearing `detections` is the part that matters visually -
    /// without it, boxes from the previous stream would hang over the next
    /// one until the first new result arrived.
    private func stopDetection() {
        videoFrameStatistics = nil
        detectionTap?.cancel()
        if let detectionTap, let tappedTrack {
            tappedTrack.remove(detectionTap)
        }
        detectionTap = nil
        tappedTrack = nil
        detections = .empty
        ingredients = .empty
    }

    /// Reacts to the user toggle.
    ///
    /// Turning it off keeps the tap attached but idle, so flipping it back on
    /// resumes without re-loading the model or re-attaching to the track.
    private func applyDetectionEnabled() {
        if isDetectionEnabled {
            if let detectionTap {
                detectionTap.setEnabled(true)
                refreshDetectionStatus()
            } else if let remoteVideoTrack {
                // No tap yet - either detection was off when the track
                // arrived, or a previous failure tore it down.
                startDetection(on: remoteVideoTrack)
            } else {
                detectionStatus = .waitingForVideo
            }
        } else {
            detectionTap?.setEnabled(false)
            detections = .empty
            ingredients = .empty
            detectionStatus = .off
        }
    }

    private func refreshDetectionStatus() {
        guard isDetectionEnabled else {
            detectionStatus = .off
            return
        }
        if case .unavailable = detectionStatus { return }
        detectionStatus = (detectionTap != nil && isReceivingVideo) ? .running : .waitingForVideo
    }

    /// Frames seen by the tap, for the diagnostics row.
    nonisolated struct VideoFrameStatistics: Equatable, Sendable {
        let processed: Int
        let dropped: Int
        var total: Int { processed + dropped }
    }

    private func handle(detectionFrame frame: DetectionFrame) {
        // A late result from a torn-down session must not repaint the screen.
        guard detectionTap != nil, isDetectionEnabled else { return }
        guard let active = resolvedDetector else { return }
        detections = frame
        // Raw model output becomes candidate ingredients here: decoys
        // dropped, low confidence filtered, ambiguous classes genericised,
        // duplicates suppressed.
        ingredients = active.normalizer.normalize(frame, source: active.source)
        if let tap = detectionTap {
            let statistics = tap.statistics
            videoFrameStatistics = VideoFrameStatistics(
                processed: statistics.processed, dropped: statistics.dropped
            )
        }
        refreshDetectionStatus()
    }

    private func handle(detectionError error: YOLODetectionError) {
        logger.error("Detection error: \(error.message, privacy: .public)")
        guard !error.isRecoverable else {
            // A single bad frame. The next one will probably be fine, so this
            // isn't worth surfacing - the tap keeps going.
            return
        }
        detectionStatus = .unavailable(reason: error.message)
        detections = .empty
        ingredients = .empty
        // Nothing further will succeed, so stop sampling rather than burning
        // CPU on frames that will fail the same way.
        detectionTap?.setEnabled(false)
    }

    // MARK: - Capture

    func requestCapture() {
        guard let coordinator else {
            errorMessage = RemoteCameraError.snapshotTransferFailed(reason: "there is no open connection").message
            return
        }
        guard isReceivingVideo else {
            // Refusing rather than asking is deliberate: with no video
            // arriving, whatever came back would not be what the user framed.
            errorMessage = RemoteCameraError.mediaNeverArrived.message
            return
        }

        let requestId = UUID().uuidString
        captureStartedAt = Date()
        pendingCaptureRequestId = requestId
        expectedChunkCount = nil
        isAwaitingSnapshot = true
        transferProgress = "Asking the camera for a photo"
        savedSnapshotName = nil
        recognition = nil

        do {
            try coordinator.send(.capturePhoto(requestId: requestId))
        } catch {
            failCapture(reason: ConnectedDevicesViewModel.describe(error))
            return
        }

        captureTimeout?.cancel()
        captureTimeout = Task { [weak self] in
            try? await Task.sleep(for: Self.captureTimeout)
            guard !Task.isCancelled, let self, self.pendingCaptureRequestId == requestId else { return }
            self.failCapture(reason: "the camera didn't finish sending within \(Self.captureTimeout.components.seconds) seconds")
        }
    }

    func requestCameraSwitch() {
        do {
            try coordinator?.send(.cameraSwitch)
        } catch {
            errorMessage = ConnectedDevicesViewModel.describe(error)
        }
    }

    /// Puts an image into the snapshot slot without a live session.
    ///
    /// For SwiftUI previews and `RemoteCameraViewRenderingTests`, which need
    /// the snapshot section populated without negotiating a connection. Not
    /// reachable from the UI - every snapshot the user sees arrives through
    /// `handle(binaryFrame:)`.
    func presentSnapshotForPreview(_ image: UIImage) {
        snapshot = image
        snapshotId = UUID()
        snapshotAnalysis = nil
        isAwaitingSnapshot = false
        transferProgress = nil
    }

    /// Puts an analysis into the slot without running recognition.
    ///
    /// Same purpose as `presentSnapshotForPreview`, for previews and for the
    /// consistency tests - which need to inject an analysis whose
    /// `snapshotId` deliberately does *not* match the displayed photo, a
    /// state the real pipeline only reaches through a race.
    ///
    /// Stores it unconditionally; `currentAnalysis` is what decides whether
    /// it is shown, and that decision is the thing under test.
    func presentAnalysisForPreview(_ analysis: SnapshotAnalysis) {
        snapshotAnalysis = analysis
        analysisPhase = .idle
    }

    /// Writes the snapshot into the app's Documents folder.
    ///
    /// Documents rather than Photos: this is a testing affordance, and
    /// writing here needs no extra permission and no new usage description.
    /// The view also offers a share sheet for getting it anywhere else.
    func saveSnapshot() {
        guard let snapshot else { return }
        do {
            let data = try SnapshotImageEncoder.encode(snapshot)
            let directory = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("RemoteSnapshots", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let name = "snapshot-\(Int(now().timeIntervalSince1970)).jpg"
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            savedSnapshotName = name
        } catch {
            errorMessage = "Couldn't save the photo: \(error.localizedDescription)"
        }
    }

    /// Runs the snapshot through `FoodRecognitionService`.
    ///
    /// Produces nothing with the default service, which is the truthful
    /// result. Any output is marked with `isMockData` when it came from the
    /// mock, and none of it is written to the pantry.
    func recognizeSnapshot() async {
        guard let snapshot else { return }
        guard recognitionService.isAvailable else {
            recognitionUnavailableExplanation = recognitionService.unavailableExplanation
            return
        }
        do {
            recognition = try await recognitionService.recognizeFood(in: snapshot)
        } catch {
            errorMessage = "Recognition failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Analyse Ingredients

    /// The Controller's headline action: take a photo through the remote
    /// camera and run hybrid recognition over it.
    ///
    /// Capture and analysis are separate phases so the UI can say which one
    /// is happening - a 20-second capture timeout and a sub-second analysis
    /// feel very different, and "Analysing..." during a slow transfer reads
    /// as a hang.
    ///
    /// Live video is never blocked: the capture travels on the data channel
    /// and the analysis runs on a detached task.
    func captureAndAnalyse() async {
        guard analysisPhase.isBusy == false else { return }
        guard coordinator != nil else {
            analysisPhase = .failed(
                RemoteCameraError.snapshotTransferFailed(reason: "there is no open connection").message
            )
            return
        }
        guard isReceivingVideo else {
            analysisPhase = .failed(RemoteCameraError.mediaNeverArrived.message)
            return
        }

        analysisPhase = .capturing
        snapshotAnalysis = nil
        snapshotAnalysisUnavailable = nil

        let image: UIImage
        do {
            image = try await withCheckedThrowingContinuation { continuation in
                captureContinuation = continuation
                requestCapture()
            }
        } catch {
            analysisPhase = .failed((error as? RemoteCameraError)?.message ?? error.localizedDescription)
            return
        }

        await analyse(image)
    }

    /// Analyses the photo already on screen, without capturing a new one.
    func analyzeSnapshot() async {
        guard let snapshot else { return }
        await analyse(snapshot)
    }

    /// Runs the full pipeline over an image from this iPhone's photo library.
    ///
    /// Exists so recognition can be validated on **one** device. The remote
    /// camera flow needs two iPhones, which makes the one thing most in need
    /// of device testing - whether Apple Vision classification actually works
    /// on hardware - the hardest thing to reach. This path needs no second
    /// device, no WebRTC session and no network.
    ///
    /// Identical pipeline: the same YOLO model, the same classifier, the same
    /// fusion and the same review sheet. Nothing is stubbed, and the result is
    /// not marked differently - a photo is a photo.
    func analyseLocalImage(_ image: UIImage) async {
        guard !analysisPhase.isBusy else { return }
        // Takes the snapshot slot so the existing review flow applies
        // unchanged, including the id check that stops a result being shown
        // against a different picture.
        snapshot = image
        snapshotId = UUID()
        snapshotAnalysis = nil
        snapshotAnalysisUnavailable = nil
        savedSnapshotName = nil
        recognition = nil
        await analyse(image)
    }

    /// Reports a photo that could not be decoded, so the picker does not fail
    /// silently.
    func reportLocalImageFailure() {
        analysisPhase = .failed("That photo couldn't be opened.")
    }

    private func analyse(_ image: UIImage) async {
        guard let analyzer = makeSnapshotAnalyzer() else {
            analysisPhase = .idle
            snapshotAnalysisUnavailable =
                "Ingredient analysis needs the detection model, which isn't available."
            return
        }
        guard let identity = snapshotId else {
            analysisPhase = .idle
            return
        }

        analysisPhase = .analysing
        do {
            let analysis = try await Task.detached(priority: .userInitiated) {
                try analyzer.analyze(image, snapshotId: identity)
            }.value
            // The photo may have been replaced or cleared while this ran.
            // Storing the result regardless is safe because `currentAnalysis`
            // compares ids, but there is no point keeping a stale one.
            guard snapshotId == identity else {
                analysisPhase = .idle
                return
            }
            snapshotAnalysis = analysis
            analysisPhase = .idle
        } catch {
            let message = (error as? VisionClassificationError)?.message
                ?? (error as? YOLODetectionError)?.message
                ?? error.localizedDescription
            analysisPhase = .failed(message)
            logger.error("Snapshot analysis failed: \(message, privacy: .public)")
        }
    }

    /// Clears a failure so the button returns to its normal state.
    func dismissAnalysisFailure() {
        if case .failed = analysisPhase { analysisPhase = .idle }
    }

    // MARK: - Hybrid snapshot analysis

    /// Runs the detector, Apple Vision classification and packaging OCR over
    /// the captured photo, and fuses the results into confidence tiers.
    ///
    /// Everything expensive happens off the main actor. The live video path
    /// is untouched while this runs - it reads a still that has already
    /// arrived, and shares no state with the frame tap.
    ///
    /// **Nothing here writes to the Pantry.** The output is a list of
    /// candidates for a review step that the user drives.
    /// Builds the analyzer, reusing the already-loaded detector and
    /// classifier where possible.
    private func makeSnapshotAnalyzer() -> SnapshotIngredientAnalyzer? {
        guard let makeDetector else { return nil }

        let active: ResolvedDetector
        if let resolvedDetector {
            active = resolvedDetector
        } else {
            do {
                active = try makeDetector()
                resolvedDetector = active
            } catch {
                logger.error("Detector unavailable for analysis: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }

        let classifier: AppleVisionIngredientClassifier
        if let visionClassifier {
            classifier = visionClassifier
        } else {
            do {
                classifier = try AppleVisionIngredientClassifier()
                visionClassifier = classifier
            } catch {
                logger.error("Vision classifier unavailable: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }

        return SnapshotIngredientAnalyzer(resolved: active, classifier: classifier)
    }

    // MARK: - Session events

    private func handle(_ event: WebRTCSessionCoordinator.Event) {
        switch event {
        case .statusChanged(let newStatus):
            status = newStatus
            heartbeat.setStatus(newStatus)
            if newStatus == .failed || newStatus == .disconnected {
                isReceivingVideo = false
            }

        case .peerIdentified(_, let deviceName):
            connectedCameraName = deviceName

        case .videoConfirmed:
            isReceivingVideo = true
            logger.info("VIDEO stage=firstFrame result=ok")
            refreshDetectionStatus()

        case .controlMessage(let message):
            handle(controlMessage: message)

        case .binaryFrame(let data):
            handle(binaryFrame: data)

        case .failed(let error):
            errorMessage = error.message
            if case .mediaNeverArrived = error {
                isReceivingVideo = false
            }

        case .ended(let reason):
            isReceivingVideo = false
            stopDetection()
            remoteVideoTrack = nil
            connectedCameraName = nil
            coordinator = nil
            webRTCClient = nil
            assembler.reset()
            if isAwaitingSnapshot {
                failCapture(reason: "the session ended before the photo arrived")
            }
            logger.info("Session ended: \(reason, privacy: .public)")
        }
    }

    private func handle(controlMessage message: RemoteControlMessage) {
        switch message {
        case .captureStarted(let requestId) where requestId == pendingCaptureRequestId:
            transferProgress = "The camera is taking the photo"

        case .captureCompleted(let requestId, _, let byteCount, let chunkCount)
            where requestId == pendingCaptureRequestId:
            expectedChunkCount = chunkCount
            transferProgress = "Receiving \(byteCount / 1024) KB in \(chunkCount) chunks"

        case .captureFailed(let requestId, let reason) where requestId == pendingCaptureRequestId:
            failCapture(reason: reason)

        case .cameraSwitched(let position):
            transferProgress = "Camera switched to \(position.displayName.lowercased())"

        case .ping:
            try? coordinator?.send(.pong)

        case .unrecognized(let type):
            logger.info("Ignoring unrecognised control message \"\(type, privacy: .public)\"")

        case .capturePhoto, .cameraSwitch, .pong, .sessionEnd,
             .captureStarted, .captureCompleted, .captureFailed:
            // Controller-to-camera messages, replies to a request we are no
            // longer waiting on, or handled by the coordinator.
            break
        }
    }

    private func handle(binaryFrame data: Data) {
        switch assembler.accept(frame: data) {
        case .incomplete(let received, let expected):
            transferProgress = "Receiving photo: \(received) of \(expected) chunks"

        case .completed(_, let payload):
            captureTimeout?.cancel()
            captureTimeout = nil
            guard let image = SnapshotImageEncoder.decode(payload) else {
                // Every chunk arrived but the bytes don't decode - corrupted
                // in transit, or the camera encoded something unusable.
                failCapture(reason: "the received photo could not be decoded")
                return
            }
            logger.info("""
            CAPTURE stage=complete result=ok bytes=\(payload.count) \
            captureMs=\(self.captureStartedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1)
            """)
            snapshot = image
            // A new photo invalidates the previous photo's analysis.
            snapshotId = UUID()
            snapshotAnalysis = nil
            snapshotAnalysisUnavailable = nil
            isAwaitingSnapshot = false
            captureContinuation?.resume(returning: image)
            captureContinuation = nil
            pendingCaptureRequestId = nil
            transferProgress = "Received \(payload.count / 1024) KB"
            logger.info("Snapshot received: \(payload.count) bytes")

        case .rejected(let reason):
            logger.info("Dropped an image frame: \(reason, privacy: .public)")
        }
    }

    private func failCapture(reason: String) {
        captureTimeout?.cancel()
        captureTimeout = nil
        captureContinuation?.resume(
            throwing: RemoteCameraError.snapshotTransferFailed(reason: reason)
        )
        captureContinuation = nil
        pendingCaptureRequestId = nil
        expectedChunkCount = nil
        isAwaitingSnapshot = false
        transferProgress = nil
        assembler.reset()
        errorMessage = RemoteCameraError.snapshotTransferFailed(reason: reason).message
    }

    private func resetSnapshotState() {
        snapshot = nil
        snapshotId = nil
        recognition = nil
        snapshotAnalysis = nil
        snapshotAnalysisUnavailable = nil
        analysisPhase = .idle
        savedSnapshotName = nil
        transferProgress = nil
        isAwaitingSnapshot = false
        pendingCaptureRequestId = nil
        expectedChunkCount = nil
        assembler.reset()
    }
}
