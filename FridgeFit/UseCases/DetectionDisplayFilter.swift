//
//  DetectionDisplayFilter.swift
//  FridgeFit
//

import CoreGraphics
import Foundation

/// Stage 2 → stage 3: candidate ingredients to the boxes actually drawn.
///
/// Separate from `IngredientNormalizer` because this is the only part of the
/// chain with *memory*. Normalisation is a pure function of one frame;
/// deciding what to draw depends on what was drawn last frame, which is what
/// stops boxes blinking.
///
/// ## What it does, in order
///
/// 1. **Entry / release.** A candidate is drawn if it clears
///    `displayThreshold`, or if the same ingredient was drawn in the previous
///    frame and still clears `displayReleaseThreshold`. Entry is never
///    lowered, so hysteresis can only keep a box, never introduce one.
/// 2. **Per-ingredient budget.** At most `maximumBoxesPerIngredient` boxes of
///    one ingredient identity, highest confidence first.
/// 3. **Frame budget.** At most `maximumDisplayedBoxes` in total.
///
/// Step 2 before step 3 is the whole fix. The other order - which is what
/// shipped - let one ingredient with many instances consume the frame budget
/// and push every other ingredient the model had found off the screen.
///
/// ## What it deliberately does not do
///
/// No cross-class suppression. Two different ingredients overlapping is the
/// normal case for food on a plate or in a fridge drawer, and suppressing on
/// that basis measured worse (see `DetectionFilterPolicy`).
///
/// No re-ranking by category, and no per-category threshold. The evaluation
/// set has one or two images per category, which cannot support either.
///
/// ## Thread safety
///
/// A value type with `mutating` methods, so it is confined to whoever owns it.
/// `RemoteCameraViewModel` owns one on the main actor; the frame tap hands
/// results there before it is consulted.
nonisolated struct DetectionDisplayFilter: Sendable {

    let policy: DetectionFilterPolicy

    /// Ingredient identities drawn in the previous frame.
    ///
    /// Keyed by identity rather than by box, because box identity is not
    /// stable across frames - every detection carries a fresh `UUID`, and the
    /// detector makes no attempt to track objects. The practical consequence
    /// is that retention is per ingredient, not per instance: once *an* apple
    /// is on screen, a second apple that dips to 0.36 is also retained. For
    /// the purpose - stopping a box blinking at the threshold - that is the
    /// right granularity, and it is honest about what the detector provides.
    private var retainedIngredientIds: Set<String> = []

    /// When the last frame was accepted, for staleness.
    private(set) var lastFrameAt: Date?

    init(policy: DetectionFilterPolicy = .default) {
        self.policy = policy
    }

    /// Filters one frame of candidates into what the overlay should draw.
    ///
    /// - Parameters:
    ///   - candidates: stage 2 output, as produced by `IngredientNormalizer`.
    ///   - now: injected so staleness and hysteresis are testable without
    ///     sleeping.
    mutating func display(
        _ candidates: IngredientDetectionFrame,
        at now: Date = Date()
    ) -> IngredientDetectionFrame {
        // A long gap means inference stalled or the stream did. Whatever was
        // on screen describes pixels that are no longer there, so it does not
        // get to vote on what is retained.
        if let lastFrameAt, now.timeIntervalSince(lastFrameAt) > policy.staleAfter {
            retainedIngredientIds = []
        }
        lastFrameAt = now

        let admitted = candidates.ingredients
            .filter { shouldDisplay($0) }
            .sorted { $0.confidence > $1.confidence }

        let budgeted = Self.applyPerIngredientBudget(
            to: admitted, limit: policy.maximumBoxesPerIngredient
        )
        let displayed = Array(budgeted.prefix(policy.maximumDisplayedBoxes))

        retainedIngredientIds = Set(displayed.map(\.ingredientId))

        return IngredientDetectionFrame(
            ingredients: displayed,
            sourceSize: candidates.sourceSize,
            source: candidates.source
        )
    }

    /// Whether the overlay should be cleared because no frame has arrived.
    func isStale(at now: Date = Date()) -> Bool {
        guard let lastFrameAt else { return false }
        return now.timeIntervalSince(lastFrameAt) > policy.staleAfter
    }

    /// Forgets everything. Called when the track changes, detection is turned
    /// off, or a session ends - at which point the previous stream's boxes
    /// must not influence the next one's.
    mutating func reset() {
        retainedIngredientIds = []
        lastFrameAt = nil
    }

    // MARK: - Rules

    private func shouldDisplay(_ candidate: DetectedIngredient) -> Bool {
        if candidate.confidence >= policy.displayThreshold { return true }
        // Already on screen, and still above the release floor.
        return retainedIngredientIds.contains(candidate.ingredientId)
            && candidate.confidence >= policy.displayReleaseThreshold
    }

    /// Takes at most `limit` boxes per ingredient identity.
    ///
    /// Not deduplication - the boxes it drops are separate real objects the
    /// model correctly found. It is a cap on how much of a finite overlay one
    /// ingredient may occupy, so that a drawer of twelve carrots does not hide
    /// the courgette next to them.
    ///
    /// - Parameter candidates: must be sorted by descending confidence, so the
    ///   boxes kept for an ingredient are its best ones.
    static func applyPerIngredientBudget(
        to candidates: [DetectedIngredient],
        limit: Int
    ) -> [DetectedIngredient] {
        guard limit > 0 else { return [] }
        var countsByIngredient: [String: Int] = [:]
        var kept: [DetectedIngredient] = []
        for candidate in candidates {
            let used = countsByIngredient[candidate.ingredientId, default: 0]
            guard used < limit else { continue }
            countsByIngredient[candidate.ingredientId] = used + 1
            kept.append(candidate)
        }
        return kept
    }
}
