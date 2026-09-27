//
//  DetectIngredientsUseCaseTests.swift
//  FridgeFitTests
//

import CoreGraphics
import XCTest
@testable import FridgeFit

@MainActor
final class DetectIngredientsUseCaseTests: XCTestCase {
    private func makeUseCase(
        service: MockIngredientRecognitionService,
        seedItems: [PantryItem] = []
    ) -> DetectIngredientsUseCase {
        DetectIngredientsUseCase(
            recognitionService: service,
            pantryRepository: InMemoryPantryRepository(seedItems: seedItems)
        )
    }

    func test_detectIngredients_returnsNormalizedDetections() async throws {
        let service = MockIngredientRecognitionService(result: .success(.sampleFridge))
        let useCase = makeUseCase(service: service)

        let detections = try await useCase.execute(image: TestImage.make())

        XCTAssertEqual(detections.map(\.name), ["Milk", "Eggs", "Tomato", "Chicken"])
        XCTAssertEqual(detections.map(\.confidence), [.high, .high, .medium, .medium])
        XCTAssertEqual(service.recognizeCallCount, 1)
    }

    func test_detectIngredients_returnsEmpty_whenNothingDetected() async throws {
        let useCase = makeUseCase(service: MockIngredientRecognitionService(result: .success(.empty)))

        let detections = try await useCase.execute(image: TestImage.make())

        XCTAssertTrue(detections.isEmpty)
    }

    /// The pantry decides what's already there, not the model.
    func test_detectIngredients_flagsDetectionsAlreadyInPantry() async throws {
        let service = MockIngredientRecognitionService(result: .success(.sampleFridge))
        let useCase = makeUseCase(
            service: service,
            seedItems: [
                PantryItem(ingredient: Ingredient(name: "milk", category: .dairy), quantity: 1, unit: .liters)
            ]
        )

        let detections = try await useCase.execute(image: TestImage.make())

        let milk = try XCTUnwrap(detections.first { $0.name == "Milk" })
        XCTAssertTrue(milk.isAlreadyInPantry, "Case-insensitive pantry match should be flagged")
        XCTAssertFalse(try XCTUnwrap(detections.first { $0.name == "Tomato" }).isAlreadyInPantry)
    }

    func test_detectIngredients_throwsUnavailable_whenModelUnavailable() async {
        let service = MockIngredientRecognitionService(availability: .appleIntelligenceNotEnabled)
        let useCase = makeUseCase(service: service)

        do {
            _ = try await useCase.execute(image: TestImage.make())
            XCTFail("Expected recognitionUnavailable")
        } catch let error as IngredientRecognitionError {
            XCTAssertEqual(error, .recognitionUnavailable(.appleIntelligenceNotEnabled))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(service.recognizeCallCount, 0, "Unavailable model must not be asked to recognise anything")
    }

    func test_detectIngredients_propagatesServiceFailure() async {
        let service = MockIngredientRecognitionService(result: .failure(IngredientRecognitionError.recognitionFailed))
        let useCase = makeUseCase(service: service)

        do {
            _ = try await useCase.execute(image: TestImage.make())
            XCTFail("Expected recognitionFailed")
        } catch let error as IngredientRecognitionError {
            XCTAssertEqual(error, .recognitionFailed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
