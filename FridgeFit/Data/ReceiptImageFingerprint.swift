//
//  ReceiptImageFingerprint.swift
//  FridgeFit
//

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// An exact, content-addressed identity for a receipt photo.
///
/// ## Why not the file's SHA-256
///
/// Hashing the picked file's bytes is the obvious thing and it is the wrong
/// thing here. `ReceiptScannerView` loads a photo through
/// `PhotosPicker` -> `loadTransferable(type: Data.self)` -> `UIImage(data:)`,
/// and what comes back is whatever representation the Photos library chose
/// to hand over. Re-exporting, syncing through iCloud Photos, or an edit
/// that changes nothing visible can all change those bytes while the picture
/// stays identical. A byte hash would miss the match and the demo would fall
/// back to a ten-second scan. The raw file hash is still useful for
/// identifying the *original fixture on disk*, which is a different job, and
/// is recorded in the demo documentation rather than used as a cache key.
///
/// ## What is hashed instead
///
/// The pixels, canonicalised so that only genuinely different pictures
/// produce different fingerprints:
///
/// 1. The image is drawn once into a fixed bitmap format - sRGB, 8 bits per
///    channel, premultiplied RGBA, tightly packed rows. This pins the colour
///    space and the memory layout, so a 16-bit or Display-P3 or
///    alpha-first source cannot change the answer by being stored
///    differently.
/// 2. The result is remapped to upright according to the photo's EXIF
///    orientation, so the same picture tagged `.up` and `.right` agrees with
///    itself.
/// 3. SHA-256 is taken over a domain-separated preimage of the algorithm
///    version, the upright dimensions and the upright pixel bytes.
///
/// The dimensions are hashed as well as the pixels so two images cannot
/// collide merely by sharing a byte sequence at different shapes.
///
/// ## This is exact matching, deliberately
///
/// There is no downscaling, no perceptual hash, no feature matching and no
/// tolerance. One different pixel is a different fingerprint, which is the
/// property the cache needs: a second Coles receipt, a re-crop of this one,
/// or a fresh photo of the same piece of paper must all miss and go to Apple
/// Intelligence. Fuzzy matching would make the cache capable of answering
/// for a receipt nobody verified.
nonisolated struct ReceiptImageFingerprint: Hashable, Codable, CustomStringConvertible {
    /// Bumped if anything above changes. Old fingerprints then stop
    /// comparing equal to new ones, which is what should happen: they
    /// describe a different canonicalisation.
    static let algorithmVersion = 1

    private static let domainSeparator = "FridgeFit.ReceiptImageFingerprint.v\(algorithmVersion)"

    /// `v<algorithmVersion>:<64 hex characters>`.
    let value: String

    init(value: String) {
        self.value = value
    }

    var description: String { value }

    /// A short form for DEBUG diagnostics and the preparation screen, where
    /// the full 64 characters are unreadable and unnecessary.
    var abbreviated: String {
        guard let hex = value.split(separator: ":").last, hex.count > 12 else { return value }
        return "\(hex.prefix(8))…\(hex.suffix(4))"
    }

    // MARK: - Computing

    /// Fingerprints a decoded image.
    ///
    /// Returns `nil` only when the image cannot be drawn at all - a zero
    /// dimension, or a bitmap context the system refuses to allocate. A
    /// `nil` fingerprint is treated by callers as "no cache identity", which
    /// falls back to a normal scan rather than failing it.
    ///
    /// Deliberately `nonisolated`: this walks several megabytes of pixels
    /// and must never run on the main actor. In this target
    /// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) that annotation is what
    /// keeps it off.
    static func make(
        of image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) -> ReceiptImageFingerprint? {
        guard let canonical = CanonicalBitmap(drawing: image) else { return nil }
        let upright = canonical.uprighted(for: orientation)

        var hasher = SHA256()
        hasher.update(data: Data(domainSeparator.utf8))
        hasher.update(data: bigEndianBytes(UInt32(upright.width)))
        hasher.update(data: bigEndianBytes(UInt32(upright.height)))
        upright.pixels.withUnsafeBufferPointer { hasher.update(bufferPointer: UnsafeRawBufferPointer($0)) }

        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return ReceiptImageFingerprint(value: "v\(algorithmVersion):\(hex)")
    }

    private static func bigEndianBytes(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}

// MARK: - Canonical bitmap

/// An image reduced to one fixed, fully specified pixel layout.
///
/// Everything variable about how a `CGImage` can be stored - colour space,
/// bit depth, alpha position, row padding - is normalised here, once, so the
/// fingerprint is a function of the picture rather than of the file that
/// carried it.
private struct CanonicalBitmap {
    let width: Int
    let height: Int
    /// Row-major, top row first, 4 bytes per pixel, no row padding.
    let pixels: [UInt8]

    private static let bytesPerPixel = 4

    /// Draws `image` into the canonical format at its native pixel size.
    ///
    /// `interpolationQuality = .none` and a 1:1 destination rect mean no
    /// resampling happens; this is a format conversion, not a resize.
    init?(drawing image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * Self.bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)

        let drew = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }

            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }

        self.width = width
        self.height = height
        self.pixels = buffer
    }

    private init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Reorders the stored pixels into upright reading order.
    ///
    /// The EXIF orientation says where the stored data's first row and first
    /// column sit in the *displayed* picture; this inverts that into a
    /// destination-to-source index map. It is a plain remap rather than a
    /// `CGAffineTransform` draw so that no rotation ever passes through
    /// interpolation or a second colour conversion - the output bytes are
    /// exactly the input bytes in a different order, which is what makes two
    /// differently-tagged copies of one photo hash identically.
    func uprighted(for orientation: CGImagePropertyOrientation) -> CanonicalBitmap {
        // The common case for a library photo. Nothing to do, and skipping
        // the copy keeps the fast path fast.
        if orientation == .up { return self }

        let swapsAxes: Bool
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: swapsAxes = true
        default: swapsAxes = false
        }

        let outWidth = swapsAxes ? height : width
        let outHeight = swapsAxes ? width : height
        let bytesPerPixel = Self.bytesPerPixel
        let sourceStride = width * bytesPerPixel
        let destinationStride = outWidth * bytesPerPixel

        var output = [UInt8](repeating: 0, count: destinationStride * outHeight)

        pixels.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                for y in 0 ..< outHeight {
                    for x in 0 ..< outWidth {
                        // (sourceX, sourceY) indexes the stored bitmap;
                        // (x, y) indexes the upright picture, y from the top.
                        let sourceX: Int
                        let sourceY: Int
                        switch orientation {
                        case .up:
                            sourceX = x;                 sourceY = y
                        case .upMirrored:
                            sourceX = width - 1 - x;      sourceY = y
                        case .down:
                            sourceX = width - 1 - x;      sourceY = height - 1 - y
                        case .downMirrored:
                            sourceX = x;                 sourceY = height - 1 - y
                        case .leftMirrored:
                            sourceX = y;                 sourceY = x
                        case .right:
                            sourceX = y;                 sourceY = height - 1 - x
                        case .rightMirrored:
                            sourceX = width - 1 - y;      sourceY = height - 1 - x
                        case .left:
                            sourceX = width - 1 - y;      sourceY = x
                        }

                        let sourceIndex = sourceY * sourceStride + sourceX * bytesPerPixel
                        let destinationIndex = y * destinationStride + x * bytesPerPixel
                        destination[destinationIndex] = source[sourceIndex]
                        destination[destinationIndex + 1] = source[sourceIndex + 1]
                        destination[destinationIndex + 2] = source[sourceIndex + 2]
                        destination[destinationIndex + 3] = source[sourceIndex + 3]
                    }
                }
            }
        }

        return CanonicalBitmap(width: outWidth, height: outHeight, pixels: output)
    }
}
