//
//  RemoteControlMessage.swift
//  FridgeFit
//

import Foundation

/// The control protocol spoken over the WebRTC data channel.
///
/// Small on purpose. Control messages are JSON text frames; image bytes
/// never travel this way - they go as binary frames described by
/// `ImageTransferFrame`, and a `captureCompleted` here is just the header
/// that tells the controller how many of those to expect.
///
/// ## Wire format
///
/// ```
/// controller -> camera   {"type":"capture_photo","requestId":"<uuid>"}
/// controller -> camera   {"type":"camera_switch"}
/// controller -> camera   {"type":"ping"}
/// camera -> controller   {"type":"pong"}
/// camera -> controller   {"type":"capture_completed","requestId":"<uuid>",
///                         "transferId":"<uuid>","byteCount":123,"chunkCount":11}
/// camera -> controller   {"type":"capture_failed","requestId":"<uuid>","reason":"..."}
/// camera -> controller   {"type":"camera_switched","position":"front"}
/// either direction       {"type":"session_end","reason":"..."}
/// ```
///
/// Anything that doesn't parse becomes `.unrecognized` rather than an error
/// that tears the channel down - a peer on a newer build must not be able to
/// break an older one by sending a message it doesn't know (see
/// `RemoteControlMessageCoder`).
nonisolated enum RemoteControlMessage: Equatable, Sendable {
    /// Controller asks the camera for a still. `requestId` correlates the
    /// reply, so a stale completion from an abandoned request is ignorable.
    case capturePhoto(requestId: String)
    /// Camera acknowledges and is about to encode - lets the controller show
    /// progress rather than appearing to do nothing.
    case captureStarted(requestId: String)
    /// Camera has finished encoding and is about to send `chunkCount` binary
    /// frames tagged `transferId`.
    case captureCompleted(requestId: String, transferId: String, byteCount: Int, chunkCount: Int)
    case captureFailed(requestId: String, reason: String)
    /// Controller asks the camera to flip between front and rear.
    case cameraSwitch
    /// Camera reports which lens it ended up on.
    case cameraSwitched(position: CameraPosition)
    case ping
    case pong
    /// Either side is leaving. Lets the peer show "Disconnected" instead of
    /// waiting out an ICE timeout.
    case sessionEnd(reason: String)
    /// A well-formed JSON object whose `type` this build doesn't know.
    case unrecognized(type: String)

    nonisolated enum CameraPosition: String, Codable, Sendable {
        case front
        case back

        var displayName: String {
            self == .front ? "Front" : "Rear"
        }

        var other: CameraPosition {
            self == .front ? .back : .front
        }
    }

    /// The `type` discriminator as it appears on the wire.
    var wireType: String {
        switch self {
        case .capturePhoto: return "capture_photo"
        case .captureStarted: return "capture_started"
        case .captureCompleted: return "capture_completed"
        case .captureFailed: return "capture_failed"
        case .cameraSwitch: return "camera_switch"
        case .cameraSwitched: return "camera_switched"
        case .ping: return "ping"
        case .pong: return "pong"
        case .sessionEnd: return "session_end"
        case .unrecognized(let type): return type
        }
    }
}

/// Encodes and decodes `RemoteControlMessage` to and from data-channel text
/// frames.
///
/// Hand-rolled rather than `Codable`-synthesised because the decode side has
/// to be *total*: every possible byte sequence has to produce either a
/// message or a described failure, and never a thrown error that propagates
/// into the data-channel callback.
nonisolated enum RemoteControlMessageCoder {
    /// Hard ceiling on a control frame. Control messages are tens of bytes;
    /// anything near this is either a bug or a peer misusing the channel.
    static let maximumFrameBytes = 4 * 1024

    nonisolated enum DecodeFailure: Error, Equatable, Sendable {
        /// Not UTF-8, not JSON, or not a JSON object.
        case malformed
        /// A JSON object with no usable `type` string.
        case missingType
        /// A known `type` whose required fields are absent or the wrong kind.
        case invalidPayload(type: String)
        case tooLarge(byteCount: Int)

        var describedReason: String {
            switch self {
            case .malformed:
                return "frame was not a JSON object"
            case .missingType:
                return "frame had no \"type\" field"
            case .invalidPayload(let type):
                return "frame of type \"\(type)\" had missing or invalid fields"
            case .tooLarge(let byteCount):
                return "frame was \(byteCount) bytes, over the \(maximumFrameBytes) byte limit"
            }
        }
    }

    static func encode(_ message: RemoteControlMessage) -> Data {
        var object: [String: Any] = ["type": message.wireType]
        switch message {
        case .capturePhoto(let requestId),
             .captureStarted(let requestId):
            object["requestId"] = requestId
        case .captureCompleted(let requestId, let transferId, let byteCount, let chunkCount):
            object["requestId"] = requestId
            object["transferId"] = transferId
            object["byteCount"] = byteCount
            object["chunkCount"] = chunkCount
        case .captureFailed(let requestId, let reason):
            object["requestId"] = requestId
            object["reason"] = reason
        case .cameraSwitched(let position):
            object["position"] = position.rawValue
        case .sessionEnd(let reason):
            object["reason"] = reason
        case .cameraSwitch, .ping, .pong, .unrecognized:
            break
        }
        // `.sortedKeys` only so encoded frames are byte-stable, which makes
        // them comparable in tests.
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            // Unreachable: every value put in above is a String or Int.
            return Data(#"{"type":"unrecognized"}"#.utf8)
        }
        return data
    }

    /// - Returns: `.success` with a message - possibly `.unrecognized` for a
    ///   type this build doesn't know - or `.failure` describing why the
    ///   frame was unusable. Never throws.
    static func decode(_ data: Data) -> Result<RemoteControlMessage, DecodeFailure> {
        guard data.count <= maximumFrameBytes else {
            return .failure(.tooLarge(byteCount: data.count))
        }
        guard
            let parsed = try? JSONSerialization.jsonObject(with: data),
            let object = parsed as? [String: Any]
        else {
            return .failure(.malformed)
        }
        guard let type = object["type"] as? String, !type.isEmpty else {
            return .failure(.missingType)
        }

        func string(_ key: String) -> String? {
            (object[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        // Accepts any JSON number: JSONSerialization hands back NSNumber, and
        // a peer writing 11.0 instead of 11 shouldn't be a protocol error.
        func int(_ key: String) -> Int? {
            (object[key] as? NSNumber)?.intValue
        }

        switch type {
        case "capture_photo":
            guard let requestId = string("requestId") else { return .failure(.invalidPayload(type: type)) }
            return .success(.capturePhoto(requestId: requestId))

        case "capture_started":
            guard let requestId = string("requestId") else { return .failure(.invalidPayload(type: type)) }
            return .success(.captureStarted(requestId: requestId))

        case "capture_completed":
            guard
                let requestId = string("requestId"),
                let transferId = string("transferId"),
                let byteCount = int("byteCount"), byteCount > 0,
                let chunkCount = int("chunkCount"), chunkCount > 0
            else {
                return .failure(.invalidPayload(type: type))
            }
            return .success(.captureCompleted(
                requestId: requestId,
                transferId: transferId,
                byteCount: byteCount,
                chunkCount: chunkCount
            ))

        case "capture_failed":
            guard let requestId = string("requestId") else { return .failure(.invalidPayload(type: type)) }
            return .success(.captureFailed(requestId: requestId, reason: string("reason") ?? "unspecified"))

        case "camera_switch":
            return .success(.cameraSwitch)

        case "camera_switched":
            guard
                let raw = string("position"),
                let position = RemoteControlMessage.CameraPosition(rawValue: raw)
            else {
                return .failure(.invalidPayload(type: type))
            }
            return .success(.cameraSwitched(position: position))

        case "ping":
            return .success(.ping)

        case "pong":
            return .success(.pong)

        case "session_end":
            return .success(.sessionEnd(reason: string("reason") ?? "unspecified"))

        default:
            return .success(.unrecognized(type: type))
        }
    }
}
