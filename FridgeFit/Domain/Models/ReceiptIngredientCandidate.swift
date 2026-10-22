//
//  ReceiptIngredientCandidate.swift
//  FridgeFit
//

import Foundation

/// A receipt item after deterministic validation and canonicalization -
/// what the confirmation screen is allowed to show.
///
/// `classification` and `category` are real enums by this point,
/// `canonicalName` has been through `IngredientCanonicalizer`, and
/// `isAlreadyInPantry` comes from reading the actual pantry in
/// `ScanReceiptUseCase`, never from the model.
///
/// Still not a pantry item: nothing is stored until the user confirms it.
nonisolated struct ReceiptIngredientCandidate: Identifiable, Equatable {
    let id: UUID
    /// What the user sees, in their own terms - "Red Capsicum", not
    /// "bell_pepper".
    let displayName: String
    /// The stable internal identity used for deduplication and for matching
    /// against the pantry. Never shown in the UI.
    let canonicalName: String
    let classification: ReceiptItemClassification
    let category: IngredientCategory
    /// The quantity written on the receipt, or `nil` when the receipt did
    /// not state one. `nil` is a real answer, not a missing value to fill in.
    let quantity: ReceiptQuantity?
    /// The receipt line this came from, shown under the name so the user can
    /// check a detection against the paper in their hand.
    let sourceText: String
    /// Reading order on the receipt, so the review list matches the receipt.
    let order: Int
    /// Set by `ScanReceiptUseCase` from the real pantry.
    let isAlreadyInPantry: Bool

    init(
        id: UUID = UUID(),
        displayName: String,
        canonicalName: String,
        classification: ReceiptItemClassification,
        category: IngredientCategory,
        quantity: ReceiptQuantity?,
        sourceText: String,
        order: Int,
        isAlreadyInPantry: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.canonicalName = canonicalName
        self.classification = classification
        self.category = category
        self.quantity = quantity
        self.sourceText = sourceText
        self.order = order
        self.isAlreadyInPantry = isAlreadyInPantry
    }

    /// Copy of this candidate with pantry knowledge applied.
    func markingAlreadyInPantry(_ isAlreadyInPantry: Bool) -> ReceiptIngredientCandidate {
        ReceiptIngredientCandidate(
            id: id,
            displayName: displayName,
            canonicalName: canonicalName,
            classification: classification,
            category: category,
            quantity: quantity,
            sourceText: sourceText,
            order: order,
            isAlreadyInPantry: isAlreadyInPantry
        )
    }
}

/// The full result of a receipt scan: what will be offered to the pantry,
/// and what was deliberately set aside.
///
/// `excluded` exists so a scan is inspectable. The confirmation screen shows
/// only `pantryCandidates`, which is the whole point of the
/// classification - but silently dropping half the receipt makes the feature
/// impossible to debug, so the rejected items stay attached to the result
/// and are surfaced in DEBUG diagnostics.
/// `source` records whether the model actually ran for this result or
/// whether a previously verified run was replayed. It travels with the
/// outcome rather than being inferred later, so the UI can never present a
/// replay as fresh analysis. It defaults to `.appleIntelligence` because
/// that is what every producer of this type did before the cache existed.
nonisolated struct ReceiptScanOutcome: Equatable {
    let pantryCandidates: [ReceiptIngredientCandidate]
    let excluded: [ReceiptIngredientCandidate]
    let source: ReceiptRecognitionSource

    init(
        pantryCandidates: [ReceiptIngredientCandidate],
        excluded: [ReceiptIngredientCandidate] = [],
        source: ReceiptRecognitionSource = .appleIntelligence
    ) {
        self.pantryCandidates = pantryCandidates
        self.excluded = excluded
        self.source = source
    }

    var isEmpty: Bool { pantryCandidates.isEmpty }

    static let empty = ReceiptScanOutcome(pantryCandidates: [], excluded: [])

    /// Copy of this outcome with pantry membership applied to its
    /// candidates, preserving everything else - including `source`.
    func markingPantryMembership(_ isMember: (ReceiptIngredientCandidate) -> Bool) -> ReceiptScanOutcome {
        ReceiptScanOutcome(
            pantryCandidates: pantryCandidates.map { $0.markingAlreadyInPantry(isMember($0)) },
            excluded: excluded,
            source: source
        )
    }
}
