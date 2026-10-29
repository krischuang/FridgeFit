//
//  AppIconOpacityTests.swift
//  FridgeFitTests
//
//  App Store packaging rules the compiler cannot enforce.
//
//  The 1024pt marketing icon must be a flat, fully opaque square with no
//  corner rounding baked in - iOS applies its own mask, so a pre-rounded
//  icon is rounded twice and shows pale fringes at the corners. A build with
//  a transparent icon compiles, installs, runs and looks fine in the
//  simulator; the only thing that catches it is App Review. So it is caught
//  here instead.
//
//  The icon that shipped before this test existed had 40% of its pixels
//  fully transparent, every remaining pixel at alpha 254, and transparent
//  corners. See `tools/appicon/make-opaque-icon.swift`.
//

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FridgeFit

final class AppIconOpacityTests: XCTestCase {

    /// The asset-catalog source, read from the repository rather than the
    /// built product: the compiled `.car` is opaque by the time Xcode has
    /// finished with it, which would make this test pass on an icon that
    /// could not be submitted.
    private static var iconURL: URL {
        var url = URL(fileURLWithPath: #filePath)
        // .../FridgeFitTests/Assets/AppIconOpacityTests.swift
        for _ in 0 ..< 3 { url.deleteLastPathComponent() }
        return url
            .appendingPathComponent("FridgeFit/Assets.xcassets/AppIcon.appiconset/fridgefit_icon.png")
    }

    private func loadIcon() throws -> CGImage {
        let url = Self.iconURL
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path),
            "App icon not found at \(url.path)"
        )
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw XCTSkip("Could not decode the app icon")
        }
        return image
    }

    /// Every pixel, read back as RGBA.
    private func pixels(of image: CGImage) -> (data: [UInt8], width: Int, height: Int) {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        data.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                // Not premultiplied: a premultiplied read of a transparent
                // pixel is indistinguishable from an opaque black one, which
                // is exactly the case this test must not miss.
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (data, width, height)
    }

    // MARK: - Dimensions

    func test_appIcon_is1024Square() throws {
        let icon = try loadIcon()
        XCTAssertEqual(icon.width, 1024, "The App Store icon must be 1024pt wide")
        XCTAssertEqual(icon.height, 1024, "The App Store icon must be 1024pt tall")
    }

    // MARK: - Opacity

    /// The pixel-level assertion. Not "mostly opaque", not "opaque in the
    /// middle" - no pixel anywhere may have alpha below 255.
    func test_appIcon_hasNoPixelWithAlphaBelow255() throws {
        let icon = try loadIcon()
        let (data, width, height) = pixels(of: icon)

        var minimumAlpha = 255
        var translucentCount = 0
        var firstOffender: (x: Int, y: Int, alpha: Int)?

        for y in 0 ..< height {
            for x in 0 ..< width {
                let alpha = Int(data[(y * width + x) * 4 + 3])
                if alpha < 255 {
                    translucentCount += 1
                    if firstOffender == nil { firstOffender = (x, y, alpha) }
                }
                minimumAlpha = min(minimumAlpha, alpha)
            }
        }

        XCTAssertEqual(
            translucentCount,
            0,
            """
            \(translucentCount) of \(width * height) pixels are not fully opaque \
            (minimum alpha \(minimumAlpha), first at \(String(describing: firstOffender))). \
            Regenerate with tools/appicon/make-opaque-icon.swift.
            """
        )
    }

    /// The encoded file should have no alpha channel at all, not an alpha
    /// channel that happens to be full. Both pass App Review, but the former
    /// cannot regress by accident.
    func test_appIcon_fileHasNoAlphaChannel() throws {
        let icon = try loadIcon()
        let info = icon.alphaInfo
        XCTAssertTrue(
            [.none, .noneSkipLast, .noneSkipFirst].contains(info),
            "The icon still carries an alpha channel (\(info.rawValue)); it should be flattened"
        )
    }

    // MARK: - No baked corner rounding

    /// Transparent or faded corners are the signature of an icon that has had
    /// its own rounding applied. The corners must be solid, and they must
    /// match each other - a square that reaches its own edges.
    func test_appIcon_cornersAreOpaqueAndIdentical() throws {
        let icon = try loadIcon()
        let (data, width, height) = pixels(of: icon)

        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let i = (y * width + x) * 4
            return [data[i], data[i + 1], data[i + 2], data[i + 3]]
        }

        let corners = [
            ("top-left", pixel(0, 0)),
            ("top-right", pixel(width - 1, 0)),
            ("bottom-left", pixel(0, height - 1)),
            ("bottom-right", pixel(width - 1, height - 1)),
        ]

        for (name, colour) in corners {
            XCTAssertEqual(colour[3], 255, "The \(name) corner is not opaque - the icon is pre-rounded")
        }

        let distinct = Set(corners.map { $0.1 })
        XCTAssertEqual(
            distinct.count,
            1,
            "The four corners differ (\(corners.map { "\($0.0)=\($0.1)" })); a full-bleed square icon's corners should match"
        )
    }

    /// A sanity check that the icon is still *artwork* and not a blank
    /// rectangle: the centre must differ from the corner fill. Without this,
    /// an all-one-colour square would satisfy every assertion above.
    func test_appIcon_stillContainsArtwork() throws {
        let icon = try loadIcon()
        let (data, width, height) = pixels(of: icon)

        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let i = (y * width + x) * 4
            return [data[i], data[i + 1], data[i + 2]]
        }

        XCTAssertNotEqual(
            pixel(width / 2, height / 2),
            pixel(0, 0),
            "The icon appears to be a flat rectangle with no artwork"
        )
    }

    // MARK: - Asset catalog

    /// Every entry in `Contents.json` that names a file must name one that
    /// exists, and the universal 1024 slot must be filled. An unfilled slot
    /// is not a build error - it is a missing icon at submission time.
    func test_appIconContentsJSON_referencesFilesThatExist_andFillsThe1024Slot() throws {
        let directory = Self.iconURL.deletingLastPathComponent()
        let contentsURL = directory.appendingPathComponent("Contents.json")
        let data = try Data(contentsOf: contentsURL)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let images = try XCTUnwrap(json?["images"] as? [[String: Any]], "Contents.json has no images array")
        XCTAssertFalse(images.isEmpty)

        for entry in images {
            guard let filename = entry["filename"] as? String else { continue }
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: directory.appendingPathComponent(filename).path),
                "Contents.json references \(filename), which is not in the icon set"
            )
        }

        // The plain (no `appearances`) universal entry is the one App Store
        // Connect takes as the marketing icon.
        let marketing = images.first { $0["appearances"] == nil && ($0["size"] as? String) == "1024x1024" }
        let filename = (marketing?["filename"] as? String) ?? ""
        XCTAssertFalse(filename.isEmpty, "The universal 1024x1024 icon slot has no image assigned")
    }
}
