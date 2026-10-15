//
//  WebRTCSignalingModels.swift
//  FridgeFit
//

import Foundation

/// Which end of the negotiation a device is.
///
/// Fixed by the flow, not by role: the **controller always calls**, the
/// camera always answers. That asymmetry is the thing that stops both
/// devices generating an offer at the same time (glare), so it is decided
/// before any document is written rather than resolved afterwards.
nonisolated enum SignalingRole: String, Codable, Sendable {
    /// Creates the session document and the offer. Always the controller.
    case caller
    /// Watches for offers addressed to it and answers. Always the camera.
    case callee

    var other: SignalingRole {
        self == .caller ? .callee : .caller
    }

    /// Firestore subcollection this side writes its ICE candidates into.
    var candidateCollectionName: String {
        self == .caller ? "callerCandidates" : "calleeCandidates"
    }
}

/// An SDP offer or answer, free of any WebRTC type so it can cross the
/// signaling boundary and be unit tested.
nonisolated struct SessionDescriptionPayload: Equatable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable {
        case offer
        case answer
    }

    let kind: Kind
    let sdp: String

    static func decode(_ data: [String: Any]?) -> SessionDescriptionPayload? {
        guard
            let data,
            let rawKind = data["type"] as? String,
            let kind = Kind(rawValue: rawKind),
            let sdp = data["sdp"] as? String,
            !sdp.isEmpty
        else {
            return nil
        }
        return SessionDescriptionPayload(kind: kind, sdp: sdp)
    }

    var encoded: [String: Any] {
        ["type": kind.rawValue, "sdp": sdp]
    }
}

/// One ICE candidate, as exchanged through Firestore.
nonisolated struct IceCandidatePayload: Equatable, Sendable {
    let candidate: String
    let sdpMid: String?
    let sdpMLineIndex: Int

    static func decode(_ data: [String: Any]) -> IceCandidatePayload? {
        guard
            let candidate = data["candidate"] as? String,
            !candidate.isEmpty,
            let index = (data["sdpMLineIndex"] as? NSNumber)?.intValue
        else {
            return nil
        }
        return IceCandidatePayload(
            candidate: candidate,
            sdpMid: data["sdpMid"] as? String,
            sdpMLineIndex: index
        )
    }

    var encoded: [String: Any] {
        var object: [String: Any] = [
            "candidate": candidate,
            "sdpMLineIndex": sdpMLineIndex,
        ]
        if let sdpMid { object["sdpMid"] = sdpMid }
        return object
    }
}

/// Lifecycle of a signaling session document.
///
/// Only ever advances. `WebRTCSessionState.canTransition(to:)` is the single
/// place that says which moves are legal, so a late Firestore snapshot
/// arriving out of order can't walk a connected session back to `offering`.
nonisolated enum WebRTCSessionState: String, Codable, CaseIterable, Sendable {
    /// Document created, offer not written yet.
    case creating
    /// Offer written, waiting for the callee's answer.
    case offering
    /// Answer written, waiting for ICE to connect.
    case answering
    /// ICE connected - media should be flowing.
    case connected
    /// Ended cleanly by either side.
    case closed
    /// Negotiation or ICE could not succeed.
    case failed

    var isTerminal: Bool {
        self == .closed || self == .failed
    }

    func canTransition(to next: WebRTCSessionState) -> Bool {
        if isTerminal { return false }
        if next == .closed || next == .failed { return true }
        switch (self, next) {
        case (.creating, .offering),
             (.offering, .answering),
             (.answering, .connected):
            return true
        default:
            // Includes same-state writes: a redundant "connected" write
            // after a duplicate snapshot is a no-op, not a transition.
            return false
        }
    }

    /// How this session state reads on the two screens.
    var deviceStatus: DeviceConnectionStatus {
        switch self {
        case .creating, .offering, .answering: return .connecting
        case .connected: return .connected
        case .closed: return .disconnected
        case .failed: return .failed
        }
    }
}

/// A signaling session document at `users/{uid}/webrtcSessions/{sessionId}`.
///
/// Scoped under the UID, so the Firestore rule that gates it is the same
/// shape as the pantry's: `request.auth.uid == uid`. Both participants are
/// named by `deviceId`, which means a session can be rejected if it isn't
/// addressed to this device even though it passed the account-level rule.
nonisolated struct WebRTCSessionRecord: Identifiable, Equatable, Sendable {
    let sessionId: String
    /// Controller device. Creates the offer.
    let callerDeviceId: String
    let callerDeviceName: String
    /// Camera device. Creates the answer.
    let calleeDeviceId: String
    let calleeDeviceName: String
    let state: WebRTCSessionState
    let offer: SessionDescriptionPayload?
    let answer: SessionDescriptionPayload?
    let createdAt: Date
    let expiresAt: Date

    var id: String { sessionId }

    /// How long an un-finished session stays interesting.
    ///
    /// Negotiation takes seconds on a LAN. Two minutes is generous, and
    /// anything older is debris from a crash or a backgrounded app - swept
    /// by `SignalingTransport.deleteExpiredSessions`.
    static let timeToLive: TimeInterval = 120

    func isExpired(now: Date = Date()) -> Bool {
        now >= expiresAt
    }

    /// The device ID on the other end from `role`.
    func peerDeviceId(from role: SignalingRole) -> String {
        role == .caller ? calleeDeviceId : callerDeviceId
    }

    func peerDeviceName(from role: SignalingRole) -> String {
        role == .caller ? calleeDeviceName : callerDeviceName
    }

    /// Which end `deviceId` is, or `nil` if this session isn't about it.
    ///
    /// The `nil` case is the per-device authorization check: Firestore rules
    /// can only prove the session belongs to the account, not that it was
    /// addressed to *this* phone.
    func role(for deviceId: String) -> SignalingRole? {
        if deviceId == callerDeviceId { return .caller }
        if deviceId == calleeDeviceId { return .callee }
        return nil
    }

    func with(state: WebRTCSessionState) -> WebRTCSessionRecord {
        WebRTCSessionRecord(
            sessionId: sessionId,
            callerDeviceId: callerDeviceId,
            callerDeviceName: callerDeviceName,
            calleeDeviceId: calleeDeviceId,
            calleeDeviceName: calleeDeviceName,
            state: state,
            offer: offer,
            answer: answer,
            createdAt: createdAt,
            expiresAt: expiresAt
        )
    }

    func with(offer: SessionDescriptionPayload?, answer: SessionDescriptionPayload?) -> WebRTCSessionRecord {
        WebRTCSessionRecord(
            sessionId: sessionId,
            callerDeviceId: callerDeviceId,
            callerDeviceName: callerDeviceName,
            calleeDeviceId: calleeDeviceId,
            calleeDeviceName: calleeDeviceName,
            state: state,
            offer: offer ?? self.offer,
            answer: answer ?? self.answer,
            createdAt: createdAt,
            expiresAt: expiresAt
        )
    }
}

// MARK: - Firestore field mapping

nonisolated extension WebRTCSessionRecord {
    enum Field {
        static let callerDeviceId = "callerDeviceId"
        static let callerDeviceName = "callerDeviceName"
        static let calleeDeviceId = "calleeDeviceId"
        static let calleeDeviceName = "calleeDeviceName"
        static let state = "state"
        static let offer = "offer"
        static let answer = "answer"
        static let createdAt = "createdAt"
        static let expiresAt = "expiresAt"
    }

    static func decode(id: String, data: [String: Any]) -> WebRTCSessionRecord? {
        guard
            let callerDeviceId = data[Field.callerDeviceId] as? String,
            let calleeDeviceId = data[Field.calleeDeviceId] as? String,
            let rawState = data[Field.state] as? String,
            let state = WebRTCSessionState(rawValue: rawState)
        else {
            return nil
        }
        let createdAt = data[Field.createdAt] as? Date ?? Date()
        return WebRTCSessionRecord(
            sessionId: id,
            callerDeviceId: callerDeviceId,
            callerDeviceName: data[Field.callerDeviceName] as? String ?? "Controller",
            calleeDeviceId: calleeDeviceId,
            calleeDeviceName: data[Field.calleeDeviceName] as? String ?? "Camera",
            state: state,
            offer: SessionDescriptionPayload.decode(data[Field.offer] as? [String: Any]),
            answer: SessionDescriptionPayload.decode(data[Field.answer] as? [String: Any]),
            createdAt: createdAt,
            expiresAt: data[Field.expiresAt] as? Date ?? createdAt.addingTimeInterval(timeToLive)
        )
    }

    /// Fields for the initial `setData`. `createdAt` is written by the
    /// caller's clock rather than `serverTimestamp()` so `expiresAt` is
    /// consistent with it - mixing a server timestamp with a locally
    /// computed expiry would make the TTL meaningless if the clocks differ.
    var encodedForCreate: [String: Any] {
        var object: [String: Any] = [
            Field.callerDeviceId: callerDeviceId,
            Field.callerDeviceName: callerDeviceName,
            Field.calleeDeviceId: calleeDeviceId,
            Field.calleeDeviceName: calleeDeviceName,
            Field.state: state.rawValue,
            Field.createdAt: createdAt,
            Field.expiresAt: expiresAt,
        ]
        if let offer { object[Field.offer] = offer.encoded }
        if let answer { object[Field.answer] = answer.encoded }
        return object
    }
}
