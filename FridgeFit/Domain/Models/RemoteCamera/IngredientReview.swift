//
//  IngredientReview.swift
//  FridgeFit
//

import CoreGraphics
import Foundation

/// What the Analyse Ingredients action is doing.
nonisolated enum SnapshotAnalysisPhase: Equatable, Sendable {
    case idle
    /// Waiting for the remote camera to send a photo.
    case capturing
    /// Running detection, classification and OCR on the photo.
    case analysing
    case failed(String)

    var isBusy: Bool { self == .capturing || self == .analysing }

    /// What to show next to the spinner. Capture and analysis are separated
    /// because a 20-second transfer and a sub-second analysis feel completely
    /// different, and one label for both reads as a hang.
    var message: String? {
        switch self {
        case .idle: return nil
        case .capturing: return "Asking the camera for a photo…"
        case .analysing: return "Analysing ingredients…"
        case .failed(let reason): return reason
        }
    }

    var failureReason: String? {
        if case .failed(let reason) = self { return reason }
        return nil
    }
}

/// How far the pantry save has got.
///
/// `partial` is a distinct case rather than a flavour of success, because
/// "three added, two already there, one had no quantity" is the normal
/// outcome of a real basket and the user needs to see which was which. The
/// summary type already models that; this just stops the UI collapsing it to
/// a tick.
nonisolated enum PantrySaveState: Equatable, Sendable {
    case idle
    case saving
    /// Everything the user confirmed went in.
    case succeeded(AddDetectedIngredientsSummary)
    /// Some went in; some were duplicates or failed validation.
    case partial(AddDetectedIngredientsSummary)
    /// Nothing went in - no use case wired, or every row failed.
    case failed(String)

    var isSaving: Bool { self == .saving }

    /// Whether the sheet may close itself.
    ///
    /// Only a clean success. A partial result has something the user has to
    /// read, and a failure has something they may want to retry.
    var allowsAutomaticDismissal: Bool {
        if case .succeeded = self { return true }
        return false
    }

    /// The summary to display, if the save produced one.
    var summary: AddDetectedIngredientsSummary? {
        switch self {
        case .succeeded(let summary), .partial(let summary): return summary
        case .idle, .saving, .failed: return nil
        }
    }

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }

    /// Whether retrying makes sense from here.
    var isRetryable: Bool {
        switch self {
        case .failed: return true
        case .partial(let summary): return !summary.failures.isEmpty
        case .idle, .saving, .succeeded: return false
        }
    }
}

/// Where a review row came from.
nonisolated enum ReviewItemOrigin: Equatable, Sendable {
    /// Produced by recognition.
    case recognised
    /// Typed in by the user because recognition missed it.
    case manual
}

/// One row in the review list: a candidate the user can accept, reject, or
/// correct.
///
/// Holds the recognition facts read-only and the user's decisions mutably.
/// The two are kept apart on purpose - renaming a row must not rewrite what
/// the model actually said, because the raw term is the only way to tell
/// later whether the model was wrong or the mapping was.
nonisolated struct IngredientReviewItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let origin: ReviewItemOrigin

    // What recognition said. Immutable.
    let recognised: FusedIngredient?

    // What the user decided. Mutable.
    var displayName: String
    var category: IngredientGroup
    var isAccepted: Bool

    /// The amount to store. **Starts empty and is never defaulted.**
    ///
    /// Recognition sees that a thing is there, not how much of it. Defaulting
    /// to `1 pcs` would put a number nobody stated into the pantry whenever
    /// the user did not notice - the exact mistake `ReceiptItemDraft`
    /// documents the old fridge-scan flow making. An empty quantity is
    /// rejected by `AddDetectedIngredientsUseCase` with a message saying what
    /// to fill in, which is the correct outcome for a number nobody knows.
    var quantityText: String
    var unit: MeasurementUnit

    /// Where this goes in the pantry, when the user wants something other
    /// than the mapping from `category`.
    ///
    /// `nil` means "follow `category`". The mapping is deliberately lossy -
    /// fruit and vegetable both become `.produce`, and the detection
    /// taxonomy has no `.grain` or `.spice` at all - so an override has to
    /// exist for the cases the mapping cannot express.
    var pantryCategoryOverride: IngredientCategory?

    init(
        id: UUID = UUID(),
        origin: ReviewItemOrigin,
        recognised: FusedIngredient?,
        displayName: String,
        category: IngredientGroup,
        isAccepted: Bool,
        quantityText: String = "",
        unit: MeasurementUnit = .pieces,
        pantryCategoryOverride: IngredientCategory? = nil
    ) {
        self.id = id
        self.origin = origin
        self.recognised = recognised
        self.displayName = displayName
        self.category = category
        self.isAccepted = isAccepted
        self.quantityText = quantityText
        self.unit = unit
        self.pantryCategoryOverride = pantryCategoryOverride
    }

    /// The quantity to store, or `nil` if the field is empty or unusable.
    /// `AddPantryItemUseCase` still has the final say.
    var quantity: Double? {
        let trimmed = quantityText.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value > 0 else { return nil }
        return value
    }

    /// Whether this row can actually be stored.
    ///
    /// Accepting a row is not the same as being ready to save it: the user
    /// has said "yes, that is an onion" without yet saying how much.
    var hasValidQuantity: Bool { quantity != nil }

    /// The pantry category this will be filed under.
    var resolvedPantryCategory: IngredientCategory {
        pantryCategoryOverride ?? category.pantryCategory
    }

    /// The storage-shaped value, for `AddDetectedIngredientsUseCase`.
    var pantryDraft: ConfirmedIngredientDraft {
        ConfirmedIngredientDraft(
            name: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            reportingName: displayName,
            quantity: quantity,
            unit: unit,
            category: resolvedPantryCategory
        )
    }

    /// Builds a row from a recognition result, pre-ticked only if the result
    /// earned it.
    init(_ ingredient: FusedIngredient) {
        self.init(
            id: ingredient.id,
            origin: .recognised,
            recognised: ingredient,
            displayName: ingredient.displayName,
            category: ingredient.category,
            isAccepted: ingredient.isPreselected
        )
    }

    /// A row the user added by hand. Accepted by definition - they typed it.
    init(manualName name: String, category: IngredientGroup) {
        self.init(
            id: UUID(),
            origin: .manual,
            recognised: nil,
            displayName: name,
            category: category,
            isAccepted: true
        )
    }

    var tier: ConfidenceTier? { recognised?.tier }
    var sources: EvidenceSources { recognised?.sources ?? [] }
    var boundingBox: CGRect? { recognised?.boundingBox }
    var confidence: Float? { recognised?.confidence }
    var conflictingClaim: String? { recognised?.conflictingClaim }
    var reviewReason: ReviewReason? { recognised?.reviewReason }

    /// Whether the user changed the name or category away from what
    /// recognition proposed.
    var wasEdited: Bool {
        guard let recognised else { return false }
        return displayName != recognised.displayName || category != recognised.category
    }

    var requiresReview: Bool {
        origin == .manual ? false : (recognised?.requiresReview ?? true)
    }
}

/// What the user confirmed, locally.
///
/// Stage 3 turns these into pantry items. Nothing in Stage 2 persists them -
/// this type is the boundary where recognition stops and the user's decision
/// begins, which is exactly why it carries no model confidence at all: once a
/// person has said "yes, that is an onion", the model's 0.43 is irrelevant.
nonisolated struct ConfirmedIngredient: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let category: IngredientGroup
    /// Whether the user typed this rather than confirming a suggestion.
    let wasManuallyAdded: Bool
    /// Whether the user corrected the name or category.
    let wasCorrected: Bool
    /// The stable ingredient identifier recognition proposed, if any. Kept so
    /// a later pantry write can be traced back, not because it is trusted.
    let recognisedIngredientId: String?
    /// The amount the user supplied. `nil` if they never did - the pantry
    /// write will reject it and say so rather than invent one.
    let quantity: Double?
    let unit: MeasurementUnit
    /// Where this goes in the pantry.
    let pantryCategory: IngredientCategory

    init(
        id: UUID = UUID(),
        name: String,
        category: IngredientGroup,
        wasManuallyAdded: Bool,
        wasCorrected: Bool,
        recognisedIngredientId: String?,
        quantity: Double? = nil,
        unit: MeasurementUnit = .pieces,
        pantryCategory: IngredientCategory = .other
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.wasManuallyAdded = wasManuallyAdded
        self.wasCorrected = wasCorrected
        self.recognisedIngredientId = recognisedIngredientId
        self.quantity = quantity
        self.unit = unit
        self.pantryCategory = pantryCategory
    }

    init(_ item: IngredientReviewItem) {
        self.init(
            id: item.id,
            name: item.displayName,
            category: item.category,
            wasManuallyAdded: item.origin == .manual,
            wasCorrected: item.wasEdited,
            recognisedIngredientId: item.recognised?.ingredientId,
            quantity: item.quantity,
            unit: item.unit,
            pantryCategory: item.resolvedPantryCategory
        )
    }
}
