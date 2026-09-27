//
//  DetectIngredientsUseCase.swift
//  FridgeFit
//

import CoreGraphics
import Foundation
import ImageIO

/// Runs a fridge scan end to end, up to (but not including) the pantry.
///
/// Orchestrates the three things that have to happen in order, so the view
/// model doesn't: check the provider can actually run, get raw detections,
/// then normalize them and reconcile them against the real pantry.
///
/// The pantry check is the important one - `isAlreadyInPantry` is decided
/// here by reading `PantryRepository`, using the same
/// `Ingredient.matches(name:)` rule `AddPantryItemUseCase` uses, so the
/// review screen agrees with what the pantry will accept. The model is never
/// asked, and never told, what's already in the pantry.
struct DetectIngredientsUseCase {
    private let recognitionService: IngredientRecognitionService
    private let pantryRepository: PantryRepository
    private let normalizer: DetectedIngredientNormalizer

    init(
        recognitionService: IngredientRecognitionService,
        pantryRepository: PantryRepository,
        normalizer: DetectedIngredientNormalizer = DetectedIngredientNormalizer()
    ) {
        self.recognitionService = recognitionService
        self.pantryRepository = pantryRepository
        self.normalizer = normalizer
    }

    /// Whether a scan can be started right now.
    var availability: IngredientRecognitionAvailability {
        recognitionService.availability
    }

    /// Detects ingredients in a fridge photo.
    ///
    /// Returns an empty array when nothing recognisable was found - that's a
    /// valid outcome with its own empty state, not an error.
    ///
    /// - Throws: `IngredientRecognitionError` if scanning is unavailable or
    ///   the scan fails, or `CancellationError` if the caller cancelled.
    func execute(
        image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> [DetectedIngredient] {
        let availability = recognitionService.availability
        guard availability.canScan else {
            throw IngredientRecognitionError.recognitionUnavailable(availability)
        }

        let result = try await recognitionService.recognizeIngredients(from: image, orientation: orientation)
        try Task.checkCancellation()

        let detections = normalizer.normalize(result)
        guard !detections.isEmpty else { return [] }

        return try await markingPantryMembership(of: detections)
    }

    /// Flags detections the user already has. A pantry read failure isn't
    /// worth losing a whole scan over - the detections are still shown, and
    /// `AddPantryItemUseCase` will still catch any duplicate on insert.
    private func markingPantryMembership(of detections: [DetectedIngredient]) async throws -> [DetectedIngredient] {
        guard let pantryItems = try? await pantryRepository.fetchAll() else {
            return detections
        }
        try Task.checkCancellation()

        return detections.map { detection in
            let isAlreadyInPantry = pantryItems.contains { $0.ingredient.matches(name: detection.name) }
            return detection.markingAlreadyInPantry(isAlreadyInPantry)
        }
    }
}
