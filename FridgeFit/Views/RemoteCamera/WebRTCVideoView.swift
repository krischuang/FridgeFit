//
//  WebRTCVideoView.swift
//  FridgeFit
//

import SwiftUI
@preconcurrency import WebRTC

/// What the on-screen renderer has actually been handed.
///
/// Distinct from `RemoteVideoFrameTap`'s count, and that distinction is the
/// point: the tap is a *separate* renderer on the same track, so it can keep
/// counting happily while the view on screen was never attached, or is
/// attached to a track that stopped. Only the view can report what the view
/// received.
nonisolated struct RenderedVideoStatus: Equatable, Sendable {
    var framesRendered = 0
    /// Size the renderer was told to expect, from `setSize`.
    var reportedSize: CGSize = .zero
    /// Dimensions and rotation of the most recent frame, which is what
    /// `RTCMTLVideoView` actually has to draw.
    var lastFrameSize: CGSize = .zero
    var lastRotationDegrees: Int = 0
    /// Bounds of the view itself. A zero or tiny size here means the frames
    /// are fine and the layout is not.
    var viewSize: CGSize = .zero
}

/// `RTCMTLVideoView` that counts what it is asked to draw.
///
/// Added to diagnose a blank preview while the session reports video as live.
/// `super.renderFrame` is called first and unconditionally, so instrumenting
/// cannot be the reason something fails to draw.
final class InstrumentedVideoView: RTCMTLVideoView {
    /// Called on the main actor, at most a few times a second.
    var onStatusChange: ((RenderedVideoStatus) -> Void)?

    private let lock = NSLock()
    private var status = RenderedVideoStatus()
    private var lastReportedAt = Date.distantPast

    override func renderFrame(_ frame: RTCVideoFrame?) {
        super.renderFrame(frame)

        guard let frame else { return }
        lock.lock()
        status.framesRendered += 1
        status.lastFrameSize = CGSize(width: Int(frame.width), height: Int(frame.height))
        status.lastRotationDegrees = frame.rotation.rawValue
        let snapshot = status
        let shouldReport = Date().timeIntervalSince(lastReportedAt) > 0.5
        if shouldReport { lastReportedAt = Date() }
        lock.unlock()

        guard shouldReport else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            var current = snapshot
            current.viewSize = self.bounds.size
            self.onStatusChange?(current)
        }
    }

    override func setSize(_ size: CGSize) {
        super.setSize(size)
        lock.lock()
        status.reportedSize = size
        lock.unlock()
    }
}

/// `RTCMTLVideoView` wrapped for SwiftUI.
///
/// Metal-backed rather than the OpenGL `RTCEAGLVideoView`, which is
/// deprecated. Renders the same way for a local track (Camera Mode's
/// preview) and a remote one (Remote Camera's live view) - a video track is
/// a video track as far as the renderer is concerned.
struct WebRTCVideoView: UIViewRepresentable {
    let track: RTCVideoTrack?
    /// Mirrors the image. Used for the front camera's local preview, where an
    /// unmirrored view of yourself looks wrong. The track sent to the peer is
    /// never mirrored - only this local presentation is.
    var isMirrored = false
    /// Reports what the renderer received, for the blank-preview diagnostic.
    var onStatusChange: ((RenderedVideoStatus) -> Void)?

    func makeUIView(context: Context) -> InstrumentedVideoView {
        let view = InstrumentedVideoView()
        view.videoContentMode = .scaleAspectFill
        view.backgroundColor = .black
        view.onStatusChange = onStatusChange
        if let track {
            track.add(view)
            context.coordinator.attachedTrack = track
        }
        return view
    }

    func updateUIView(_ view: InstrumentedVideoView, context: Context) {
        view.onStatusChange = onStatusChange
        // Re-attaching the same track would double-register the renderer, so
        // only act when it actually changed - which it does when a session
        // connects, disconnects, or reconnects to a different camera.
        if context.coordinator.attachedTrack !== track {
            context.coordinator.attachedTrack?.remove(view)
            track?.add(view)
            context.coordinator.attachedTrack = track
        }
        view.transform = isMirrored ? CGAffineTransform(scaleX: -1, y: 1) : .identity
    }

    static func dismantleUIView(_ view: InstrumentedVideoView, coordinator: Coordinator) {
        coordinator.attachedTrack?.remove(view)
        coordinator.attachedTrack = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Remembers which track this renderer is attached to, so attach and
    /// detach stay balanced across SwiftUI updates.
    final class Coordinator {
        var attachedTrack: RTCVideoTrack?
    }
}

/// A video surface with a placeholder for when there is nothing to show.
///
/// The placeholder is the honest state and is used whenever no frames have
/// been confirmed - the one thing this must never do is present a black
/// rectangle as if it were a working stream.
struct VideoSurface: View {
    let track: RTCVideoTrack?
    let isLive: Bool
    let placeholder: String
    var isMirrored = false
    var onStatusChange: ((RenderedVideoStatus) -> Void)?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.black)

            if let track, isLive {
                WebRTCVideoView(
                    track: track, isMirrored: isMirrored, onStatusChange: onStatusChange
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "video.slash")
                        .font(.largeTitle)
                    Text(placeholder)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding()
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .accessibilityLabel(isLive ? "Live camera video" : placeholder)
    }
}
