//
//  ClassificationCapabilityTests.swift
//  FridgeFitTests
//

import CoreGraphics
import Foundation
import UIKit
import Vision
import XCTest
@testable import FridgeFit

/// Degrading to YOLO-only when Apple Vision classification cannot run.
///
/// The bug these exist for: one `try classifier.classify(...)` in
/// `SnapshotIngredientAnalyzer.analyze` propagated out of the method and
/// discarded the YOLO detections that had *already succeeded*, plus the OCR
/// that had not yet run. In the simulator that meant tapping Analyse produced
/// "Image classification failed: Failed to create espresso context" and
/// nothing else - no boxes, no text, no review.
final class ClassificationCapabilityTests: XCTestCase {

    // MARK: - The capability type

    /// A platform limitation and a fault must stay distinguishable, or the
    /// UI either cries wolf every simulator run or hides a real device fault.
    func test_aSimulatorLimitationIsNotAFault() {
        let limitation = ClassificationCapability.unavailableInSimulator("Failed to create espresso context.")

        XCTAssertFalse(limitation.isAvailable)
        XCTAssertTrue(limitation.isExpectedLimitation)
        XCTAssertEqual(limitation.userMessage, "Apple Vision classification unavailable in Simulator")
    }

    func test_aRealFailureIsAFaultAndKeepsItsDetail() {
        let failure = ClassificationCapability.failed("something genuinely broke")

        XCTAssertFalse(failure.isAvailable)
        XCTAssertFalse(failure.isExpectedLimitation, "this is not an expected limitation")
        XCTAssertEqual(failure.userMessage, "Apple Vision classification failed: something genuinely broke")
        XCTAssertEqual(failure.diagnosticDetail, "something genuinely broke",
                       "the underlying reason must not be swallowed")
    }

    func test_availabilityHasNothingToReport() {
        XCTAssertTrue(ClassificationCapability.available.isAvailable)
        XCTAssertNil(ClassificationCapability.available.userMessage)
    }

    // MARK: - The probe

    /// The probe is the source of truth, not `#if targetEnvironment`.
    ///
    /// Asserting the *specific* value per platform would bake in today's
    /// simulator behaviour; what matters is that the probe agrees with
    /// reality, and that a simulator failure is classified as a limitation
    /// rather than a fault.
    func test_theProbeAgreesWithWhatTheAPIActuallyDoes() {
        let capability = AppleVisionIngredientClassifier.probeCapability()

        let request = VNClassifyImageRequestProbe.canRun()
        XCTAssertEqual(capability.isAvailable, request,
                       "the probe must report what the API actually does here")

        #if targetEnvironment(simulator)
        if !capability.isAvailable {
            XCTAssertTrue(capability.isExpectedLimitation,
                          "a simulator failure is a known limitation, not a fault")
        }
        #endif
    }

    // MARK: - The classifier refuses rather than lying

    /// An empty result means "looked and found nothing". That is a claim
    /// about the image. Unavailability is a claim about the platform, and
    /// conflating them would report "no ingredients" for a photo nothing
    /// examined.
    func test_anUnavailableClassifierThrowsRatherThanReturningEmpty() throws {
        let classifier = try AppleVisionIngredientClassifier(
            map: VisionIngredientMap.load(in: .main),
            capability: .unavailableInSimulator("probe failed")
        )

        XCTAssertThrowsError(try classifier.classify(Self.solidImage(), orientation: .up)) { error in
            guard let error = error as? VisionClassificationError else {
                return XCTFail("expected a VisionClassificationError, got \(error)")
            }
            XCTAssertTrue(error.isExpectedLimitation)
            XCTAssertEqual(error.message, "Apple Vision classification unavailable in Simulator")
        }
    }

    func test_aFailedClassifierThrowsAFaultNotALimitation() throws {
        let classifier = try AppleVisionIngredientClassifier(
            map: VisionIngredientMap.load(in: .main),
            capability: .failed("Espresso context creation failed on device")
        )

        XCTAssertThrowsError(try classifier.classify(Self.solidImage(), orientation: .up)) { error in
            let error = error as? VisionClassificationError
            XCTAssertEqual(error?.isExpectedLimitation, false,
                           "a device failure must not be downgraded to 'unavailable'")
            XCTAssertTrue(error?.message.contains("Espresso context creation failed on device") ?? false,
                          "the real reason must reach the user, got \(error?.message ?? "nil")")
        }
    }

    // MARK: - The outcome summary

    func test_anOutcomeKnowsWhenResultsAreDetectorOnly() {
        let unavailable = ClassificationOutcome(
            capability: .unavailableInSimulator("espresso"), sceneFailure: nil,
            regionsAttempted: 0, regionFailures: 0, regionFailure: nil, packagingFailure: nil
        )
        XCTAssertTrue(unavailable.isDetectorOnly)
        XCTAssertNil(unavailable.faultMessage, "a known limitation is not a fault")
        XCTAssertEqual(unavailable.userMessage, "Apple Vision classification unavailable in Simulator")

        XCTAssertFalse(ClassificationOutcome.available.isDetectorOnly)
        XCTAssertNil(ClassificationOutcome.available.userMessage)
    }

    func test_aSceneFailureOnAWorkingClassifierIsReportedAsAFault() {
        let outcome = ClassificationOutcome(
            capability: .available, sceneFailure: "Image classification failed: out of memory",
            regionsAttempted: 3, regionFailures: 0, regionFailure: nil, packagingFailure: nil
        )

        XCTAssertTrue(outcome.isDetectorOnly)
        XCTAssertEqual(outcome.faultMessage, "Image classification failed: out of memory")
    }

    /// Region failures used to be swallowed into a log line. A device where
    /// every crop fails must say so.
    func test_regionFailuresAreCountedAndSurfaced() {
        let outcome = ClassificationOutcome(
            capability: .available, sceneFailure: nil,
            regionsAttempted: 4, regionFailures: 4, regionFailure: "espresso", packagingFailure: nil
        )

        XCTAssertEqual(outcome.faultMessage, "4 of 4 regions failed: espresso")
    }

    // MARK: - End to end: the actual reported bug

    /// Tapping Analyse in the simulator must produce YOLO results, not an
    /// error. Runs the real detector and the real classifier.
    func test_analysisDegradesToYOLOOnlyInsteadOfFailing() throws {
        let analyzer = try Self.makeAnalyzer()

        // Must not throw. This is the whole fix.
        let analysis = try analyzer.analyze(
            try HybridEvaluation.image(named: "fruits_mixed"), orientation: .up
        )

        if analysis.classification.capability.isAvailable {
            throw XCTSkip("""
            The classifier is available here, so there is nothing to degrade. \
            This test is about the simulator path.
            """)
        }

        XCTAssertTrue(analysis.classification.isDetectorOnly)
        XCTAssertEqual(
            analysis.classification.userMessage,
            "Apple Vision classification unavailable in Simulator"
        )
        XCTAssertNil(analysis.classification.faultMessage,
                     "an expected limitation must not be reported as a fault")
    }

    /// The detector's work survives. Previously it was computed and then
    /// thrown away by the classifier's error.
    ///
    /// Uses a real photograph rather than the synthetic disc: that disc
    /// scores 0.363 through Vision, below the shipped 0.40 display threshold,
    /// so the production normaliser correctly filters it out and the test
    /// would be measuring the fixture rather than the fix.
    func test_yoloResultsSurviveAnUnavailableClassifier() throws {
        let analyzer = try Self.makeAnalyzer()

        let analysis = try analyzer.analyze(
            try HybridEvaluation.image(named: "fruits_mixed"), orientation: .up
        )

        XCTAssertFalse(
            analysis.fused.localised.isEmpty,
            "the detector found nothing at all, so nothing survived"
        )
        for item in analysis.fused.localised {
            XCTAssertNotNil(item.boundingBox, "detector results keep their measured boxes")
            XCTAssertTrue(item.sources.contains(.detector))
        }
    }

    /// Nothing may claim two methods agreed when only one ran.
    func test_noAgreementIsInventedWithoutAClassifier() throws {
        let analyzer = try Self.makeAnalyzer()

        let analysis = try analyzer.analyze(
            try HybridEvaluation.image(named: "fruits_mixed"), orientation: .up
        )

        guard !analysis.classification.capability.isAvailable else {
            throw XCTSkip("classifier available; agreement is legitimate here")
        }

        XCTAssertEqual(analysis.fused.agreedCount, 0, "no second opinion means no agreement")
        XCTAssertEqual(analysis.fused.conflictCount, 0, "and nothing to disagree with")
        for item in analysis.fused.all {
            XCTAssertEqual(item.tier, .singleSource)
            XCTAssertEqual(item.sources, .detector, "only the detector contributed")
            XCTAssertNil(item.classifierConfidence, "no confidence may be invented")
            XCTAssertNil(item.classifierIdentifier)
            XCTAssertTrue(item.requiresReview)
        }
    }

    /// OCR is a different Vision request and works where the classifier does
    /// not, so it must not be gated on the classifier.
    func test_ocrStillRunsWithoutTheClassifier() throws {
        let analyzer = try Self.makeAnalyzer()

        let analysis = try analyzer.analyze(Self.textImage(), orientation: .up)

        XCTAssertNil(analysis.classification.packagingFailure,
                     "OCR should run regardless of the classifier")
        XCTAssertFalse(analysis.packaging.lines.isEmpty,
                       "expected to read the rendered text; got \(analysis.packaging.lines)")
    }

    /// A blank frame is a normal outcome, not an error, and must not be
    /// filled in with anything.
    func test_anEmptyDetectionResultIsStillAValidAnalysis() throws {
        let analyzer = try Self.makeAnalyzer()

        let analysis = try analyzer.analyze(Self.blankImage(), orientation: .up)

        XCTAssertTrue(analysis.fused.localised.isEmpty)
        XCTAssertTrue(analysis.fused.sceneLevel.isEmpty)
        XCTAssertEqual(analysis.fused.agreedCount, 0)
    }

    /// The degraded analysis still drives a usable review step.
    @MainActor
    func test_aDegradedAnalysisStillSupportsReviewAndConfirmation() throws {
        let analyzer = try Self.makeAnalyzer()
        let analysis = try analyzer.analyze(
            try HybridEvaluation.image(named: "fruits_mixed"), orientation: .up
        )

        let review = IngredientReviewViewModel(analysis: analysis)

        XCTAssertFalse(review.isEmpty, "nothing to review means this test proves nothing")
        XCTAssertEqual(review.classification, analysis.classification,
                       "the review sheet must be able to say why it is YOLO-only")
        if analysis.classification.isDetectorOnly {
            XCTAssertEqual(review.acceptedCount, 0,
                           "single-source rows are never pre-ticked, so nothing is accepted by default")
            XCTAssertEqual(review.count(of: .agreed), 0)
        }

        // The user can still accept, correct and add.
        let id = try XCTUnwrap(review.items.first).id
        review.accept(id)
        review.rename(id, to: "Satsuma")
        review.setQuantityText("3", for: id)
        XCTAssertTrue(review.addManualIngredient(name: "Cheddar", category: .dairy))

        XCTAssertEqual(review.acceptedCount, 2)
        XCTAssertTrue(review.items.contains { $0.displayName == "Satsuma" })
    }

    // MARK: - Fixtures

    private static func makeAnalyzer() throws -> SnapshotIngredientAnalyzer {
        let resolved = try IngredientDetectorFactory.makeIngredientDetector(bundle: .main)
        let classifier = try AppleVisionIngredientClassifier(bundle: .main)
        return try XCTUnwrap(
            SnapshotIngredientAnalyzer(resolved: resolved, classifier: classifier),
            "expected a YOLOFoodDetectionService"
        )
    }

    private static func render(_ size: CGSize, _ body: (CGContext) -> Void) -> CGImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            body(context.cgContext)
        }
        return image.cgImage!
    }

    static func orangeOnWhite() -> CGImage {
        render(CGSize(width: 640, height: 640)) { context in
            context.setFillColor(UIColor(red: 1, green: 140 / 255, blue: 0, alpha: 1).cgColor)
            context.fillEllipse(in: CGRect(x: 200, y: 200, width: 240, height: 240))
        }
    }

    static func blankImage() -> CGImage {
        render(CGSize(width: 640, height: 640)) { _ in }
    }

    static func solidImage() -> CGImage {
        render(CGSize(width: 64, height: 64)) { _ in }
    }

    /// Large, high-contrast text, so OCR has something it can actually read.
    static func textImage() -> CGImage {
        let size = CGSize(width: 640, height: 320)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
            ("ORGANIC RICE" as NSString).draw(at: CGPoint(x: 40, y: 110), withAttributes: attributes)
        }
        return image.cgImage!
    }
}

/// Independent check of whether `VNClassifyImageRequest` runs here, so the
/// probe is compared against something other than itself.
enum VNClassifyImageRequestProbe {
    static func canRun() -> Bool {
        let side = 16
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else { return false }
        return (try? VNImageRequestHandler(cgImage: image, options: [:])
            .perform([VNClassifyImageRequest()])) != nil
    }
}
