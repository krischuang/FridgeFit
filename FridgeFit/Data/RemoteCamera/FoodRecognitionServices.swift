//
//  FoodRecognitionServices.swift
//  FridgeFit
//

import Foundation
import UIKit

/// The default `FoodRecognitionService`: recognises nothing, and says so.
///
/// This is the honest state of the prototype. FridgeFit's on-device
/// intelligence reads receipt *text*; there is no component here that
/// identifies food in a photograph, and pretending otherwise by running the
/// receipt interpreter over a picture of a fridge shelf would produce
/// confident nonsense.
///
/// The snapshot arriving on the controller is the thing this prototype set
/// out to prove. Recognition is the next piece of work, and this type is
/// where it plugs in.
nonisolated final class UnimplementedFoodRecognitionService: FoodRecognitionService {
    var isAvailable: Bool { false }

    var unavailableExplanation: String? {
        """
        Food recognition isn't wired up yet. This prototype proves the remote \
        snapshot reaches the app - identifying what's in it comes next.
        """
    }

    func recognizeFood(in image: UIImage) async throws -> FoodRecognitionResult {
        FoodRecognitionResult(items: [], isMockData: false)
    }
}

/// Fixed, obviously-fake recognition output for exercising the snapshot UI.
///
/// Every result is flagged `isMockData`, and `RemoteCameraView` shows a
/// "Mock data" badge off that flag, so a screenshot of this can't be
/// mistaken for working recognition. Nothing it returns reaches the pantry -
/// `RemoteCameraViewModel` never calls `AddDetectedIngredientsUseCase`.
///
/// Not wired into the app by default; `RemoteCameraViewModel` takes
/// `UnimplementedFoodRecognitionService` unless a caller passes this in.
nonisolated final class MockFoodRecognitionService: FoodRecognitionService {
    var isAvailable: Bool { true }
    var unavailableExplanation: String? { nil }

    /// Deliberately bland pantry staples. The names are not derived from the
    /// image in any way - they are the same every time.
    private static let fixedItems = [
        RecognizedFoodItem(name: "Mock Milk", confidence: 0.92),
        RecognizedFoodItem(name: "Mock Eggs", confidence: 0.88),
        RecognizedFoodItem(name: "Mock Spinach", confidence: 0.71),
    ]

    func recognizeFood(in image: UIImage) async throws -> FoodRecognitionResult {
        FoodRecognitionResult(items: Self.fixedItems, isMockData: true)
    }
}
