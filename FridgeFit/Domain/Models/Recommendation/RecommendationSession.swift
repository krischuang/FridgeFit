//
//  RecommendationSession.swift
//  FridgeFit
//

import Foundation

/// What the user did with a recipe during the current recommendation
/// session.
nonisolated enum SessionRecipeFeedbackAction: Equatable, Hashable, Sendable {
    case saved
    case skipped
    case reported(SessionRecipeFeedbackReason)
}

/// A predefined reason for rejecting a recommendation.
///
/// A fixed set rather than free text because each one maps to a specific,
/// testable change in ranking - "takes too long" reorders by cooking time,
/// not by sentiment.
nonisolated enum SessionRecipeFeedbackReason: String, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case tooMuchShopping
    case takesTooLong
    case tooDifficult
    case notMyTaste

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .tooMuchShopping: return "Requires too much shopping"
        case .takesTooLong: return "Takes too long"
        case .tooDifficult: return "Too difficult"
        case .notMyTaste: return "Not my taste"
        }
    }
}

/// One recorded response to a recommendation.
nonisolated struct SessionRecipeFeedback: Equatable, Hashable, Sendable {
    let recipeID: UUID
    let action: SessionRecipeFeedbackAction
}

/// One temporary recommendation session.
///
/// ## Why this is not persisted
///
/// A session begins when the user asks for recommendations and ends when
/// they leave the flow. Nothing here is written to Firestore, and that is
/// the intended design rather than an unfinished one:
///
/// - The feedback is about *this* list in *this* pantry state. "Too much
///   shopping" stops being true as soon as the user buys the ingredient.
/// - Persisting it would mean a new user-scoped Firestore collection and
///   new security rules, which the brief asks not to add without a
///   demonstrated requirement.
/// - It keeps the influence auditable: ranking depends only on the
///   recipes, the pantry, the context, and this value type, so the tests
///   can state an expected order exactly.
///
/// Feedback never touches `Recipe` or `PantryItem`. This type only ever
/// holds recipe ids, so no amount of skipping or reporting can alter
/// stored pantry or recipe data.
nonisolated struct RecommendationSession: Equatable, Sendable {
    let id: UUID
    private(set) var isActive: Bool
    private(set) var feedbackByRecipeID: [UUID: SessionRecipeFeedbackAction]

    init(id: UUID = UUID()) {
        self.id = id
        self.isActive = true
        self.feedbackByRecipeID = [:]
    }

    /// Records the user's latest action for a recipe, replacing any
    /// earlier action for the same recipe.
    mutating func record(_ feedback: SessionRecipeFeedback) {
        feedbackByRecipeID[feedback.recipeID] = feedback.action
    }

    /// Clears any action recorded for a recipe, so the user can undo.
    mutating func clearFeedback(for recipeID: UUID) {
        feedbackByRecipeID[recipeID] = nil
    }

    func feedback(for recipeID: UUID) -> SessionRecipeFeedbackAction? {
        feedbackByRecipeID[recipeID]
    }

    var recordedFeedback: [UUID: SessionRecipeFeedbackAction] {
        feedbackByRecipeID
    }

    /// Recipes the user saved during this session.
    var savedRecipeIDs: Set<UUID> {
        Set(feedbackByRecipeID.filter { $0.value == .saved }.keys)
    }

    /// Ends the session. An inactive session has no influence on ranking.
    mutating func end() {
        isActive = false
    }
}
