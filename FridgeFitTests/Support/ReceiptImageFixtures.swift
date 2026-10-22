//
//  ReceiptImageFixtures.swift
//  FridgeFitTests
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Synthetic images for exercising `ReceiptImageFingerprint`.
///
/// Built from explicit pixel arrays rather than bundled photographs so a
/// test can say exactly how two images differ - by one pixel, by their
/// dimensions, by nothing but the container they were encoded in. No real
/// receipt is checked into the test target.
enum ReceiptImageFixtures {

    /// Builds an opaque RGB image from a generator over pixel coordinates.
    ///
    /// - Parameter alphaInfo: lets a test produce the *same picture* in a
    ///   different memory layout, which is what proves canonicalisation is
    ///   doing its job.
    static func image(
        width: Int,
        height: Int,
        alphaInfo: CGImageAlphaInfo = .premultipliedLast,
        colorSpace: CGColorSpace? = nil,
        pixel: (Int, Int) -> (UInt8, UInt8, UInt8)
    ) -> CGImage {
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let (r, g, b) = pixel(x, y)
                let index = y * bytesPerRow + x * 4
                bytes[index] = r
                bytes[index + 1] = g
                bytes[index + 2] = b
                bytes[index + 3] = 255
            }
        }

        let space = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: alphaInfo.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        return context.makeImage()!
    }

    /// A deterministic, receipt-ish gradient. Stands in for "the demo
    /// receipt" wherever the test only needs *a specific picture*.
    static func demoLikeReceipt(width: Int = 48, height: Int = 80) -> CGImage {
        image(width: width, height: height) { x, y in
            let value = UInt8((x &* 5 &+ y &* 3) % 256)
            return (value, value &+ 90, value &+ 180)
        }
    }

    /// The same layout and palette, different content. Stands in for
    /// "a different Coles receipt" - visually similar, genuinely not the
    /// same picture.
    static func visuallySimilarDifferentReceipt(width: Int = 48, height: Int = 80) -> CGImage {
        image(width: width, height: height) { x, y in
            let value = UInt8((x &* 5 &+ y &* 3 &+ 7) % 256)
            return (value, value &+ 90, value &+ 180)
        }
    }

    /// `demoLikeReceipt` with exactly one pixel altered, to prove the match
    /// is exact and not perceptual.
    static func demoReceiptWithOnePixelChanged(width: Int = 48, height: Int = 80) -> CGImage {
        image(width: width, height: height) { x, y in
            let value = UInt8((x &* 5 &+ y &* 3) % 256)
            if x == width / 2, y == height / 2 {
                return (value ^ 0x01, value &+ 90, value &+ 180)
            }
            return (value, value &+ 90, value &+ 180)
        }
    }

    /// Rotates pixels so the *stored* data of the result, tagged with
    /// `orientation`, displays as `image` does when tagged `.up`.
    ///
    /// This is how a test produces "the same photograph, written to disk
    /// sideways with an EXIF tag", which is exactly what a camera does.
    static func reoriented(_ image: CGImage, as orientation: CGImagePropertyOrientation) -> CGImage {
        let uprightWidth = image.width
        let uprightHeight = image.height
        let upright = rgbaBytes(of: image)

        let swapsAxes: Bool
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored: swapsAxes = true
        default: swapsAxes = false
        }
        // Stored dimensions are the upright ones, transposed when the
        // orientation swaps axes.
        let storedWidth = swapsAxes ? uprightHeight : uprightWidth
        let storedHeight = swapsAxes ? uprightWidth : uprightHeight

        return self.image(width: storedWidth, height: storedHeight) { sx, sy in
            // Inverse of the destination-to-source map in
            // `ReceiptImageFingerprint`: given a stored coordinate, where
            // does it appear in the upright picture?
            let x: Int
            let y: Int
            switch orientation {
            case .up:            x = sx;                      y = sy
            case .upMirrored:    x = uprightWidth - 1 - sx;   y = sy
            case .down:          x = uprightWidth - 1 - sx;   y = uprightHeight - 1 - sy
            case .downMirrored:  x = sx;                      y = uprightHeight - 1 - sy
            case .leftMirrored:  x = sy;                      y = sx
            case .right:         x = uprightWidth - 1 - sy;   y = sx
            case .rightMirrored: x = uprightWidth - 1 - sy;   y = uprightHeight - 1 - sx
            case .left:          x = sy;                      y = uprightHeight - 1 - sx
            }

            let index = y * uprightWidth * 4 + x * 4
            return (upright[index], upright[index + 1], upright[index + 2])
        }
    }

    /// Round-trips an image through a real PNG file, so a test can prove the
    /// fingerprint survives encoding and carries no filename dependency.
    static func pngRoundTrip(_ image: CGImage) -> CGImage? {
        guard let data = pngData(image),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Re-encodes as PNG with extra metadata attached, leaving every pixel
    /// alone. The file's bytes change; the picture does not.
    static func pngDataWithExtraMetadata(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        let properties: [CFString: Any] = [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyPNGDescription: "harmless metadata change",
                kCGImagePropertyPNGSoftware: "FridgeFitTests"
            ] as [CFString: Any]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Reads an image back out as tightly packed sRGB RGBA.
    private static func rgbaBytes(of image: CGImage) -> [UInt8] {
        let bytesPerRow = image.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            )!
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
