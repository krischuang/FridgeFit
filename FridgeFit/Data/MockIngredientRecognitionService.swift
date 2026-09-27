//
//  MockIngredientRecognitionService.swift
//  FridgeFit
//

import CoreGraphics
import Foundation
import ImageIO

/// Test double / preview double for `IngredientRecognitionService`.
///
/// Returns whatever `result` is set to and reports whatever `availability`
/// is set to, so the whole scan flow - success, empty detection, failure,
/// unavailable, cancellation - can be driven from a unit test with no
/// Apple Intelligence device, no Vision, no network and no camera.
///
/// `delay` exists for the cancellation tests: it holds the call open long
/// enough for a test to cancel it, and respects cancellation while waiting.
final class MockIngredientRecognitionService: IngredientRecognitionService {
    var result: Result<IngredientDetectionResult, Error>
    var availability: IngredientRecognitionAvailability
    var delay: Duration?

    private(set) var recognizeCallCount = 0

    init(
        result: Result<IngredientDetectionResult, Error> = .success(.empty),
        availability: IngredientRecognitionAvailability = .available,
        delay: Duration? = nil
    ) {
        self.result = result
        self.availability = availability
        self.delay = delay
    }

    func recognizeIngredients(
        from image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> IngredientDetectionResult {
        recognizeCallCount += 1

        if let delay {
            try await Task.sleep(for: delay)
        }
        try Task.checkCancellation()

        return try result.get()
    }
}

extension IngredientDetectionResult {
    /// Convenience for tests and previews: a plausible scan of a stocked
    /// fridge.
    static let sampleFridge = IngredientDetectionResult(ingredients: [
        RawDetectedIngredient(name: "milk", category: IngredientCategory.dairy.rawValue, visibleCount: 1, confidence: "high"),
        RawDetectedIngredient(name: "eggs", category: IngredientCategory.other.rawValue, visibleCount: 6, confidence: "high"),
        RawDetectedIngredient(name: "tomato", category: IngredientCategory.produce.rawValue, visibleCount: 3, confidence: "medium"),
        RawDetectedIngredient(name: "chicken", category: IngredientCategory.meat.rawValue, visibleCount: 0, confidence: "medium")
    ])
}
