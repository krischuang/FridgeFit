//
//  ImageTransferFrame.swift
//  FridgeFit
//

import Foundation

/// Binary framing for sending a captured JPEG over the WebRTC data channel.
///
/// Why not just send the JPEG as one `RTCDataBuffer`? SCTP data channels have
/// a per-message size limit that varies by peer, and a large single message
/// blocks the channel for the whole send. Why not base64 it into a JSON
/// control message? That is a third more bytes and would mean holding the
/// whole image as a string on both sides. So: fixed-size header, small
/// binary chunks, reassembled by `ImageTransferAssembler`.
///
/// Firestore is not involved in this path at all. Signaling documents carry
/// SDP and ICE only - image bytes go peer-to-peer.
///
/// ## Header layout (27 bytes, big-endian)
///
/// ```
/// offset  size  field
/// 0       2     magic 0x46 0x46 ("FF")
/// 2       1     version (currently 1)
/// 3       16    transferId, raw UUID bytes
/// 19      4     chunkIndex
/// 23      4     chunkCount
/// 27      ...   payload
/// ```
nonisolated enum ImageTransferFrame {
    static let magic: [UInt8] = [0x46, 0x46]
    static let version: UInt8 = 1
    static let headerByteCount = 27

    /// Payload bytes per chunk.
    ///
    /// 16 KB is the conservative floor for SCTP message size across WebRTC
    /// implementations; staying well under it avoids negotiating
    /// `maxMessageSize` with the peer.
    static let defaultPayloadBytes = 12 * 1024

    /// Ceiling on a whole transfer. A fridge snapshot re-encoded by
    /// `SnapshotImageEncoder` lands around 150-400 KB, so this is ~10x
    /// headroom and still small enough that a malicious or buggy peer can't
    /// make the controller buffer unboundedly.
    static let maximumTransferBytes = 4 * 1024 * 1024

    /// Matches `maximumTransferBytes` at the default payload size, with
    /// rounding headroom. Checked before allocating, so a forged header
    /// claiming a huge `chunkCount` is rejected rather than reserved for.
    static let maximumChunkCount = 512

    nonisolated struct Header: Equatable, Sendable {
        let transferId: UUID
        let chunkIndex: Int
        let chunkCount: Int
    }

    nonisolated enum FrameError: Error, Equatable, Sendable {
        case emptyPayload
        case payloadTooLarge(byteCount: Int)
        case tooManyChunks(chunkCount: Int)
    }

    nonisolated enum ParseError: Error, Equatable, Sendable {
        case shorterThanHeader(byteCount: Int)
        case badMagic
        case unsupportedVersion(UInt8)
        case invalidChunkCount(Int)
        case chunkIndexOutOfRange(index: Int, count: Int)

        var describedReason: String {
            switch self {
            case .shorterThanHeader(let byteCount):
                return "frame was \(byteCount) bytes, shorter than the \(ImageTransferFrame.headerByteCount) byte header"
            case .badMagic:
                return "frame did not start with the image-transfer magic bytes"
            case .unsupportedVersion(let version):
                return "frame used unsupported framing version \(version)"
            case .invalidChunkCount(let count):
                return "frame declared an unusable chunk count of \(count)"
            case .chunkIndexOutOfRange(let index, let count):
                return "frame declared chunk \(index) of \(count)"
            }
        }
    }

    /// Splits `payload` into wire frames.
    ///
    /// - Throws: `FrameError` if the payload is empty or past the transfer
    ///   ceiling - caught at the call site and reported as a `captureFailed`
    ///   so the controller isn't left waiting on chunks that never come.
    static func chunk(
        payload: Data,
        transferId: UUID,
        payloadBytesPerChunk: Int = defaultPayloadBytes
    ) throws -> [Data] {
        guard !payload.isEmpty else { throw FrameError.emptyPayload }
        guard payload.count <= maximumTransferBytes else {
            throw FrameError.payloadTooLarge(byteCount: payload.count)
        }
        let perChunk = max(1, payloadBytesPerChunk)
        let chunkCount = (payload.count + perChunk - 1) / perChunk
        guard chunkCount <= maximumChunkCount else {
            throw FrameError.tooManyChunks(chunkCount: chunkCount)
        }

        var frames: [Data] = []
        frames.reserveCapacity(chunkCount)
        for index in 0..<chunkCount {
            let start = payload.index(payload.startIndex, offsetBy: index * perChunk)
            let end = payload.index(start, offsetBy: min(perChunk, payload.distance(from: start, to: payload.endIndex)))
            var frame = Data(capacity: headerByteCount + perChunk)
            frame.append(contentsOf: magic)
            frame.append(version)
            frame.append(contentsOf: bytes(of: transferId))
            frame.append(contentsOf: bigEndianBytes(UInt32(index)))
            frame.append(contentsOf: bigEndianBytes(UInt32(chunkCount)))
            frame.append(payload[start..<end])
            frames.append(frame)
        }
        return frames
    }

    /// Reads a frame's header and payload.
    ///
    /// - Throws: `ParseError`. Callers treat any failure as "this was not one
    ///   of our frames" and drop it; nothing here can corrupt an in-progress
    ///   transfer.
    static func parse(_ frame: Data) throws -> (header: Header, payload: Data) {
        guard frame.count >= headerByteCount else {
            throw ParseError.shorterThanHeader(byteCount: frame.count)
        }
        // Re-index from zero: a Data sliced out of a larger buffer keeps the
        // parent's indices, so subscripting by literal offsets on the
        // incoming frame would read the wrong bytes.
        let bytes = [UInt8](frame)
        guard bytes[0] == magic[0], bytes[1] == magic[1] else { throw ParseError.badMagic }
        guard bytes[2] == version else { throw ParseError.unsupportedVersion(bytes[2]) }

        // `uuid_t` is a 16-tuple of UInt8 with no default initialiser, hence
        // the explicit zero tuple before copying the bytes in.
        var uuidBytes: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &uuidBytes) { raw in
            for offset in 0..<16 { raw[offset] = bytes[3 + offset] }
        }
        let transferId = UUID(uuid: uuidBytes)
        let chunkIndex = Int(readBigEndianUInt32(bytes, at: 19))
        let chunkCount = Int(readBigEndianUInt32(bytes, at: 23))

        guard chunkCount > 0, chunkCount <= maximumChunkCount else {
            throw ParseError.invalidChunkCount(chunkCount)
        }
        guard chunkIndex >= 0, chunkIndex < chunkCount else {
            throw ParseError.chunkIndexOutOfRange(index: chunkIndex, count: chunkCount)
        }

        let payload = Data(bytes[headerByteCount...])
        return (Header(transferId: transferId, chunkIndex: chunkIndex, chunkCount: chunkCount), payload)
    }

    // MARK: - Byte helpers

    private static func bytes(of uuid: UUID) -> [UInt8] {
        withUnsafeBytes(of: uuid.uuid) { Array($0) }
    }

    private static func bigEndianBytes(_ value: UInt32) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: value >> 24),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value),
        ]
    }

    private static func readBigEndianUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }
}

/// Reassembles `ImageTransferFrame` chunks back into the original bytes.
///
/// Tolerates out-of-order and duplicate chunks because that's what an
/// unreliable path would deliver - the prototype's data channel is ordered
/// and reliable, so in practice chunks arrive in sequence, but relying on
/// that would make the receiver fragile if the channel config ever changed.
///
/// Not thread-safe; owned by whichever object pumps the data channel.
nonisolated final class ImageTransferAssembler {
    nonisolated enum Outcome: Equatable, Sendable {
        /// Chunk accepted, more expected.
        case incomplete(received: Int, expected: Int)
        /// Last missing chunk arrived; `data` is the original payload.
        case completed(transferId: UUID, data: Data)
        /// Frame was not usable. The in-progress transfer, if any, is intact.
        case rejected(reason: String)
    }

    private struct PartialTransfer {
        let chunkCount: Int
        var chunks: [Int: Data]
        var byteCount: Int
    }

    private var transfers: [UUID: PartialTransfer] = [:]

    /// Transfers held at once. The prototype only ever has one in flight;
    /// this just stops a peer opening thousands of partial transfers.
    private static let maximumConcurrentTransfers = 4

    func accept(frame: Data) -> Outcome {
        let parsed: (header: ImageTransferFrame.Header, payload: Data)
        do {
            parsed = try ImageTransferFrame.parse(frame)
        } catch let error as ImageTransferFrame.ParseError {
            return .rejected(reason: error.describedReason)
        } catch {
            return .rejected(reason: "frame could not be parsed")
        }

        let header = parsed.header
        var transfer = transfers[header.transferId] ?? PartialTransfer(
            chunkCount: header.chunkCount,
            chunks: [:],
            byteCount: 0
        )

        // A peer that changes its mind about the chunk count mid-transfer is
        // either buggy or hostile - drop the whole transfer rather than
        // reassembling a mix of two different images.
        guard transfer.chunkCount == header.chunkCount else {
            transfers[header.transferId] = nil
            return .rejected(reason: "chunk count changed mid-transfer")
        }
        if transfers[header.transferId] == nil,
           transfers.count >= Self.maximumConcurrentTransfers {
            return .rejected(reason: "too many concurrent image transfers")
        }
        // Duplicate: already have this index, nothing to do.
        if transfer.chunks[header.chunkIndex] != nil {
            transfers[header.transferId] = transfer
            return .incomplete(received: transfer.chunks.count, expected: transfer.chunkCount)
        }
        guard transfer.byteCount + parsed.payload.count <= ImageTransferFrame.maximumTransferBytes else {
            transfers[header.transferId] = nil
            return .rejected(reason: "transfer exceeded the \(ImageTransferFrame.maximumTransferBytes) byte limit")
        }

        transfer.chunks[header.chunkIndex] = parsed.payload
        transfer.byteCount += parsed.payload.count

        guard transfer.chunks.count == transfer.chunkCount else {
            transfers[header.transferId] = transfer
            return .incomplete(received: transfer.chunks.count, expected: transfer.chunkCount)
        }

        transfers[header.transferId] = nil
        var assembled = Data(capacity: transfer.byteCount)
        for index in 0..<transfer.chunkCount {
            // Safe: the count check above means every index 0..<chunkCount is
            // present, since indices outside that range are rejected in parse.
            assembled.append(transfer.chunks[index] ?? Data())
        }
        return .completed(transferId: header.transferId, data: assembled)
    }

    /// Forgets any partial transfers. Called when a session ends so a
    /// half-received image can't be completed by a later, unrelated session.
    func reset() {
        transfers.removeAll()
    }

    var hasPartialTransfers: Bool { !transfers.isEmpty }
}
