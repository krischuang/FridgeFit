//
//  FoodRecognitionService.swift
//  FridgeFit
//

import Foundation
import UIKit

/// One thing a recogniser thinks it saw in a snapshot.
///
/// Intentionally *not* an `Ingredient` or a `PantryItem`. Recognition output
/// is a guess, and the pantry only ever gains items the user confirmed - the
/// same boundary `ReceiptItemDraft` draws for receipt scanning.
nonisolated struct RecognizedFoodItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    /// 0...1. Presentational only; nothing branches on a threshold yet.
    let confidence: Double

    init(id: UUID = UUID(), name: String, confidence: Double) {
        self.id = id
        self.name = name
        self.confidence = confidence
    }
}

nonisolated struct FoodRecognitionResult: Equatable, Sendable {
    let items: [RecognizedFoodItem]
    /// True when the result came from `MockFoodRecognitionService`. The UI
    /// shows a "Mock data" badge off this flag so a demo can never be
    /// mistaken for real recognition.
    let isMockData: Bool
}

/// The extension point where a remote snapshot would meet food recognition.
///
/// This prototype's job is to prove a fridge photo taken on one iPhone can
/// reach the main app on another. Recognition itself is deliberately left
/// unimplemented: FridgeFit's existing on-device intelligence
/// (`AppleReceiptIngredientInterpreter`) reads *receipt text* via Vision, not
/// food in a photo, so reusing it here would mean running OCR over a picture
/// of vegetables and inventing an interpretation of whatever it found. That
/// would be a fake result wearing a real pipeline's clothes.
///
/// So there are two conformances and no third:
/// - `UnimplementedFoodRecognitionService` - the default. Returns nothing and
///   says why.
/// - `MockFoodRecognitionService` - opt-in, for exercising the snapshot UI.
///   Everything it returns is flagged `isMockData`.
///
/// Neither writes to the pantry. `RemoteCameraViewModel` holds the snapshot
/// in memory and offers a save-to-Photos button; wiring recognition output
/// into `AddDetectedIngredientsUseCase` is the next step, not this one.
nonisolated protocol FoodRecognitionService: AnyObject, Sendable {
    /// Whether this service can actually recognise anything right now.
    var isAvailable: Bool { get }

    /// Why recognition is unavailable, for display. `nil` when available.
    var unavailableExplanation: String? { get }

    func recognizeFood(in image: UIImage) async throws -> FoodRecognitionResult
}
