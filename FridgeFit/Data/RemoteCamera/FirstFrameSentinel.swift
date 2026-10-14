//
//  FirstFrameSentinel.swift
//  FridgeFit
//

import Foundation
@preconcurrency import WebRTC

/// A video renderer that exists only to notice the first frame.
///
/// Attached to the remote track alongside the real `RTCMTLVideoView`. ICE
/// reaching `connected` means a network path works; it does not mean the
/// peer is actually encoding anything. This is what turns "we think we're
/// connected" into "a frame was decoded", so the UI can refuse to claim
/// success over a black rectangle.
///
/// Renders nothing, so it costs one object and one `Bool` check per frame.
nonisolated final class FirstFrameSentinel: NSObject, RTCVideoRenderer, @unchecked Sendable {
    private let onFirstFrame: @MainActor () -> Void
    private let lock = NSLock()
    private var hasFired = false

    init(onFirstFrame: @escaping @MainActor () -> Void) {
        self.onFirstFrame = onFirstFrame
        super.init()
    }

    func setSize(_ size: CGSize) {}

    /// Called on a WebRTC decoder thread.
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard frame != nil else { return }
        lock.lock()
        let shouldFire = !hasFired
        hasFired = true
        lock.unlock()
        guard shouldFire else { return }

        let notify = onFirstFrame
        Task { @MainActor in notify() }
    }
}
