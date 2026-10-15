//
//  FusedIngredient.swift
//  FridgeFit
//

import CoreGraphics
import Foundation

/// How much independent support an ingredient claim has.
///
/// The ordering is deliberate: higher means better supported, and the UI
/// sorts on it. Nothing here authorises a pantry write - the highest tier
/// means "worth suggesting first", not "true".
nonisolated enum ConfidenceTier: Int, Comparable, Codable, Sendable, CaseIterable {
    /// Exactly one method named it. The common case.
    case singleSource = 1
    /// The detector and the classifier disagree about the same region. Both
    /// candidates are kept and the item is marked uncertain, because
    /// discarding one would be choosing arbitrarily between two methods that
    /// each have the better track record in different categories.
    case conflicting = 0
    /// The detector and the classifier independently named the same
    /// ingredient in the same region.
    ///
    /// The highest-precision tier measured, but **not** infallible: on
    /// `market_crowded` both methods independently reported "pumpkin" and
    /// there is no pumpkin in the photograph. Measured 5/6 correct - 83.3%.
    /// Independence reduces correlated error; it does not remove it. This
    /// tier is a pre-ticked suggestion in a sheet the user still accepts.
    case agreed = 2

    static func < (lhs: ConfidenceTier, rhs: ConfidenceTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .agreed: return "Both methods agree"
        case .singleSource: return "One method only"
        case .conflicting: return "Methods disagree"
        }
    }

    /// Whether the review sheet should pre-tick this. Only agreement, and
    /// even then the user still confirms.
    var isPreselected: Bool { self == .agreed }

    var symbolName: String {
        switch self {
        case .agreed: return "checkmark.seal"
        case .singleSource: return "questionmark.circle"
        case .conflicting: return "exclamationmark.triangle"
        }
    }
}

/// Which methods contributed to a fused claim.
nonisolated struct EvidenceSources: OptionSet, Codable, Sendable {
    let rawValue: Int
    static let detector = EvidenceSources(rawValue: 1 << 0)
    static let regionClassifier = EvidenceSources(rawValue: 1 << 1)
    static let sceneClassifier = EvidenceSources(rawValue: 1 << 2)
    static let packagingText = EvidenceSources(rawValue: 1 << 3)

    var displayNames: [String] {
        var names: [String] = []
        if contains(.detector) { names.append("YOLO") }
        if contains(.regionClassifier) { names.append("Vision (region)") }
        if contains(.sceneClassifier) { names.append("Vision (whole image)") }
        if contains(.packagingText) { names.append("Packaging text") }
        return names
    }
}

/// One ingredient claim after fusing the detector and the classifier.
///
/// Still a candidate. The type exists to carry *how well supported* a guess
/// is into the review step, not to represent anything confirmed.
nonisolated struct FusedIngredient: Identifiable, Equatable, Sendable {
    let id: UUID
    let ingredientId: String
    let displayName: String
    let category: IngredientGroup
    let tier: ConfidenceTier
    let sources: EvidenceSources

    /// Normalised Vision-space box, or `nil` for a scene-level claim.
    ///
    /// **`nil` is load-bearing.** A whole-image classification knows what is
    /// present but not where, and attaching it to one of the detector's boxes
    /// would assert a location nothing measured. Scene-level claims therefore
    /// carry no box and are never drawn as one.
    let boundingBox: CGRect?

    let detectorConfidence: Float?
    let classifierConfidence: Float?
    /// The detector's raw vocabulary term, when the detector contributed.
    let detectorTerm: String?
    /// The classifier's raw Vision identifier, when it contributed.
    let classifierIdentifier: String?
    /// For `.conflicting`: what the other method called this same region.
    let conflictingClaim: String?
    let reviewReason: ReviewReason?
    /// Whether this entry actually asserts that its ingredient is present.
    ///
    /// `false` only for an unresolved conflict under
    /// `ConflictStrategy.deferToUser`: the region is real and is shown, but
    /// neither candidate label is claimed. Evaluation and preselection both
    /// skip these, so "we do not know" is representable rather than being
    /// silently rounded to one of the two guesses.
    let assertsIngredient: Bool

    init(
        id: UUID = UUID(),
        ingredientId: String,
        displayName: String,
        category: IngredientGroup,
        tier: ConfidenceTier,
        sources: EvidenceSources,
        boundingBox: CGRect? = nil,
        detectorConfidence: Float? = nil,
        classifierConfidence: Float? = nil,
        detectorTerm: String? = nil,
        classifierIdentifier: String? = nil,
        conflictingClaim: String? = nil,
        reviewReason: ReviewReason? = nil,
        assertsIngredient: Bool = true
    ) {
        self.id = id
        self.ingredientId = ingredientId
        self.displayName = displayName
        self.category = category
        self.tier = tier
        self.sources = sources
        self.boundingBox = boundingBox
        self.detectorConfidence = detectorConfidence
        self.classifierConfidence = classifierConfidence
        self.detectorTerm = detectorTerm
        self.classifierIdentifier = classifierIdentifier
        self.conflictingClaim = conflictingClaim
        self.reviewReason = reviewReason
        self.assertsIngredient = assertsIngredient
    }

    /// Best available confidence, for sorting within a tier.
    var confidence: Float {
        max(detectorConfidence ?? 0, classifierConfidence ?? 0)
    }

    var confidencePercentage: Int { Int((confidence * 100).rounded()) }

    var requiresReview: Bool { tier != .agreed || reviewReason != nil }

    /// Whether the review sheet should pre-tick this.
    ///
    /// Agreement only, and even then it is a default the user can clear. An
    /// unasserted conflict is never preselected.
    var isPreselected: Bool { tier.isPreselected && assertsIngredient }

    /// Whether this claim is anchored to a measured region.
    var isLocalised: Bool { boundingBox != nil }
}

/// Everything one fusion pass produced.
nonisolated struct FusedDetectionFrame: Equatable, Sendable {
    /// Claims anchored to a measured region, drawable as boxes.
    let localised: [FusedIngredient]
    /// Claims from whole-image classification, which have no location.
    /// Listed separately so nothing can accidentally draw them.
    let sceneLevel: [FusedIngredient]
    let sourceSize: CGSize
    /// Food claims both methods made that are not FridgeFit ingredients,
    /// kept for diagnostics rather than discarded silently.
    let rejectedFoodClaims: [String]

    static let empty = FusedDetectionFrame(
        localised: [], sceneLevel: [], sourceSize: .zero, rejectedFoodClaims: []
    )

    var isEmpty: Bool { localised.isEmpty && sceneLevel.isEmpty }

    /// Everything, for a review list. Agreement first, then single source,
    /// then conflicts; by confidence within a tier.
    var all: [FusedIngredient] {
        (localised + sceneLevel).sorted {
            $0.tier == $1.tier ? $0.confidence > $1.confidence : $0.tier > $1.tier
        }
    }

    func count(of tier: ConfidenceTier) -> Int {
        all.filter { $0.tier == tier }.count
    }

    /// Ingredient identities this frame actually asserts, for scoring.
    var assertedIngredientIds: Set<String> {
        Set(all.filter(\.assertsIngredient).map(\.ingredientId))
    }

    var agreedCount: Int { count(of: .agreed) }
    var conflictCount: Int { count(of: .conflicting) }
}
