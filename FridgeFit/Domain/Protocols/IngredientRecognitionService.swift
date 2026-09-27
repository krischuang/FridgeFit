//
//  IngredientRecognitionService.swift
//  FridgeFit
//

import CoreGraphics
import ImageIO

/// Abstraction over whatever turns a fridge photo into candidate
/// ingredients - Apple's on-device Foundation Model today, something else
/// later.
///
/// Returns untrusted `RawDetectedIngredient`s only. Nothing here may decide
/// what's actually in the pantry, whether an ingredient is a duplicate, or
/// how much of it there is: `DetectIngredientsUseCase` normalizes every
/// detection and checks it against the real pantry first, the same way
/// `SubstitutionService` output goes through validation before the UI sees
/// it.
///
/// Implementations are expected to keep the image on-device.
protocol IngredientRecognitionService {
    /// Whether this provider can run a scan right now, in FridgeFit's terms.
    ///
    /// Read fresh on every access - the user can turn Apple Intelligence on
    /// or off, and the model can finish downloading, while the app is open.
    var availability: IngredientRecognitionAvailability { get }

    /// Identifies candidate ingredients in a fridge photo.
    ///
    /// - Parameters:
    ///   - image: The photo to analyse.
    ///   - orientation: How `image` should be rotated before analysis -
    ///     camera captures are rarely upright.
    /// - Throws: `IngredientRecognitionError`, never a provider-specific
    ///   error type.
    func recognizeIngredients(
        from image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> IngredientDetectionResult
}
