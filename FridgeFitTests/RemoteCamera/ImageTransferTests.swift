//
//  ImageTransferTests.swift
//  FridgeFitTests
//

import UIKit
import XCTest
@testable import FridgeFit

/// Test E: chunking a captured photo, pushing it through the framing, and
/// reconstructing a displayable image on the other side.
final class ImageTransferTests: XCTestCase {

    // MARK: - Fixtures

    /// A scale-1 image, so `UIImage.size` and its pixel dimensions are the
    /// same number. `TestImage.makeUIImage` uses the default renderer format,
    /// whose scale is the screen's - harmless for the receipt tests that
    /// share it, but it would make the size assertions here ambiguous.
    private func makeImage(pixelWidth: Int, pixelHeight: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let size = CGSize(width: pixelWidth, height: pixelHeight)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Chunking

    func test_chunk_splitsPayloadAcrossFrames() throws {
        let payload = Data(repeating: 0xAB, count: 30_000)

        let frames = try ImageTransferFrame.chunk(
            payload: payload,
            transferId: UUID(),
            payloadBytesPerChunk: 12_000
        )

        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].count, ImageTransferFrame.headerByteCount + 12_000)
        XCTAssertEqual(frames[1].count, ImageTransferFrame.headerByteCount + 12_000)
        // Remainder, not padded out.
        XCTAssertEqual(frames[2].count, ImageTransferFrame.headerByteCount + 6_000)
    }

    func test_chunk_producesASingleFrameForASmallPayload() throws {
        let frames = try ImageTransferFrame.chunk(payload: Data([1, 2, 3]), transferId: UUID())

        XCTAssertEqual(frames.count, 1)
    }

    func test_chunk_rejectsAnEmptyPayload() {
        XCTAssertThrowsError(try ImageTransferFrame.chunk(payload: Data(), transferId: UUID())) { error in
            XCTAssertEqual(error as? ImageTransferFrame.FrameError, .emptyPayload)
        }
    }

    func test_chunk_rejectsAPayloadOverTheTransferLimit() {
        let payload = Data(repeating: 0, count: ImageTransferFrame.maximumTransferBytes + 1)

        XCTAssertThrowsError(try ImageTransferFrame.chunk(payload: payload, transferId: UUID())) { error in
            XCTAssertEqual(
                error as? ImageTransferFrame.FrameError,
                .payloadTooLarge(byteCount: ImageTransferFrame.maximumTransferBytes + 1)
            )
        }
    }

    func test_chunk_rejectsAChunkCountOverTheLimit() {
        // Small chunks against a large-ish payload: under the byte ceiling,
        // over the frame-count ceiling.
        let payload = Data(repeating: 0, count: 10_000)

        XCTAssertThrowsError(
            try ImageTransferFrame.chunk(payload: payload, transferId: UUID(), payloadBytesPerChunk: 1)
        ) { error in
            guard case .tooManyChunks = error as? ImageTransferFrame.FrameError else {
                return XCTFail("expected tooManyChunks, got \(error)")
            }
        }
    }

    // MARK: - Header parsing

    func test_parse_readsBackTheHeaderItWrote() throws {
        let transferId = UUID()
        let frames = try ImageTransferFrame.chunk(
            payload: Data(repeating: 7, count: 25_000),
            transferId: transferId,
            payloadBytesPerChunk: 10_000
        )

        let (header, payload) = try ImageTransferFrame.parse(frames[1])

        XCTAssertEqual(header.transferId, transferId)
        XCTAssertEqual(header.chunkIndex, 1)
        XCTAssertEqual(header.chunkCount, 3)
        XCTAssertEqual(payload.count, 10_000)
    }

    func test_parse_rejectsAFrameShorterThanTheHeader() {
        XCTAssertThrowsError(try ImageTransferFrame.parse(Data([0x46, 0x46, 0x01]))) { error in
            XCTAssertEqual(error as? ImageTransferFrame.ParseError, .shorterThanHeader(byteCount: 3))
        }
    }

    func test_parse_rejectsBadMagic() throws {
        var frame = try ImageTransferFrame.chunk(payload: Data([1]), transferId: UUID())[0]
        frame[0] = 0x00

        XCTAssertThrowsError(try ImageTransferFrame.parse(frame)) { error in
            XCTAssertEqual(error as? ImageTransferFrame.ParseError, .badMagic)
        }
    }

    func test_parse_rejectsAnUnsupportedVersion() throws {
        var frame = try ImageTransferFrame.chunk(payload: Data([1]), transferId: UUID())[0]
        frame[2] = 0x99

        XCTAssertThrowsError(try ImageTransferFrame.parse(frame)) { error in
            XCTAssertEqual(error as? ImageTransferFrame.ParseError, .unsupportedVersion(0x99))
        }
    }

    func test_parse_rejectsAChunkIndexBeyondTheChunkCount() throws {
        var frame = try ImageTransferFrame.chunk(payload: Data([1]), transferId: UUID())[0]
        // chunkIndex lives at offset 19..22, big-endian. Forge index 5 of 1.
        frame[22] = 5

        XCTAssertThrowsError(try ImageTransferFrame.parse(frame)) { error in
            XCTAssertEqual(
                error as? ImageTransferFrame.ParseError,
                .chunkIndexOutOfRange(index: 5, count: 1)
            )
        }
    }

    /// A frame sliced out of a larger buffer keeps the parent's indices, so
    /// parsing by literal offsets has to re-index. If it didn't, a
    /// concatenated receive buffer would be read at the wrong offsets.
    func test_parse_handlesAFrameSlicedFromALargerBuffer() throws {
        let frames = try ImageTransferFrame.chunk(payload: Data(repeating: 9, count: 50), transferId: UUID())
        var buffer = Data(repeating: 0xFF, count: 64)
        buffer.append(frames[0])
        let slice = buffer[64...]

        let (header, payload) = try ImageTransferFrame.parse(slice)

        XCTAssertEqual(header.chunkIndex, 0)
        XCTAssertEqual(payload, Data(repeating: 9, count: 50))
    }

    // MARK: - Reassembly

    func test_assembler_reconstructsTheOriginalPayload() throws {
        let payload = Data((0..<40_000).map { UInt8($0 % 251) })
        let transferId = UUID()
        let frames = try ImageTransferFrame.chunk(
            payload: payload,
            transferId: transferId,
            payloadBytesPerChunk: 7_000
        )
        let assembler = ImageTransferAssembler()

        var outcome: ImageTransferAssembler.Outcome?
        for frame in frames {
            outcome = assembler.accept(frame: frame)
        }

        XCTAssertEqual(outcome, .completed(transferId: transferId, data: payload))
        XCTAssertFalse(assembler.hasPartialTransfers)
    }

    func test_assembler_reportsProgressWhileIncomplete() throws {
        let frames = try ImageTransferFrame.chunk(
            payload: Data(repeating: 3, count: 20_000),
            transferId: UUID(),
            payloadBytesPerChunk: 5_000
        )
        let assembler = ImageTransferAssembler()

        XCTAssertEqual(assembler.accept(frame: frames[0]), .incomplete(received: 1, expected: 4))
        XCTAssertEqual(assembler.accept(frame: frames[1]), .incomplete(received: 2, expected: 4))
        XCTAssertTrue(assembler.hasPartialTransfers)
    }

    func test_assembler_handlesOutOfOrderChunks() throws {
        let payload = Data((0..<18_000).map { UInt8($0 % 97) })
        let frames = try ImageTransferFrame.chunk(
            payload: payload,
            transferId: UUID(),
            payloadBytesPerChunk: 5_000
        )
        let assembler = ImageTransferAssembler()

        var outcome: ImageTransferAssembler.Outcome?
        for frame in frames.reversed() {
            outcome = assembler.accept(frame: frame)
        }

        guard case .completed(_, let reassembled) = outcome else {
            return XCTFail("expected completion, got \(String(describing: outcome))")
        }
        XCTAssertEqual(reassembled, payload, "chunks must be ordered by index, not arrival")
    }

    func test_assembler_ignoresDuplicateChunks() throws {
        let payload = Data(repeating: 5, count: 10_000)
        let frames = try ImageTransferFrame.chunk(
            payload: payload,
            transferId: UUID(),
            payloadBytesPerChunk: 5_000
        )
        let assembler = ImageTransferAssembler()

        XCTAssertEqual(assembler.accept(frame: frames[0]), .incomplete(received: 1, expected: 2))
        XCTAssertEqual(
            assembler.accept(frame: frames[0]),
            .incomplete(received: 1, expected: 2),
            "a repeated chunk must not count twice"
        )

        guard case .completed(_, let reassembled) = assembler.accept(frame: frames[1]) else {
            return XCTFail("expected completion after the second distinct chunk")
        }
        XCTAssertEqual(reassembled, payload)
    }

    func test_assembler_rejectsAnUnparseableFrameWithoutLosingProgress() throws {
        let payload = Data(repeating: 1, count: 10_000)
        let frames = try ImageTransferFrame.chunk(
            payload: payload,
            transferId: UUID(),
            payloadBytesPerChunk: 5_000
        )
        let assembler = ImageTransferAssembler()
        _ = assembler.accept(frame: frames[0])

        guard case .rejected = assembler.accept(frame: Data([0x01, 0x02])) else {
            return XCTFail("expected a short frame to be rejected")
        }

        guard case .completed(_, let reassembled) = assembler.accept(frame: frames[1]) else {
            return XCTFail("the in-progress transfer should have survived the bad frame")
        }
        XCTAssertEqual(reassembled, payload)
    }

    func test_assembler_dropsATransferWhoseChunkCountChanges() throws {
        let transferId = UUID()
        let first = try ImageTransferFrame.chunk(
            payload: Data(repeating: 1, count: 10_000),
            transferId: transferId,
            payloadBytesPerChunk: 5_000
        )[0]
        // Same transferId, different chunk count - either a bug or a peer
        // trying to splice two images together.
        let conflicting = try ImageTransferFrame.chunk(
            payload: Data(repeating: 2, count: 15_000),
            transferId: transferId,
            payloadBytesPerChunk: 5_000
        )[0]
        let assembler = ImageTransferAssembler()
        _ = assembler.accept(frame: first)

        guard case .rejected(let reason) = assembler.accept(frame: conflicting) else {
            return XCTFail("expected a changed chunk count to be rejected")
        }
        XCTAssertTrue(reason.contains("chunk count"))
        XCTAssertFalse(assembler.hasPartialTransfers)
    }

    func test_assembler_reset_discardsPartialTransfers() throws {
        let frames = try ImageTransferFrame.chunk(
            payload: Data(repeating: 1, count: 10_000),
            transferId: UUID(),
            payloadBytesPerChunk: 5_000
        )
        let assembler = ImageTransferAssembler()
        _ = assembler.accept(frame: frames[0])
        XCTAssertTrue(assembler.hasPartialTransfers)

        assembler.reset()

        XCTAssertFalse(assembler.hasPartialTransfers)
    }

    // MARK: - End to end, with a real image

    /// The whole snapshot path: UIImage in, chunks over the wire, UIImage out.
    func test_endToEnd_imageSurvivesEncodeChunkReassembleDecode() throws {
        let original = makeImage(pixelWidth: 1600, pixelHeight: 1200)

        let encoded = try SnapshotImageEncoder.encode(original)
        let transferId = UUID()
        let frames = try ImageTransferFrame.chunk(payload: encoded, transferId: transferId)

        let assembler = ImageTransferAssembler()
        var received: Data?
        for frame in frames {
            if case .completed(_, let data) = assembler.accept(frame: frame) {
                received = data
            }
        }

        let payload = try XCTUnwrap(received, "the transfer should have completed")
        XCTAssertEqual(payload, encoded)

        let reconstructed = try XCTUnwrap(SnapshotImageEncoder.decode(payload))
        // Downscaled to a 1280 long edge on the way out, so this is the
        // expected size rather than the original 1600x1200.
        XCTAssertEqual(reconstructed.size.width, 1280, accuracy: 1)
        XCTAssertEqual(reconstructed.size.height, 960, accuracy: 1)
    }

    func test_encode_downscalesALargeImageUnderTheTargetSize() throws {
        let large = makeImage(pixelWidth: 4032, pixelHeight: 3024)

        let encoded = try SnapshotImageEncoder.encode(large)

        XCTAssertLessThanOrEqual(encoded.count, SnapshotImageEncoder.targetByteCount)
        XCTAssertLessThanOrEqual(encoded.count, ImageTransferFrame.maximumTransferBytes)
    }

    func test_encode_leavesASmallImageAtItsOwnSize() throws {
        let small = makeImage(pixelWidth: 320, pixelHeight: 240)

        let decoded = try XCTUnwrap(SnapshotImageEncoder.decode(try SnapshotImageEncoder.encode(small)))

        XCTAssertEqual(decoded.size.width, 320, accuracy: 1)
        XCTAssertEqual(decoded.size.height, 240, accuracy: 1)
    }

    /// The point-versus-pixel trap: a modest *point* size at scale 3 is a
    /// large image in pixels, and must still be brought under the limit.
    func test_encode_downscalesByPixelsNotPoints() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 3
        let retinaImage = UIGraphicsImageRenderer(
            size: CGSize(width: 1000, height: 750),
            format: format
        ).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1000, height: 750))
        }
        XCTAssertEqual(retinaImage.scale, 3, "fixture should be a Retina-scale image")

        let decoded = try XCTUnwrap(SnapshotImageEncoder.decode(try SnapshotImageEncoder.encode(retinaImage)))

        // 1000x750 points at scale 3 is 3000x2250 pixels, so the long edge
        // has to come down to 1280 - not be waved through as "1000 < 1280".
        XCTAssertEqual(decoded.size.width, SnapshotImageEncoder.maximumPixelDimension, accuracy: 1)
        XCTAssertEqual(decoded.size.height, 960, accuracy: 1)
    }

    func test_decode_returnsNilForBytesThatArentAnImage() {
        XCTAssertNil(SnapshotImageEncoder.decode(Data(repeating: 0x42, count: 1_024)))
    }

    func test_decode_returnsNilForATruncatedTransfer() throws {
        let encoded = try SnapshotImageEncoder.encode(makeImage(pixelWidth: 800, pixelHeight: 600))

        // Keep only the first 40 bytes: a valid JPEG header, no image data.
        XCTAssertNil(SnapshotImageEncoder.decode(encoded.prefix(40)))
    }
}
