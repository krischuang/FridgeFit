//
//  WebRTCFactory.swift
//  FridgeFit
//

import Foundation
@preconcurrency import WebRTC

/// Process-wide `RTCPeerConnectionFactory`.
///
/// A singleton because the factory owns WebRTC's worker threads and its
/// video codec registry; creating one per session leaks threads and makes
/// repeated connect/disconnect cycles progressively slower. Created lazily,
/// so an install that never opens Camera Mode never pays for it.
nonisolated final class WebRTCFactory {
    static let shared = WebRTCFactory()

    let peerConnectionFactory: RTCPeerConnectionFactory

    private init() {
        RTCInitializeSSL()
        // Warnings and errors only. WebRTC's info level logs every ICE
        // candidate, which would put network addresses in the device log for
        // no diagnostic benefit the app's own logging doesn't already give.
        RTCSetMinDebugLogLevel(.warning)

        // This prototype streams video only - no audio track is ever created
        // or negotiated. Taking manual control of the audio session and
        // leaving it disabled keeps WebRTC's audio device module from
        // activating the session, which is what would otherwise trigger a
        // microphone permission prompt the app has no use for (and no
        // `NSMicrophoneUsageDescription` to justify).
        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.useManualAudio = true
        audioSession.isAudioEnabled = false

        peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }
}
