//
//  DetectionFilterPolicy.swift
//  FridgeFit
//

import CoreGraphics
import Foundation

/// Every number that decides whether a prediction is seen, in one place.
///
/// ## The four stages, kept apart on purpose
///
/// 1. **Raw predictions** - what the Core ML pipeline emits, after its own
///    baked-in per-class NMS. Nothing in this type touches them; the floor the
///    model is asked for is `candidateThreshold`, set on
///    `YOLOFoodDetectionService.Configuration`.
/// 2. **Accepted candidates** - raw predictions mapped onto ingredient
///    identities: decoys dropped, ambiguous classes genericised, same-ingredient
///    overlaps merged. `IngredientNormalizer` produces these. This is the list
///    the snapshot pipeline and fusion work from.
/// 3. **Displayed detections** - the subset drawn over live video.
///    `DetectionDisplayFilter` produces these, and it is *lossy on purpose*.
/// 4. **Review suggestions** - what the review sheet proposes, which comes
///    from fusion over stage 2, never from stage 3.
///
/// Stage 3 being lossy is the whole point, and stage 4 reading stage 2 is why
/// it is safe: a detection hidden from the overlay is still available to the
/// classifier, to OCR and to fusion, so a weak YOLO box that Apple Vision
/// independently corroborates still reaches the user. Hiding is a statement
/// about the live overlay's signal-to-noise, not a deletion.
///
/// ## Why these particular numbers
///
/// Measured over the 11-image annotated set with
/// `tools/yolo-export/sweep_display_policy.py`, applying this exact policy
/// rather than raw model output. The full table is in
/// `docs/detection-confidence-filtering.md`. Headlines:
///
/// - `displayThreshold` 0.40 maximises F1 (0.357). 0.45 trades 10.5 points of
///   recall for 4.4 of precision; by 0.80 recall is zero and the *only*
///   surviving detection in the whole set is a wrong one, so precision is 0.0.
/// - `maximumBoxesPerIngredient` is where the precision actually came from. A
///   flat top-12-by-confidence cap let one well-detected ingredient take every
///   slot - 9 apple boxes and 3 banana boxes on a fruit bowl, with the orange,
///   pear, pineapple and strawberry the model *had* found pushed out. Budgeting
///   per ingredient lifted precision 0.417 → 0.556 and recall 0.132 → 0.263
///   while *reducing* boxes per image from 3.27 to 2.82.
/// - `strongThreshold` separates two visual treatments. It does **not** mean
///   verified; see `DetectionConfidenceBand`.
///
/// Two things were measured and deliberately **not** adopted:
///
/// - **Cross-class spatial NMS.** At every IoU from 0.60 to 0.85 it removed a
///   correct `zucchini` from `veg_mixed` along with one false positive, netting
///   F1 down (0.357 → 0.333). Separate physical objects overlap; suppressing
///   across classes on this evidence would cost more than it saved.
/// - **Decoy veto** (dropping a food box a more-confident decoy covers). Zero
///   effect on all 11 images. No measured benefit, so no code.
///
/// ## The limitation, stated plainly
///
/// 11 images and 38 annotated ingredients is a smoke test. It is enough to
/// rank 0.40 against 0.80 and to show the box-budget fix is a real gain; it is
/// not enough to choose between 0.40 and 0.42, and it cannot support
/// per-category thresholds - several categories have a single image. These are
/// therefore conservative provisional settings, pinned by tests so a change is
/// deliberate.
nonisolated struct DetectionFilterPolicy: Sendable, Equatable {

    // MARK: Stage 2 - accepted candidates

    /// Floor for a prediction to become a candidate ingredient at all.
    ///
    /// Deliberately *below* `displayThreshold`. The snapshot pipeline runs
    /// region classification and OCR over candidates, both of which can
    /// corroborate a box the live overlay chose not to draw. Raising this to
    /// match the display floor would silently delete those.
    var candidateThreshold: Float = 0.30

    /// Cap on candidates carried into classification and fusion.
    ///
    /// Generous: a Vision request per box costs ~30 ms for a whole image on
    /// the snapshot path, which runs once rather than per frame.
    var maximumCandidates: Int = 24

    // MARK: Stage 3 - the live overlay

    /// Below this, nothing is drawn.
    var displayThreshold: Float = 0.40

    /// Confidence an already-drawn box may fall to before it is removed.
    ///
    /// Pure hysteresis, and it fixes a visible artefact rather than a metric:
    /// a detection oscillating around 0.40 between frames makes the box blink.
    /// Entry stays at `displayThreshold`, so this never *adds* a detection -
    /// it only lets one that already earned its place persist through a dip.
    var displayReleaseThreshold: Float = 0.34

    /// Boundary between the two visual treatments.
    ///
    /// Not a trust boundary. On this evaluation set the single
    /// highest-confidence detection in all 11 images - `bell pepper` at 0.837
    /// on `veg_mixed` - is wrong, and 5 of the 18 claims in this band are
    /// wrong (72.2% precision). High confidence means "drawn solid", never
    /// "verified".
    var strongThreshold: Float = 0.60

    /// Two boxes of the same ingredient overlapping by more than this are one
    /// object. Only ever applied *within* an ingredient identity.
    var duplicateIoU: CGFloat = 0.55

    /// Boxes one ingredient identity may occupy in the frame budget.
    ///
    /// Not duplicate suppression - these are separate physical objects and the
    /// model is right about all of them. It is a fairness rule for a fixed
    /// number of slots. 2, 3 and 4 scored identically on the evaluation set;
    /// 3 is the middle, and 6 lost most of the gain.
    var maximumBoxesPerIngredient: Int = 3

    /// Total boxes drawn per frame.
    var maximumDisplayedBoxes: Int = 12

    /// How long a displayed frame stays valid without a replacement.
    ///
    /// At the tap's ~3 FPS a gap this long means inference has stalled or the
    /// stream has, and boxes measured against a frame that old are no longer
    /// describing what is on screen. Clearing beats drifting.
    var staleAfter: TimeInterval = 1.5

    // MARK: Stage 4 - review suggestions

    /// Floor for a fused claim to be offered in the review sheet.
    ///
    /// Matches `candidateThreshold` rather than `displayThreshold`, for the
    /// same reason: review is where a second method's opinion is available, so
    /// it should see more than the overlay does, not less.
    var reviewThreshold: Float = 0.30

    static let `default` = DetectionFilterPolicy()

    /// Policy for the COCO YOLO11n fallback.
    ///
    /// Its ten classes are closed-vocabulary and its confidences are better
    /// calibrated than the open-vocabulary model's, so it keeps the thresholds
    /// it was originally tuned with. Nothing in the sweep above describes this
    /// model, so nothing in the sweep above is applied to it.
    static let cocoFallback: DetectionFilterPolicy = {
        var policy = DetectionFilterPolicy()
        policy.candidateThreshold = 0.40
        policy.displayThreshold = 0.45
        policy.displayReleaseThreshold = 0.40
        policy.strongThreshold = 0.60
        policy.reviewThreshold = 0.40
        return policy
    }()

    /// Band a confidence falls in, for display only.
    func band(for confidence: Float) -> DetectionConfidenceBand {
        confidence >= strongThreshold ? .strong : .tentative
    }
}

/// How a *displayed* detection is drawn.
///
/// Two cases, and neither of them is "verified". A `DetectedIngredient` comes
/// from one method - the detector - and one method's opinion is a candidate
/// however confident it sounds. Verification requires a second, independent
/// method agreeing about the same pixels, which is `ConfidenceTier.agreed` on
/// `FusedIngredient` and only ever exists on the snapshot path.
///
/// Keeping the two concepts in different types is deliberate: there is no
/// value of this enum that a detector-only claim can reach that means trusted.
nonisolated enum DetectionConfidenceBand: String, Codable, Equatable, Sendable, CaseIterable {
    /// Above the display floor, below `strongThreshold`. Drawn dashed.
    case tentative
    /// At or above `strongThreshold`. Drawn solid - which says "the model is
    /// confident", not "this is correct".
    case strong

    /// Whether the overlay draws this with a broken stroke.
    var isDashed: Bool { self == .tentative }
}
