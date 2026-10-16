//
//  SnapshotImageEncoder.swift
//  FridgeFit
//

import CoreGraphics
import Foundation
import UIKit

/// Turns a captured camera frame into bytes small enough to push through a
/// data channel, and back again on the far side.
///
/// A raw 4032x3024 frame is tens of megabytes. Downscaling to a long edge of
/// 1280 keeps a fridge shelf perfectly readable - it is more than the
/// existing receipt scanner needs from Vision - while landing in the low
/// hundreds of kilobytes, which is a handful of
/// `ImageTransferFrame.defaultPayloadBytes` chunks.
nonisolated enum SnapshotImageEncoder {
    /// Long edge after downscaling.
    static let maximumPixelDimension: CGFloat = 1280

    /// Starting JPEG quality. Stepped down if the first encode is too big.
    static let initialQuality: CGFloat = 0.7

    /// Target for the encoded bytes. Well under
    /// `ImageTransferFrame.maximumTransferBytes` so the cap is never the
    /// thing that fails a capture.
    static let targetByteCount = 600 * 1024

    nonisolated enum EncodeError: Error, Equatable, Sendable {
        case couldNotEncode
        /// Still over `ImageTransferFrame.maximumTransferBytes` after the
        /// lowest quality step. Practically unreachable at this resolution;
        /// here so the failure is named rather than being a silent oversize
        /// send.
        case irreduciblyLarge(byteCount: Int)

        var describedReason: String {
            switch self {
            case .couldNotEncode:
                return "the frame could not be encoded as JPEG"
            case .irreduciblyLarge(let byteCount):
                return "the encoded photo was \(byteCount) bytes, over the transfer limit"
            }
        }
    }

    /// Downscales and JPEG-encodes, stepping quality down until the result
    /// fits.
    static func encode(_ image: UIImage) throws -> Data {
        let scaled = downscaled(image)
        for quality in [initialQuality, 0.5, 0.35, 0.2] as [CGFloat] {
            guard let data = scaled.jpegData(compressionQuality: quality) else {
                throw EncodeError.couldNotEncode
            }
            if data.count <= targetByteCount || quality == 0.2 {
                guard data.count <= ImageTransferFrame.maximumTransferBytes else {
                    throw EncodeError.irreduciblyLarge(byteCount: data.count)
                }
                return data
            }
        }
        throw EncodeError.couldNotEncode
    }

    /// Rebuilds the image on the receiving side.
    ///
    /// - Returns: `nil` if the bytes aren't a decodable image, which is how a
    ///   truncated or corrupted transfer surfaces.
    static func decode(_ data: Data) -> UIImage? {
        UIImage(data: data)
    }

    /// Redraws `image` with its long edge no larger than
    /// `maximumPixelDimension`, in pixels.
    ///
    /// Works in pixels rather than points deliberately. `UIImage.size` is in
    /// points, so a frame measuring 1000x750 points at scale 3 is really
    /// 3000x2250 pixels - comparing its *point* size against a pixel budget
    /// would wave it straight through and produce a JPEG several times larger
    /// than intended.
    ///
    /// Always redraws, even when nothing needs shrinking, which also
    /// normalises orientation: a frame carrying a rotation flag gets it baked
    /// into the pixels here rather than surviving as EXIF for the receiver to
    /// reinterpret.
    static func downscaled(_ image: UIImage) -> UIImage {
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let longEdge = max(pixelSize.width, pixelSize.height)
        guard longEdge > 0 else { return image }

        let ratio = min(1, maximumPixelDimension / longEdge)
        let targetSize = CGSize(
            width: max(1, (pixelSize.width * ratio).rounded()),
            height: max(1, (pixelSize.height * ratio).rounded())
        )

        let format = UIGraphicsImageRendererFormat.default()
        // 1.0 so `targetSize` is interpreted as pixels, not points.
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
