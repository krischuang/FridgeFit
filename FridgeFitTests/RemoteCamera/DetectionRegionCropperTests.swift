//
//  DetectionRegionCropperTests.swift
//  FridgeFitTests
//

import CoreGraphics
import Foundation
import UIKit
import XCTest
@testable import FridgeFit

/// The coordinate flip, pinned down with pixels.
///
/// A vertically mirrored crop still looks like a plausible food crop, so this
/// error would not be visible in the results - only in the accuracy, and only
/// as a vague "classification is worse than expected". Hence an asymmetric
/// fixture and explicit assertions.
final class DetectionRegionCropperTests: XCTestCase {

    private let cropper = DetectionRegionCropper(
        configuration: {
            var configuration = DetectionRegionCropper.Configuration.default
            // No margin, so the arithmetic under test is not blurred by it.
            configuration.margin = 0
            return configuration
        }()
    )

    private func region(_ box: CGRect) -> DetectedObject {
        DetectedObject(label: "apple", confidence: 0.9, boundingBox: box)
    }

    // MARK: - Geometry

    func test_aBoxAtTheBottomInVisionSpaceCropsTheBottomOfTheImage() {
        // Vision y = 0 is the bottom. In CGImage pixels, the bottom of a
        // 400-tall image is y = 300...400.
        let rect = cropper.pixelRect(
            for: CGRect(x: 0, y: 0, width: 0.5, height: 0.25),
            in: CGSize(width: 400, height: 400)
        )

        XCTAssertEqual(rect?.minY, 300, "a Vision-bottom box must map to the pixel bottom")
        XCTAssertEqual(rect?.maxY, 400)
    }

    func test_aBoxAtTheTopInVisionSpaceCropsTheTopOfTheImage() {
        let rect = cropper.pixelRect(
            for: CGRect(x: 0, y: 0.75, width: 0.5, height: 0.25),
            in: CGSize(width: 400, height: 400)
        )

        XCTAssertEqual(rect?.minY, 0)
        XCTAssertEqual(rect?.maxY, 100)
    }

    func test_theHorizontalAxisIsNotFlipped() {
        let rect = cropper.pixelRect(
            for: CGRect(x: 0, y: 0.4, width: 0.25, height: 0.2),
            in: CGSize(width: 400, height: 400)
        )

        XCTAssertEqual(rect?.minX, 0, "x is not mirrored")
        XCTAssertEqual(rect?.maxX, 100)
    }

    /// The real proof: crop a known quadrant out of a four-colour image and
    /// check the pixels that come back.
    func test_theCropContainsThePixelsTheBoxPointsAt() throws {
        // Top-left red, top-right green, bottom-left blue, bottom-right yellow.
        let size = CGSize(width: 200, height: 200)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill();    context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.green.setFill();  context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
            UIColor.blue.setFill();   context.fill(CGRect(x: 0, y: 100, width: 100, height: 100))
            UIColor.yellow.setFill(); context.fill(CGRect(x: 100, y: 100, width: 100, height: 100))
        }
        let cgImage = try XCTUnwrap(image.cgImage)

        // Vision space: bottom-left quadrant is x 0...0.5, y 0...0.5.
        // In the drawn image that quadrant is blue.
        let crops = cropper.crops(
            from: cgImage,
            regions: [region(CGRect(x: 0, y: 0, width: 0.5, height: 0.5))]
        )

        let crop = try XCTUnwrap(crops.first)
        XCTAssertEqual(crop.image.width, 100)
        XCTAssertEqual(crop.image.height, 100)
        let (red, green, blue) = try averageColour(of: crop.image)
        XCTAssertLessThan(red, 60, "bottom-left is blue, so red should be low")
        XCTAssertLessThan(green, 60)
        XCTAssertGreaterThan(blue, 180, "bottom-left in Vision space is the blue quadrant")
    }

    // MARK: - Guards

    func test_aCropSmallerThanTheMinimumIsSkipped() {
        var configuration = DetectionRegionCropper.Configuration.default
        configuration.margin = 0
        configuration.minimumPixelSize = 50
        let strict = DetectionRegionCropper(configuration: configuration)

        let rect = strict.pixelRect(
            for: CGRect(x: 0.1, y: 0.1, width: 0.05, height: 0.05),
            in: CGSize(width: 400, height: 400)  // 20x20 pixels
        )

        XCTAssertNil(rect, "a 20-pixel sliver is not worth a Vision request")
    }

    func test_aMarginIsAddedButClampedToTheFrame() {
        var configuration = DetectionRegionCropper.Configuration.default
        configuration.margin = 0.5
        let generous = DetectionRegionCropper(configuration: configuration)

        // A box flush against the left edge: the margin would push it to -50.
        let rect = generous.pixelRect(
            for: CGRect(x: 0, y: 0.25, width: 0.25, height: 0.5),
            in: CGSize(width: 400, height: 400)
        )

        XCTAssertEqual(rect?.minX, 0, "the crop must stay inside the image")
        XCTAssertGreaterThan(rect?.width ?? 0, 100, "but the margin should still widen it")
    }

    func test_cropsAreCappedLargestFirst() {
        var configuration = DetectionRegionCropper.Configuration.default
        configuration.margin = 0
        configuration.maximumCrops = 2
        let capped = DetectionRegionCropper(configuration: configuration)

        let small = region(CGRect(x: 0.0, y: 0.0, width: 0.15, height: 0.15))
        let medium = region(CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3))
        let large = region(CGRect(x: 0.5, y: 0.5, width: 0.45, height: 0.45))

        let image = try! XCTUnwrap(solidImage(400, 400).cgImage)
        let crops = capped.crops(from: image, regions: [small, medium, large])

        XCTAssertEqual(crops.count, 2)
        XCTAssertEqual(Set(crops.map(\.region.id)), [large.id, medium.id],
                       "the smallest box is the one dropped")
    }

    func test_aZeroSizedBoxProducesNoCrop() {
        XCTAssertNil(cropper.pixelRect(
            for: CGRect(x: 0.5, y: 0.5, width: 0, height: 0),
            in: CGSize(width: 400, height: 400)
        ))
    }

    /// The cropper must work on normalised ingredients too, since that is
    /// what the live pipeline crops.
    func test_normalisedIngredientsCanBeCropped() throws {
        let ingredient = DetectedIngredient(
            ingredientId: "apple", displayName: "Apple", category: .fruit,
            confidence: 0.8, boundingBox: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            source: .ingredientDetector, rawTerm: "apple"
        )
        let image = try XCTUnwrap(solidImage(400, 400).cgImage)

        let crops = cropper.crops(from: image, regions: [ingredient])

        XCTAssertEqual(crops.count, 1)
        XCTAssertEqual(crops.first?.region.id, ingredient.id)
    }

    // MARK: - Helpers

    private func solidImage(_ width: Int, _ height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format
        ).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func averageColour(of image: CGImage) throws -> (Double, Double, Double) {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var totals = (0.0, 0.0, 0.0)
        let count = Double(width * height)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            totals.0 += Double(pixels[index])
            totals.1 += Double(pixels[index + 1])
            totals.2 += Double(pixels[index + 2])
        }
        return (totals.0 / count, totals.1 / count, totals.2 / count)
    }
}
