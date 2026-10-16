//
//  DetectionDisplayFilterTests.swift
//  FridgeFitTests
//

import CoreGraphics
import XCTest
@testable import FridgeFit

/// Stage 3: candidates to drawn boxes.
///
/// The regressions these guard are the ones that were actually measured, not
/// hypothetical ones:
///
/// - the flat frame cap starving ingredient diversity (precision 0.417 vs
///   0.556 on the evaluation set, for the same number of rectangles)
/// - boxes blinking at the threshold
/// - stale boxes outliving the frame they describe
/// - separate real objects of one ingredient being mistaken for duplicates
final class DetectionDisplayFilterTests: XCTestCase {

    private func filter(
        display: Float = 0.40,
        release: Float = 0.34,
        strong: Float = 0.60,
        perIngredient: Int = 3,
        maximum: Int = 12,
        staleAfter: TimeInterval = 1.5
    ) -> DetectionDisplayFilter {
        var policy = DetectionFilterPolicy.default
        policy.displayThreshold = display
        policy.displayReleaseThreshold = release
        policy.strongThreshold = strong
        policy.maximumBoxesPerIngredient = perIngredient
        policy.maximumDisplayedBoxes = maximum
        policy.staleAfter = staleAfter
        return DetectionDisplayFilter(policy: policy)
    }

    private func box(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 0.1) -> CGRect {
        CGRect(x: x, y: y, width: size, height: size)
    }

    private func candidate(
        _ ingredientId: String,
        _ confidence: Float,
        _ rect: CGRect,
        reason: ReviewReason? = nil
    ) -> DetectedIngredient {
        DetectedIngredient(
            ingredientId: ingredientId,
            displayName: ingredientId.capitalized,
            category: .fruit,
            confidence: confidence,
            boundingBox: rect,
            source: .ingredientDetector,
            reviewReason: reason,
            rawTerm: ingredientId,
            band: DetectionFilterPolicy.default.band(for: confidence)
        )
    }

    private func frame(_ candidates: [DetectedIngredient]) -> IngredientDetectionFrame {
        IngredientDetectionFrame(
            ingredients: candidates.sorted { $0.confidence > $1.confidence },
            sourceSize: CGSize(width: 640, height: 480),
            source: .ingredientDetector
        )
    }

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Threshold filtering

    func test_candidatesBelowTheDisplayThresholdAreNotDrawn() {
        var subject = filter()

        let shown = subject.display(frame([candidate("apple", 0.39, box(0.1, 0.1))]), at: epoch)

        XCTAssertTrue(shown.isEmpty, "0.39 is below the 0.40 display floor")
    }

    func test_theDisplayThresholdIsInclusive() {
        var subject = filter()

        let shown = subject.display(frame([candidate("apple", 0.40, box(0.1, 0.1))]), at: epoch)

        XCTAssertEqual(shown.ingredients.count, 1)
    }

    /// The candidate list is wider than the displayed list, and must stay so.
    func test_hidingFromTheOverlayDoesNotAlterTheCandidateFrame() {
        var subject = filter()
        let candidates = frame([
            candidate("apple", 0.80, box(0.1, 0.1)),
            candidate("pear", 0.33, box(0.5, 0.5)),
        ])

        let shown = subject.display(candidates, at: epoch)

        XCTAssertEqual(shown.ingredients.map(\.ingredientId), ["apple"])
        XCTAssertEqual(candidates.ingredients.count, 2,
                       "the input is a value type and must come back untouched")
    }

    func test_borderlineConfidencesLandOnTheRightSideOfEveryBoundary() {
        var subject = filter()
        let cases: [(Float, Bool, String)] = [
            (0.3999, false, "just under the floor"),
            (0.40, true, "exactly the floor"),
            (0.4001, true, "just over the floor"),
            (0.5999, true, "just under the strong band"),
            (0.60, true, "exactly the strong band"),
        ]

        for (confidence, expected, description) in cases {
            subject.reset()
            let shown = subject.display(
                frame([candidate("apple", confidence, box(0.1, 0.1))]), at: epoch
            )
            XCTAssertEqual(!shown.isEmpty, expected, "\(description) (\(confidence))")
        }
    }

    func test_theStrongBandChangesPresentationNotTrust() {
        var subject = filter()

        let shown = subject.display(
            frame([
                candidate("apple", 0.85, box(0.1, 0.1)),
                candidate("pear", 0.45, box(0.5, 0.5)),
            ]),
            at: epoch
        )

        let apple = shown.ingredients.first { $0.ingredientId == "apple" }
        let pear = shown.ingredients.first { $0.ingredientId == "pear" }
        XCTAssertEqual(apple?.band, .strong)
        XCTAssertEqual(pear?.band, .tentative)
        // Neither is verified, however confident. This is the rule that keeps
        // a 0.837 misclassification from being presented as settled.
        XCTAssertEqual(shown.ingredients.filter(\.isVerified).count, 0)
        XCTAssertTrue(shown.ingredients.allSatisfy(\.requiresConfirmation))
    }

    // MARK: - Empty results

    func test_anEmptyCandidateFrameProducesAnEmptyDisplayFrame() {
        var subject = filter()

        let shown = subject.display(frame([]), at: epoch)

        XCTAssertTrue(shown.isEmpty)
        XCTAssertEqual(shown.sourceSize, CGSize(width: 640, height: 480),
                       "geometry survives so the overlay can still lay out an empty state")
    }

    func test_aFrameOfOnlyWeakCandidatesProducesNothingRatherThanTheBestWeakOne() {
        var subject = filter()

        let shown = subject.display(
            frame([
                candidate("apple", 0.39, box(0.1, 0.1)),
                candidate("pear", 0.38, box(0.5, 0.5)),
                candidate("grape", 0.31, box(0.8, 0.8)),
            ]),
            at: epoch
        )

        XCTAssertTrue(shown.isEmpty, "there is no floor for 'show something anyway'")
    }

    // MARK: - The per-ingredient box budget

    /// The measured regression. A flat top-N cap let one ingredient take every
    /// slot: on `fruits_mixed` the overlay drew 9 apples and 3 bananas and hid
    /// the orange, pear, pineapple and strawberry the model had found.
    func test_oneIngredientCannotConsumeTheWholeFrameBudget() {
        var subject = filter(perIngredient: 3, maximum: 6)
        var candidates = (0..<10).map { index in
            candidate("apple", 0.90 - Float(index) * 0.01, box(CGFloat(index) * 0.09, 0.1, 0.05))
        }
        candidates.append(candidate("pear", 0.45, box(0.1, 0.6)))
        candidates.append(candidate("grape", 0.44, box(0.4, 0.6)))

        let shown = subject.display(frame(candidates), at: epoch)

        XCTAssertEqual(shown.ingredients.filter { $0.ingredientId == "apple" }.count, 3)
        XCTAssertEqual(
            Set(shown.ingredients.map(\.ingredientId)), ["apple", "pear", "grape"],
            "every ingredient the model found above the floor should be representable"
        )
    }

    /// Budgeting is not duplicate suppression. Several apples in a bowl are
    /// several real apples, and the best ones are kept, not merged.
    func test_multipleSeparateObjectsOfOneIngredientAreAllDrawnUpToTheBudget() {
        var subject = filter(perIngredient: 3)

        let shown = subject.display(
            frame([
                candidate("apple", 0.90, box(0.05, 0.05)),
                candidate("apple", 0.80, box(0.40, 0.05)),
                candidate("apple", 0.70, box(0.75, 0.05)),
            ]),
            at: epoch
        )

        XCTAssertEqual(shown.ingredients.count, 3, "three distant apples are three apples")
        XCTAssertEqual(Set(shown.ingredients.map(\.boundingBox)).count, 3)
    }

    func test_theBudgetKeepsTheBestBoxesForAnIngredient() {
        var subject = filter(perIngredient: 2)

        let shown = subject.display(
            frame([
                candidate("apple", 0.90, box(0.05, 0.05)),
                candidate("apple", 0.80, box(0.40, 0.05)),
                candidate("apple", 0.50, box(0.75, 0.05)),
            ]),
            at: epoch
        )

        XCTAssertEqual(shown.ingredients.map(\.confidence), [0.90, 0.80])
    }

    func test_theFrameBudgetStillCapsTheTotal() {
        var subject = filter(perIngredient: 3, maximum: 4)
        let candidates = ["apple", "pear", "grape", "lemon", "mango"].enumerated().map {
            candidate($0.element, 0.90 - Float($0.offset) * 0.05, box(CGFloat($0.offset) * 0.15, 0.1))
        }

        let shown = subject.display(frame(candidates), at: epoch)

        XCTAssertEqual(shown.ingredients.count, 4)
        XCTAssertEqual(shown.ingredients.map(\.ingredientId), ["apple", "pear", "grape", "lemon"],
                       "the cap takes from the bottom by confidence")
    }

    func test_aBudgetOfZeroDrawsNothing() {
        let shown = DetectionDisplayFilter.applyPerIngredientBudget(
            to: [candidate("apple", 0.9, box(0.1, 0.1))], limit: 0
        )

        XCTAssertTrue(shown.isEmpty)
    }

    // MARK: - Stability across frames

    /// Flicker. A detection oscillating around the floor would otherwise
    /// appear and disappear every third of a second.
    func test_aDisplayedDetectionSurvivesADipBelowTheThreshold() {
        var subject = filter(display: 0.40, release: 0.34)

        let first = subject.display(frame([candidate("apple", 0.45, box(0.1, 0.1))]), at: epoch)
        let second = subject.display(
            frame([candidate("apple", 0.36, box(0.1, 0.1))]),
            at: epoch.addingTimeInterval(0.33)
        )

        XCTAssertEqual(first.ingredients.count, 1)
        XCTAssertEqual(second.ingredients.count, 1, "0.36 is above the release floor")
    }

    func test_hysteresisNeverAdmitsADetectionThatWasNotAlreadyShown() {
        var subject = filter(display: 0.40, release: 0.34)

        let first = subject.display(frame([candidate("apple", 0.36, box(0.1, 0.1))]), at: epoch)
        let second = subject.display(
            frame([candidate("apple", 0.36, box(0.1, 0.1))]),
            at: epoch.addingTimeInterval(0.33)
        )

        XCTAssertTrue(first.isEmpty, "entry is at the display threshold, not the release one")
        XCTAssertTrue(second.isEmpty, "and a frame that drew nothing retains nothing")
    }

    func test_aDetectionBelowTheReleaseThresholdIsDropped() {
        var subject = filter(display: 0.40, release: 0.34)

        _ = subject.display(frame([candidate("apple", 0.45, box(0.1, 0.1))]), at: epoch)
        let second = subject.display(
            frame([candidate("apple", 0.33, box(0.1, 0.1))]),
            at: epoch.addingTimeInterval(0.33)
        )

        XCTAssertTrue(second.isEmpty, "0.33 is below the release floor and goes")
    }

    func test_aStableStreamProducesAStableFrame() {
        var subject = filter()
        let candidates = frame([
            candidate("apple", 0.72, box(0.1, 0.1)),
            candidate("pear", 0.55, box(0.5, 0.5)),
        ])

        var identities: [[String]] = []
        for step in 0..<5 {
            let shown = subject.display(candidates, at: epoch.addingTimeInterval(Double(step) * 0.33))
            identities.append(shown.ingredients.map(\.ingredientId))
        }

        XCTAssertEqual(identities, Array(repeating: ["apple", "pear"], count: 5))
    }

    // MARK: - Staleness

    func test_aLongGapDiscardsTheRetainedSet() {
        var subject = filter(display: 0.40, release: 0.34, staleAfter: 1.5)

        _ = subject.display(frame([candidate("apple", 0.45, box(0.1, 0.1))]), at: epoch)
        // Two seconds later the stream is no longer describing the same scene,
        // so the weak apple does not get to inherit its place.
        let afterGap = subject.display(
            frame([candidate("apple", 0.36, box(0.1, 0.1))]),
            at: epoch.addingTimeInterval(2.0)
        )

        XCTAssertTrue(afterGap.isEmpty)
    }

    func test_stalenessIsReportedOnceTheWindowHasPassed() {
        var subject = filter(staleAfter: 1.5)

        XCTAssertFalse(subject.isStale(at: epoch), "nothing has been displayed yet")
        _ = subject.display(frame([candidate("apple", 0.80, box(0.1, 0.1))]), at: epoch)

        XCTAssertFalse(subject.isStale(at: epoch.addingTimeInterval(1.0)))
        XCTAssertTrue(subject.isStale(at: epoch.addingTimeInterval(1.6)))
    }

    func test_resetForgetsEverything() {
        var subject = filter()

        _ = subject.display(frame([candidate("apple", 0.45, box(0.1, 0.1))]), at: epoch)
        subject.reset()

        XCTAssertNil(subject.lastFrameAt)
        XCTAssertFalse(subject.isStale(at: epoch.addingTimeInterval(100)))
        let afterReset = subject.display(
            frame([candidate("apple", 0.36, box(0.1, 0.1))]),
            at: epoch.addingTimeInterval(0.33)
        )
        XCTAssertTrue(afterReset.isEmpty, "a reset filter retains nothing to carry over")
    }

    // MARK: - Ordering and metadata

    func test_displayedDetectionsAreOrderedByConfidence() {
        var subject = filter()

        let shown = subject.display(
            frame([
                candidate("apple", 0.55, box(0.1, 0.1)),
                candidate("pear", 0.90, box(0.4, 0.1)),
                candidate("grape", 0.70, box(0.7, 0.1)),
            ]),
            at: epoch
        )

        XCTAssertEqual(shown.ingredients.map(\.ingredientId), ["pear", "grape", "apple"])
    }

    func test_geometryAndSourceSurviveFiltering() {
        var subject = filter()

        let shown = subject.display(
            IngredientDetectionFrame(
                ingredients: [candidate("apple", 0.80, box(0.1, 0.1))],
                sourceSize: CGSize(width: 1280, height: 720),
                source: .cocoFallback
            ),
            at: epoch
        )

        XCTAssertEqual(shown.sourceSize, CGSize(width: 1280, height: 720))
        XCTAssertEqual(shown.source, .cocoFallback)
    }

    // MARK: - High-confidence misclassifications

    /// The headline finding, pinned as a test: raising the display threshold
    /// does not remove the errors it is supposed to remove.
    ///
    /// These are the real terms and real confidences the installed model
    /// produces on the evaluation images - a carton of eggs read as `orange`
    /// at 0.726, raw beef as `bread loaf` at 0.712, and a courgette as
    /// `bell pepper` at 0.837, which is the most confident detection in the
    /// entire set. Every one of them clears any threshold that leaves useful
    /// recall intact.
    func test_raisingTheDisplayThresholdDoesNotSuppressConfidentMistakes() {
        let measuredMistakes: [(String, Float)] = [
            ("bell_pepper", 0.837),  // veg_mixed, there is no pepper in it
            ("orange", 0.726),       // eggs_carton
            ("bread_loaf", 0.712),   // beef_raw
        ]

        for threshold in [Float(0.40), 0.50, 0.60, 0.65, 0.70] {
            var subject = filter(display: threshold, release: threshold - 0.06)
            let shown = subject.display(
                frame(measuredMistakes.enumerated().map { index, mistake in
                    candidate(mistake.0, mistake.1, box(CGFloat(index) * 0.3, 0.1))
                }),
                at: epoch
            )
            XCTAssertFalse(
                shown.isEmpty,
                """
                At \(threshold) the confident mistakes still display. This test \
                exists to stop anyone claiming the threshold fixed them - it \
                cannot, and the fix is corroboration, not a higher number.
                """
            )
        }
    }

    /// And the corollary: a threshold high enough to remove them removes
    /// everything. At 0.80 on the evaluation set the only detection left in
    /// all 11 images was a wrong one, so precision measured 0.0.
    func test_aThresholdHighEnoughToSuppressThemAlsoSuppressesCorrectDetections() {
        var subject = filter(display: 0.85, release: 0.80)

        let shown = subject.display(
            frame([
                candidate("bell_pepper", 0.837),  // the wrong one
                candidate("apple", 0.792),        // a right one, scored lower
                candidate("banana", 0.793),       // another right one
            ].map { $0 }),
            at: epoch
        )

        XCTAssertTrue(shown.isEmpty, "the error and the correct detections go together")
    }

    private func candidate(_ ingredientId: String, _ confidence: Float) -> DetectedIngredient {
        candidate(ingredientId, confidence, box(0.1, 0.1))
    }
}
