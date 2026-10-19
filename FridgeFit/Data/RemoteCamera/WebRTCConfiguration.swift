//
//  WebRTCConfiguration.swift
//  FridgeFit
//

import Foundation

/// ICE server configuration for the prototype.
///
/// STUN only by default, which is a deliberate and *limited* choice. STUN
/// tells each device its own public address so the two can try to reach each
/// other directly. It does not relay anything. That means:
///
/// - Same Wi-Fi: works, usually on a host (LAN) candidate without STUN even
///   mattering.
/// - Different networks behind ordinary home NATs: often works.
/// - One device on cellular, or either behind symmetric/carrier-grade NAT:
///   frequently **fails**, and no amount of STUN fixes it. That case needs a
///   TURN relay.
///
/// So STUN is not a connectivity guarantee, and the app does not pretend it
/// is: when ICE fails, `RemoteCameraError.iceNegotiationFailed` says whether
/// a TURN server was configured and what that implies.
///
/// TURN stays optional and environment-configurable - no paid service is
/// required to run this prototype, and nothing is deployed. Supply one by
/// adding these to the gitignored `Secrets.xcconfig` (see
/// `Secrets.xcconfig.example`), exactly like `SPOONACULAR_API_KEY`:
///
/// ```
/// TURN_URL = turn:turn.example.com:3478
/// TURN_USERNAME = username
/// TURN_CREDENTIAL = password
/// ```
///
/// Credentials are read from Info.plist at runtime and never logged -
/// `describedForLogs` reports presence only.
nonisolated struct WebRTCConfiguration: Equatable, Sendable {
    nonisolated struct TurnServer: Equatable, Sendable {
        let url: String
        let username: String
        let credential: String
    }

    let stunURLs: [String]
    let turnServer: TurnServer?

    /// Google's public STUN servers. Free, no account, widely used for
    /// exactly this kind of prototype. Two of them so one being unreachable
    /// doesn't stall gathering.
    static let defaultStunURLs = [
        "stun:stun.l.google.com:19302",
        "stun:stun1.l.google.com:19302",
    ]

    /// Loaded once at first use, like `SpoonacularConfiguration`.
    static let current = load()

    static func load(bundle: Bundle = .main) -> WebRTCConfiguration {
        func string(_ key: String) -> String? {
            guard
                let value = bundle.object(forInfoDictionaryKey: key) as? String,
                case let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines),
                !trimmed.isEmpty
            else {
                return nil
            }
            return trimmed
        }

        // All three or none. A half-configured TURN server would gather relay
        // candidates that always fail authentication, which looks exactly
        // like a network problem and wastes the person debugging it.
        let turn: TurnServer?
        if let url = string("TURN_URL"),
           let username = string("TURN_USERNAME"),
           let credential = string("TURN_CREDENTIAL") {
            turn = TurnServer(url: url, username: username, credential: credential)
        } else {
            turn = nil
        }

        return WebRTCConfiguration(stunURLs: defaultStunURLs, turnServer: turn)
    }

    var hasTurnServer: Bool { turnServer != nil }

    /// Safe to log: says whether TURN is configured, never what it is.
    var describedForLogs: String {
        "STUN servers: \(stunURLs.count), TURN: \(hasTurnServer ? "configured" : "not configured")"
    }

    /// What to tell the user about cross-network expectations.
    var connectivityCaveat: String {
        if hasTurnServer {
            return """
            A TURN relay is configured, so connections across different \
            networks should work.
            """
        }
        return """
        STUN only - no TURN relay configured. Put both devices on the same \
        Wi-Fi network for the most reliable connection. Across different \
        networks (for example one device on cellular) the connection may fail.
        """
    }
}
