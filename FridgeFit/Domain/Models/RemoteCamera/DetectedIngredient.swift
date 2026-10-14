//
//  DetectedIngredient.swift
//  FridgeFit
//

import CoreGraphics
import Foundation

/// Which model produced a detection.
///
/// Carried on every result so the UI can say where a box came from, and so a
/// fallback run is never mistaken for the full ingredient model.
nonisolated enum DetectionSource: String, Codable, Equatable, Sendable {
    /// YOLO-World v2 small, with FridgeFit's ingredient vocabulary.
    case ingredientDetector
    /// The original COCO YOLO11n, used when the ingredient model is
    /// unavailable. Ten food classes only.
    case cocoFallback

    var displayName: String {
        switch self {
        case .ingredientDetector: return "Ingredient model"
        case .cocoFallback: return "COCO fallback"
        }
    }

    var shortName: String {
        switch self {
        case .ingredientDetector: return "YOLO-World"
        case .cocoFallback: return "YOLO11n"
        }
    }
}

/// Why a detection needs a human to confirm it.
nonisolated enum ReviewReason: String, Codable, Equatable, Sendable {
    /// Confidence is above the display floor but below the trust threshold.
    case lowConfidence
    /// The class itself is not visually distinguishable - raw beef, lamb and
    /// pork, for instance. Reported generically rather than guessed.
    case ambiguousClass

    var message: String {
        switch self {
        case .lowConfidence: return "Low confidence - please confirm"
        case .ambiguousClass: return "Looks similar to other ingredients - please confirm"
        }
    }
}

/// A detection after normalisation: a *candidate* ingredient, not a fact, and
/// certainly not a pantry entry.
///
/// Three distinct concepts, deliberately kept apart:
///
/// 1. `DetectedObject` - what the model saw, in its own vocabulary.
/// 2. `DetectedIngredient` - that, mapped onto a stable ingredient identity,
///    with a review flag. **Nothing here is confirmed.**
/// 3. `PantryItem` - something the user has confirmed. Only the user creates
///    these, and nothing in this file writes one.
///
/// This type is the hand-off point for a future
/// Camera → Detection → User Review → Pantry flow: it carries everything
/// `AddDetectedIngredientsUseCase` would need, without presuming anything
/// about when or whether that happens.
nonisolated struct DetectedIngredient: Identifiable, Equatable, Sendable {
    let id: UUID
    /// Stable identifier from the taxonomy, e.g. `"red_meat"`.
    let ingredientId: String
    let displayName: String
    let category: IngredientGroup
    let confidence: Float
    /// Normalised to the oriented frame, Vision orientation - same space as
    /// `DetectedObject.boundingBox`.
    let boundingBox: CGRect
    let source: DetectionSource
    /// Non-nil when the user should confirm before this is trusted.
    let reviewReason: ReviewReason?
    /// The raw model term, kept for diagnostics and so a reviewer can see
    /// what the model actually said.
    let rawTerm: String

    init(
        id: UUID = UUID(),
        ingredientId: String,
        displayName: String,
        category: IngredientGroup,
        confidence: Float,
        boundingBox: CGRect,
        source: DetectionSource,
        reviewReason: ReviewReason? = nil,
        rawTerm: String
    ) {
        self.id = id
        self.ingredientId = ingredientId
        self.displayName = displayName
        self.category = category
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.source = source
        self.reviewReason = reviewReason
        self.rawTerm = rawTerm
    }

    var requiresReview: Bool { reviewReason != nil }

    var confidencePercentage: Int { Int((confidence * 100).rounded()) }

    /// What the overlay prints. Flagged items are marked rather than hidden,
    /// so the user sees the uncertainty instead of a confident-looking label.
    var overlayLabel: String {
        requiresReview
            ? "\(displayName)? \(confidencePercentage)%"
            : "\(displayName) \(confidencePercentage)%"
    }
}

/// A frame's normalised ingredients, with the geometry they were measured
/// against.
nonisolated struct IngredientDetectionFrame: Equatable, Sendable {
    let ingredients: [DetectedIngredient]
    /// Oriented frame size, as displayed.
    let sourceSize: CGSize
    let source: DetectionSource

    static let empty = IngredientDetectionFrame(
        ingredients: [], sourceSize: .zero, source: .ingredientDetector
    )

    var isEmpty: Bool { ingredients.isEmpty }
    var reviewCount: Int { ingredients.filter(\.requiresReview).count }

    /// Distinct categories present, in display order.
    var categories: [IngredientGroup] {
        var seen = Set<IngredientGroup>()
        return ingredients.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }
}
