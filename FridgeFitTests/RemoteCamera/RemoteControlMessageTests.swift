//
//  RemoteControlMessageTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// Test D: the data-channel control protocol.
///
/// The decode side has to be total - every byte sequence must produce either
/// a message or a described failure, never a throw into a WebRTC callback -
/// so the malformed cases get as much attention as the happy path.
final class RemoteControlMessageTests: XCTestCase {

    // MARK: - Round trips

    private func assertRoundTrips(_ message: RemoteControlMessage, file: StaticString = #filePath, line: UInt = #line) {
        let encoded = RemoteControlMessageCoder.encode(message)
        switch RemoteControlMessageCoder.decode(encoded) {
        case .success(let decoded):
            XCTAssertEqual(decoded, message, file: file, line: line)
        case .failure(let failure):
            XCTFail("expected a round trip, got \(failure)", file: file, line: line)
        }
    }

    func test_capturePhoto_roundTrips() {
        assertRoundTrips(.capturePhoto(requestId: "D4C5A1E0-0000-4000-8000-000000000001"))
    }

    func test_captureStarted_roundTrips() {
        assertRoundTrips(.captureStarted(requestId: "req-1"))
    }

    func test_captureCompleted_roundTrips() {
        assertRoundTrips(.captureCompleted(
            requestId: "req-1",
            transferId: "4FC6A8B2-0000-4000-8000-000000000002",
            byteCount: 184_320,
            chunkCount: 15
        ))
    }

    func test_captureFailed_roundTrips() {
        assertRoundTrips(.captureFailed(requestId: "req-1", reason: "no camera frame had arrived yet"))
    }

    func test_cameraSwitch_roundTrips() {
        assertRoundTrips(.cameraSwitch)
    }

    func test_cameraSwitched_roundTrips_forBothPositions() {
        assertRoundTrips(.cameraSwitched(position: .front))
        assertRoundTrips(.cameraSwitched(position: .back))
    }

    func test_ping_and_pong_roundTrip() {
        assertRoundTrips(.ping)
        assertRoundTrips(.pong)
    }

    func test_sessionEnd_roundTrips() {
        assertRoundTrips(.sessionEnd(reason: "the camera device left Camera Mode"))
    }

    // MARK: - Wire format

    func test_encode_producesTheDocumentedWireFormat() throws {
        let encoded = RemoteControlMessageCoder.encode(.capturePhoto(requestId: "abc"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(object["type"] as? String, "capture_photo")
        XCTAssertEqual(object["requestId"] as? String, "abc")
        XCTAssertEqual(object.count, 2, "no unexpected fields on the wire")
    }

    func test_decode_acceptsAHandWrittenFrame() {
        let frame = Data(#"{"type":"capture_photo","requestId":"abc"}"#.utf8)

        XCTAssertEqual(try? RemoteControlMessageCoder.decode(frame).get(), .capturePhoto(requestId: "abc"))
    }

    func test_decode_acceptsAFloatingPointChunkCount() {
        // A peer writing 15.0 instead of 15 is sloppy, not a protocol error.
        let frame = Data("""
        {"type":"capture_completed","requestId":"r","transferId":"t","byteCount":100.0,"chunkCount":15.0}
        """.utf8)

        XCTAssertEqual(
            try? RemoteControlMessageCoder.decode(frame).get(),
            .captureCompleted(requestId: "r", transferId: "t", byteCount: 100, chunkCount: 15)
        )
    }

    // MARK: - Malformed input

    func test_decode_rejectsNonJSON() {
        XCTAssertEqual(RemoteControlMessageCoder.decode(Data([0x00, 0x01, 0x02])), .failure(.malformed))
    }

    func test_decode_rejectsEmptyData() {
        XCTAssertEqual(RemoteControlMessageCoder.decode(Data()), .failure(.malformed))
    }

    func test_decode_rejectsAJSONArray() {
        XCTAssertEqual(RemoteControlMessageCoder.decode(Data("[1,2,3]".utf8)), .failure(.malformed))
    }

    func test_decode_rejectsAMissingType() {
        XCTAssertEqual(RemoteControlMessageCoder.decode(Data(#"{"requestId":"abc"}"#.utf8)), .failure(.missingType))
    }

    func test_decode_rejectsAnEmptyType() {
        XCTAssertEqual(RemoteControlMessageCoder.decode(Data(#"{"type":""}"#.utf8)), .failure(.missingType))
    }

    func test_decode_rejectsCapturePhotoWithoutARequestId() {
        XCTAssertEqual(
            RemoteControlMessageCoder.decode(Data(#"{"type":"capture_photo"}"#.utf8)),
            .failure(.invalidPayload(type: "capture_photo"))
        )
    }

    func test_decode_rejectsCaptureCompletedWithAZeroChunkCount() {
        let frame = Data("""
        {"type":"capture_completed","requestId":"r","transferId":"t","byteCount":10,"chunkCount":0}
        """.utf8)

        XCTAssertEqual(
            RemoteControlMessageCoder.decode(frame),
            .failure(.invalidPayload(type: "capture_completed"))
        )
    }

    func test_decode_rejectsAnUnknownCameraPosition() {
        XCTAssertEqual(
            RemoteControlMessageCoder.decode(Data(#"{"type":"camera_switched","position":"sideways"}"#.utf8)),
            .failure(.invalidPayload(type: "camera_switched"))
        )
    }

    func test_decode_rejectsAnOversizedFrame() {
        let padding = String(repeating: "x", count: RemoteControlMessageCoder.maximumFrameBytes)
        let frame = Data(#"{"type":"ping","pad":"\#(padding)"}"#.utf8)

        guard case .failure(.tooLarge) = RemoteControlMessageCoder.decode(frame) else {
            return XCTFail("expected an oversized frame to be rejected")
        }
    }

    /// Forward compatibility: a peer on a newer build must not be able to
    /// break this one by sending a message it doesn't know.
    func test_decode_mapsAnUnknownTypeToUnrecognized() {
        XCTAssertEqual(
            try? RemoteControlMessageCoder.decode(Data(#"{"type":"zoom_in","level":3}"#.utf8)).get(),
            .unrecognized(type: "zoom_in")
        )
    }

    func test_sessionEnd_toleratesAMissingReason() {
        XCTAssertEqual(
            try? RemoteControlMessageCoder.decode(Data(#"{"type":"session_end"}"#.utf8)).get(),
            .sessionEnd(reason: "unspecified")
        )
    }

    func test_captureFailed_toleratesAMissingReason() {
        XCTAssertEqual(
            try? RemoteControlMessageCoder.decode(Data(#"{"type":"capture_failed","requestId":"r"}"#.utf8)).get(),
            .captureFailed(requestId: "r", reason: "unspecified")
        )
    }

    func test_everyDecodeFailure_describesItself() {
        let failures: [RemoteControlMessageCoder.DecodeFailure] = [
            .malformed,
            .missingType,
            .invalidPayload(type: "capture_photo"),
            .tooLarge(byteCount: 9_999),
        ]
        for failure in failures {
            XCTAssertFalse(failure.describedReason.isEmpty)
        }
    }
}
