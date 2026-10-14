//
//  IngredientDetectorFactoryTests.swift
//  FridgeFitTests
//

import CoreGraphics
import CoreVideo
import ImageIO
import UIKit
import XCTest
@testable import FridgeFit

/// Model selection, the COCO fallback, and real inference with the shipped
/// YOLO-World model.
final class IngredientDetectorFactoryTests: XCTestCase {

    /// A bundle that hides one resource, to exercise the fallback without
    /// deleting anything from the real bundle.
    private final class BundleHidingResource: Bundle, @unchecked Sendable {
        private let hidden: String
        init(hiding name: String) {
            self.hidden = name
            super.init()
        }
        override func url(forResource name: String?, withExtension ext: String?) -> URL? {
            if name == hidden { return nil }
            return Bundle.main.url(forResource: name, withExtension: ext)
        }
    }

    // MARK: - Selection

    func test_theIngredientModelIsPreferred() throws {
        let resolved = try IngredientDetectorFactory.makeBest(bundle: .main)

        XCTAssertEqual(resolved.source, .ingredientDetector)
        XCTAssertNil(resolved.fallbackReason)
        XCTAssertEqual(resolved.taxonomy.modelIdentifier, "yolov8s-worldv2")
    }

    func test_theIngredientDetectorLoadsWithTheFullVocabulary() throws {
        let resolved = try IngredientDetectorFactory.makeIngredientDetector(bundle: .main)

        XCTAssertGreaterThan(resolved.taxonomy.ingredientCount, 80)
        // Decoys must reach the model even though they never reach the user.
        XCTAssertTrue(resolved.taxonomy.allTerms.contains("plate"))
    }

    /// The point of keeping YOLO11n: a missing or broken ingredient model
    /// degrades to ten reliable classes rather than to nothing.
    func test_aMissingIngredientModelFallsBackToCoco() throws {
        let bundle = BundleHidingResource(hiding: IngredientDetectorFactory.ingredientModelName)

        let resolved = try IngredientDetectorFactory.makeBest(bundle: bundle)

        XCTAssertEqual(resolved.source, .cocoFallback)
        XCTAssertEqual(resolved.taxonomy.modelIdentifier, "yolo11n-coco")
        let reason = try XCTUnwrap(resolved.fallbackReason, "a fallback must explain itself")
        XCTAssertFalse(reason.isEmpty)
    }

    func test_aMissingVocabularyAlsoFallsBack() throws {
        let bundle = BundleHidingResource(hiding: "ingredient_vocabulary")

        let resolved = try IngredientDetectorFactory.makeBest(bundle: bundle)

        XCTAssertEqual(resolved.source, .cocoFallback)
        XCTAssertNotNil(resolved.fallbackReason)
    }

    func test_theCocoFallbackCoversTheTenEdibleClasses() throws {
        let resolved = try IngredientDetectorFactory.makeFallbackDetector(bundle: .main)

        XCTAssertEqual(resolved.taxonomy.ingredientCount, 10)
        XCTAssertEqual(Set(resolved.taxonomy.definitions.map(\.term)), COCOFoodClass.all)
        for definition in resolved.taxonomy.definitions {
            XCTAssertFalse(definition.requiresReview)
        }
    }

    /// Only one model is constructed per resolution, so a constrained device
    /// never holds both.
    func test_resolvingProducesASingleDetector() throws {
        let resolved = try IngredientDetectorFactory.makeBest(bundle: .main)

        XCTAssertTrue(resolved.detector is YOLOFoodDetectionService)
        XCTAssertIdentical(resolved.detector as AnyObject, resolved.detector as AnyObject)
    }

    func test_theShippedFilteringPolicyIsTheOneThatWasTuned() {
        let policy = IngredientNormalizer.Configuration.default

        // 0.40 came from a threshold sweep over the annotated evaluation set:
        // same recall as 0.35, precision 42% -> 56%, false positives halved.
        XCTAssertEqual(policy.displayThreshold, 0.40)
        XCTAssertEqual(policy.trustThreshold, 0.60)
        XCTAssertLessThan(policy.displayThreshold, policy.trustThreshold)
    }

    // MARK: - Real inference

    /// A normaliser that keeps everything the model reports.
    ///
    /// The inference tests are about the *pipeline* - model loads, Vision
    /// decodes, boxes land in the right place - not about the shipped
    /// filtering policy, which `IngredientNormalizerTests` covers. Using the
    /// production threshold here would make them a test of one synthetic
    /// fixture's confidence rather than of inference.
    private func permissiveNormalizer(_ taxonomy: IngredientTaxonomy) -> IngredientNormalizer {
        var policy = IngredientNormalizer.Configuration.default
        policy.displayThreshold = 0.0
        policy.trustThreshold = 1.0
        return IngredientNormalizer(taxonomy: taxonomy, configuration: policy)
    }

    /// A 640x640 white frame with a solid orange disc.
    ///
    /// The model reports `orange` on it through Vision at roughly 0.36 - a
    /// hard-edged synthetic shape is not a photograph, and Vision's
    /// `.scaleFill` resampling scores it differently from the PIL-based
    /// evaluation harness. Good enough to prove inference works and that
    /// coordinates are right; not a statement about real-world confidence.
    private func orangeOnWhite() throws -> CVPixelBuffer {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 640), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 640))
            UIColor(red: 1.0, green: 140.0 / 255.0, blue: 0, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 200, y: 200, width: 240, height: 240))
        }
        return try pixelBuffer(from: image)
    }

    private func pixelBuffer(from image: UIImage) throws -> CVPixelBuffer {
        let cgImage = try XCTUnwrap(image.cgImage)
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, cgImage.width, cgImage.height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary, &buffer
        )
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
        let context = try XCTUnwrap(CGContext(
            data: CVPixelBufferGetBaseAddress(pixels),
            width: cgImage.width, height: cgImage.height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixels),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return pixels
    }

    /// End to end with the real YOLO-World export: inference, normalisation,
    /// and correct coordinates.
    func test_theShippedIngredientModelDetectsAKnownObject() throws {
        let resolved = try IngredientDetectorFactory.makeIngredientDetector(bundle: .main)

        let raw = try resolved.detector.detect(
            in: try orangeOnWhite(),
            orientation: .up,
            orientedSize: CGSize(width: 640, height: 640)
        )
        let result = permissiveNormalizer(resolved.taxonomy).normalize(raw, source: resolved.source)

        let orange = try XCTUnwrap(
            result.ingredients.first { $0.ingredientId == "orange" },
            "expected an orange, got \(result.ingredients.map(\.ingredientId))"
        )
        XCTAssertEqual(orange.category, .fruit)
        XCTAssertEqual(orange.source, .ingredientDetector)
        XCTAssertGreaterThan(orange.confidence, 0.0)

        // The disc is centred and spans ~0.375 of the frame. This also pins
        // down the coordinate convention end to end.
        XCTAssertEqual(orange.boundingBox.midX, 0.5, accuracy: 0.10)
        XCTAssertEqual(orange.boundingBox.midY, 0.5, accuracy: 0.10)
    }

    func test_everyNormalisedIngredientComesFromTheVocabulary() throws {
        let resolved = try IngredientDetectorFactory.makeIngredientDetector(bundle: .main)

        let raw = try resolved.detector.detect(
            in: try orangeOnWhite(), orientation: .up,
            orientedSize: CGSize(width: 640, height: 640)
        )
        let result = permissiveNormalizer(resolved.taxonomy).normalize(raw, source: resolved.source)

        XCTAssertFalse(result.isEmpty)
        let known = Set(resolved.taxonomy.definitions.map(\.ingredient))
        for ingredient in result.ingredients {
            XCTAssertTrue(known.contains(ingredient.ingredientId)
                          || ingredient.ingredientId == "red_meat"
                          || ingredient.ingredientId == "poultry",
                          "\(ingredient.ingredientId) is not a taxonomy ingredient")
            XCTAssertNotEqual(ingredient.category, .decoy)
        }
    }

    /// A blank frame producing nothing is a normal outcome, not an error, and
    /// must never be filled in with invented ingredients.
    func test_aBlankFrameProducesNoIngredients() throws {
        let resolved = try IngredientDetectorFactory.makeIngredientDetector(bundle: .main)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 640), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 640))
        }

        let raw = try resolved.detector.detect(
            in: try pixelBuffer(from: blank), orientation: .up,
            orientedSize: CGSize(width: 640, height: 640)
        )
        // Permissive on purpose: if a blank frame produces anything at all,
        // that is worth failing on, not hiding behind a threshold.
        let result = permissiveNormalizer(resolved.taxonomy).normalize(raw, source: resolved.source)

        XCTAssertTrue(result.isEmpty, "got \(result.ingredients.map(\.displayName))")
    }

    func test_inferenceRunsForEveryFrameRotation() throws {
        let resolved = try IngredientDetectorFactory.makeIngredientDetector(bundle: .main)
        let buffer = try orangeOnWhite()

        for rotation in FrameOrientation.Rotation.allCases {
            let orientation = try XCTUnwrap(CGImagePropertyOrientation(
                rawValue: FrameOrientation.cgOrientationRawValue(for: rotation)
            ))
            let size = FrameOrientation.orientedSize(width: 640, height: 640, rotation: rotation)

            let raw = try resolved.detector.detect(in: buffer, orientation: orientation, orientedSize: size)
            let result = permissiveNormalizer(resolved.taxonomy).normalize(raw, source: resolved.source)

            XCTAssertTrue(
                result.ingredients.contains { $0.ingredientId == "orange" },
                "rotation \(rotation) lost the detection"
            )
        }
    }
}
