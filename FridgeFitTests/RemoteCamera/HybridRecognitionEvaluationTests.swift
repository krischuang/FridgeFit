//
//  HybridRecognitionEvaluationTests.swift
//  FridgeFitTests
//

import CoreGraphics
import Foundation
import Vision
import XCTest
@testable import FridgeFit

/// Measures the hybrid pipeline on the same 11 annotated images the Python
/// harness used, through the real Swift Vision APIs.
///
/// This is the validation step for Stage 1: the research numbers were
/// produced by `tools/vision-eval/`, which decodes images with PIL/ImageIO
/// and calls Vision from a command-line tool. If the app's path scores
/// differently, that difference matters more than the original figure - and
/// the preprocessing question from the YOLO-World round (coremltools 0.537 vs
/// Vision 0.363 on the same fixture) is exactly why it is worth checking
/// rather than assuming.
///
/// Nothing here is mocked. Every number comes from the shipped Core ML model
/// and the OS classifier running over real photographs.
final class HybridRecognitionEvaluationTests: XCTestCase {

    private var annotations: [String: HybridEvaluation.Annotation] = [:]

    override func setUpWithError() throws {
        try super.setUpWithError()
        annotations = try HybridEvaluation.annotations()
        XCTAssertEqual(annotations.count, 11, "the shared evaluation set is 11 images")
        try XCTSkipUnless(
            Self.visionClassifierIsSupported,
            """
            VNClassifyImageRequest cannot run in the iOS simulator - it fails \
            with "Failed to create espresso context". Verified with a 20-line \
            reproduction containing no FridgeFit code: the same binary works \
            on macOS and returns 1303 classifications.

            The Swift pipeline IS measured, on Mac Catalyst, by
            tools/vision-eval/swift-harness. Run:
              ./tools/vision-eval/swift-harness/build.sh
              ./tools/vision-eval/swift-harness/harness <resources> <images> <annotations>

            These tests run unchanged on a physical device.
            """
        )
    }

    /// Whether `VNClassifyImageRequest` can run at all in this environment.
    ///
    /// Probed once rather than assumed from `#if targetEnvironment(simulator)`,
    /// so a future simulator that gains support is picked up automatically
    /// instead of being skipped forever.
    private static let visionClassifierIsSupported: Bool = {
        let width = 32, height = 32
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let probe = context.makeImage() else { return false }
        let request = VNClassifyImageRequest()
        return (try? VNImageRequestHandler(cgImage: probe, options: [:]).perform([request])) != nil
    }()

    // MARK: - Candidates

    /// Whole-image classification: what Apple Vision reports about the frame.
    private func fullImageSets(threshold: Float) throws -> [String: Set<String>] {
        var configuration = AppleVisionIngredientClassifier.Configuration.default
        configuration.confidenceThreshold = threshold
        // The cap exists for the UI; evaluation wants everything above the
        // threshold, or the measurement becomes a measurement of the cap.
        configuration.maximumIngredients = 50
        let classifier = try AppleVisionIngredientClassifier(
            bundle: .main, configuration: configuration
        )

        var sets: [String: Set<String>] = [:]
        for name in annotations.keys {
            let result = try classifier.classify(try HybridEvaluation.image(named: name))
            // Wrong-food claims are concrete errors and must be counted, so
            // they enter the set under a name no annotation can match.
            sets[name] = Set(result.ingredients.map(\.ingredientId))
                .union(result.rejectedFoodClaims.map { "!\($0)" })
        }
        return sets
    }

    /// Detector alone: the shipped YOLO-World model over the same stills.
    private func detectorSets() throws -> [String: Set<String>] {
        let resolved = try IngredientDetectorFactory.makeIngredientDetector(bundle: .main)
        let detector = try XCTUnwrap(resolved.detector as? YOLOFoodDetectionService)

        var sets: [String: Set<String>] = [:]
        for name in annotations.keys {
            let image = try HybridEvaluation.image(named: name)
            let raw = try detector.detect(in: image)
            let normalised = resolved.normalizer.normalize(raw, source: resolved.source)
            sets[name] = Set(normalised.ingredients.map(\.ingredientId))
        }
        return sets
    }

    /// Crop-based: classify the contents of each box the detector produced.
    ///
    /// Returns the detector sets alongside, so both halves of the comparison
    /// come from one pass over the images.
    private func cropSets(
        regionThreshold: Float
    ) throws -> (detector: [String: Set<String>], crops: [String: Set<String>], agreed: [String: Set<String>]) {
        let resolved = try IngredientDetectorFactory.makeIngredientDetector(bundle: .main)
        let detector = try XCTUnwrap(resolved.detector as? YOLOFoodDetectionService)
        var configuration = AppleVisionIngredientClassifier.Configuration.default
        configuration.confidenceThreshold = regionThreshold
        let classifier = try AppleVisionIngredientClassifier(
            bundle: .main, configuration: configuration
        )
        let regionClassifier = RegionIngredientClassifier(classifier: classifier)

        var detectorSets: [String: Set<String>] = [:]
        var cropSets: [String: Set<String>] = [:]
        var agreedSets: [String: Set<String>] = [:]

        for name in annotations.keys {
            let image = try HybridEvaluation.image(named: name)
            let raw = try detector.detect(in: image)
            let normalised = resolved.normalizer.normalize(raw, source: resolved.source)
            let regions = regionClassifier.classifyRegions(
                in: image, regions: normalised.ingredients
            ).results

            detectorSets[name] = Set(normalised.ingredients.map(\.ingredientId))
            cropSets[name] = Set(regions.values.flatMap { $0.ingredients.map(\.ingredientId) })

            let fused = DetectionFusionService().fuse(
                detections: normalised, regionClassifications: regions
            )
            agreedSets[name] = Set(
                fused.localised.filter { $0.tier == .agreed }.map(\.ingredientId)
            )
        }
        return (detectorSets, cropSets, agreedSets)
    }

    // MARK: - The measurement

    /// The headline comparison. Prints the table that goes into the docs.
    func test_measureEveryCandidateOnTheSharedSet() throws {
        let detector = try detectorSets()
        let fullImage30 = try fullImageSets(threshold: 0.30)
        let fullImage10 = try fullImageSets(threshold: 0.10)
        let crops = try cropSets(regionThreshold: 0.20)

        func union(_ a: [String: Set<String>], _ b: [String: Set<String>]) -> [String: Set<String>] {
            var out = a
            for (key, value) in b { out[key, default: []].formUnion(value) }
            return out
        }

        let scores = [
            HybridEvaluation.score(detector, against: annotations, label: "yolo-world (swift)"),
            HybridEvaluation.score(fullImage30, against: annotations, label: "vision full-image @0.30"),
            HybridEvaluation.score(fullImage10, against: annotations, label: "vision full-image @0.10"),
            HybridEvaluation.score(crops.crops, against: annotations, label: "vision crop-based @0.20"),
            HybridEvaluation.score(union(detector, crops.crops), against: annotations,
                                   label: "hybrid: yolo + crops"),
            HybridEvaluation.score(union(detector, fullImage30), against: annotations,
                                   label: "hybrid: yolo + full-image"),
            HybridEvaluation.score(crops.agreed, against: annotations, label: "agreement (localised)"),
        ]
        HybridEvaluation.report(scores)

        print("--- false negatives, detector ---")
        print(scores[0].missed.sorted().joined(separator: ", "))
        print("--- false positives, vision full-image @0.30 ---")
        print(scores[1].spurious.sorted().joined(separator: ", "))
        print("--- false positives, crop-based ---")
        print(scores[3].spurious.sorted().joined(separator: ", "))

        // Every candidate must produce *something*, or the harness is broken
        // rather than the model being bad.
        for score in scores where score.label != "agreement (localised)" {
            XCTAssertGreaterThan(score.found, 0, "\(score.label) found nothing at all")
        }
    }

    /// Does the Swift path reproduce the Python harness?
    ///
    /// The Python run measured 42.1% recall / 72.7% precision at 0.30. An
    /// exact match is not expected - ImageIO and PIL do not decode JPEGs
    /// identically - but a large gap would mean the research numbers do not
    /// describe the app, which is the thing worth knowing.
    func test_swiftReproducesThePythonFullImageMeasurement() throws {
        let score = HybridEvaluation.score(
            try fullImageSets(threshold: 0.30), against: annotations,
            label: "vision full-image @0.30"
        )

        print(String(format: "Swift: recall %.1f%% precision %.1f%% (Python: 42.1%% / 72.7%%)",
                     score.recall * 100, score.precision * 100))

        // Deliberately loose: this asserts "the same ballpark", not "the same
        // number". A tight bound here would be a test of JPEG decoding.
        XCTAssertEqual(score.recall, 0.421, accuracy: 0.15,
                       "Swift recall diverges from the measured Python baseline")
        XCTAssertEqual(score.precision, 0.727, accuracy: 0.20,
                       "Swift precision diverges from the measured Python baseline")
    }

    /// Apple Vision should beat the shipped detector on this set - that is
    /// the finding Stage 1 exists to confirm in Swift.
    func test_visionOutperformsTheDetectorOnThisSet() throws {
        let detector = HybridEvaluation.score(
            try detectorSets(), against: annotations, label: "yolo"
        )
        let vision = HybridEvaluation.score(
            try fullImageSets(threshold: 0.30), against: annotations, label: "vision"
        )

        print(String(format: "yolo %.1f%%/%.1f%%  vision %.1f%%/%.1f%%",
                     detector.recall * 100, detector.precision * 100,
                     vision.recall * 100, vision.precision * 100))

        XCTAssertGreaterThan(vision.recall, detector.recall,
                             "Apple Vision was expected to recall more than YOLO-World here")
    }

    /// The categories YOLO-World cannot do at all.
    ///
    /// Asserted as a *floor on Vision* and a *ceiling on the detector*,
    /// because this is the gap the hybrid exists to close. If the detector
    /// ever starts scoring here, that is a real change worth investigating,
    /// not a test to quietly update.
    func test_visionCoversCategoriesTheDetectorCannot() throws {
        let detector = HybridEvaluation.score(
            try detectorSets(), against: annotations, label: "yolo"
        )
        let vision = HybridEvaluation.score(
            try fullImageSets(threshold: 0.10), against: annotations, label: "vision@0.10"
        )

        for category in ["meat", "seafood", "dairy"] {
            print(String(format: "%@: yolo %.0f%%  vision %.0f%%", category,
                         detector.recall(for: category) * 100,
                         vision.recall(for: category) * 100))
            XCTAssertEqual(detector.recall(for: category), 0, accuracy: 0.001,
                           "YOLO-World scoring on \(category) would be new - verify, don't relax this")
        }
        XCTAssertGreaterThan(
            vision.recall(for: "seafood") + vision.recall(for: "dairy") + vision.recall(for: "meat"),
            0, "Vision was expected to score on at least one protein/dairy category"
        )
    }
}
