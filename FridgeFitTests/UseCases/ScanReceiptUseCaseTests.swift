//
//  ScanReceiptUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class ScanReceiptUseCaseTests: XCTestCase {
    private func makeUseCase(
        recognizer: MockReceiptTextRecognizer,
        interpreter: MockReceiptIngredientInterpreter = MockReceiptIngredientInterpreter(),
        repository: PantryRepository = InMemoryPantryRepository()
    ) -> ScanReceiptUseCase {
        ScanReceiptUseCase(
            textRecognizer: recognizer,
            interpreter: interpreter,
            pantryRepository: repository
        )
    }

    /// An interpreter that answers correctly for whatever lines it is
    /// given, so the test exercises the real parser and normalizer.
    private func interpreterForSampleReceipt() -> MockReceiptIngredientInterpreter {
        let interpreter = MockReceiptIngredientInterpreter()
        let lines = ReceiptLineParser().parse(SampleReceipt.recognizedText)
        interpreter.result = .success(SampleReceipt.interpretation(for: lines))
        return interpreter
    }

    // MARK: - The whole pipeline

    func test_execute_turnsAReceiptPhotoIntoPantryCandidates() async throws {
        let useCase = makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: SampleReceipt.ocrLines),
            interpreter: interpreterForSampleReceipt()
        )

        let outcome = try await useCase.execute(image: TestImage.make())

        XCTAssertEqual(
            outcome.pantryCandidates.map(\.displayName),
            ["Banana", "Chicken Breast", "Cup Mushrooms", "Red Capsicum", "Atlantic Salmon"]
        )
        XCTAssertEqual(outcome.excluded.map(\.displayName), ["Woolworths", "Coca Cola", "Dishwashing Tablets", "Paper Towel"])
    }

    func test_execute_extractsQuantitiesOnlyWhereTheReceiptStatesThem() async throws {
        let useCase = makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: SampleReceipt.ocrLines),
            interpreter: interpreterForSampleReceipt()
        )

        let outcome = try await useCase.execute(image: TestImage.make())
        let byCanonical = Dictionary(
            uniqueKeysWithValues: outcome.pantryCandidates.map { ($0.canonicalName, $0) }
        )

        // Stated on the line, so read from it.
        XCTAssertEqual(byCanonical["chicken"]?.quantity, ReceiptQuantity(value: 500, unit: .grams))
        XCTAssertEqual(byCanonical["mushroom"]?.quantity, ReceiptQuantity(value: 200, unit: .grams))

        // Not stated anywhere on the line, so left unknown rather than
        // defaulted to a number the receipt never mentioned.
        XCTAssertNil(try XCTUnwrap(byCanonical["bell_pepper"]).quantity, "CAPS RED states no amount")
        XCTAssertNil(try XCTUnwrap(byCanonical["salmon"]).quantity, "SALMON ATL states no amount")
        XCTAssertNil(try XCTUnwrap(byCanonical["banana"]).quantity, "BANANA CAVENDISH states no amount")
    }

    /// The interpreter must only ever be handed text, and only the cleaned
    /// product lines - never receipt furniture.
    func test_execute_sendsOnlyCleanedProductLinesToTheInterpreter() async throws {
        let interpreter = interpreterForSampleReceipt()
        let useCase = makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: SampleReceipt.ocrLines),
            interpreter: interpreter
        )

        _ = try await useCase.execute(image: TestImage.make())

        XCTAssertEqual(
            interpreter.lastLineItems.map(\.productDescription),
            SampleReceipt.expectedProductDescriptions
        )
        let sent = interpreter.lastLineItems.map(\.productDescription).joined(separator: " ")
        XCTAssertFalse(sent.contains("SUBTOTAL"))
        XCTAssertFalse(sent.contains("EFTPOS"))
        XCTAssertFalse(sent.contains("GST"))
    }

    // MARK: - Pantry reconciliation

    func test_execute_flagsCandidatesAlreadyInThePantry() async throws {
        let repository = InMemoryPantryRepository(seedItems: [
            PantryItem(ingredient: Ingredient(name: "Banana", category: .produce), quantity: 3, unit: .pieces)
        ])
        let useCase = makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: SampleReceipt.ocrLines),
            interpreter: interpreterForSampleReceipt(),
            repository: repository
        )

        let outcome = try await useCase.execute(image: TestImage.make())
        let banana = outcome.pantryCandidates.first { $0.canonicalName == "banana" }

        XCTAssertEqual(banana?.isAlreadyInPantry, true)
        XCTAssertEqual(outcome.pantryCandidates.filter(\.isAlreadyInPantry).count, 1)
    }

    // MARK: - The three "nothing found" outcomes

    func test_execute_throwsNoTextRecognized_whenOCRFindsNothing() async {
        let useCase = makeUseCase(recognizer: MockReceiptTextRecognizer(lines: []))

        await assert(useCase, throws: .noTextRecognized)
    }

    func test_execute_throwsNoProductLines_whenEveryLineIsReceiptFurniture() async {
        let useCase = makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: ["SUBTOTAL 10.00", "GST 1.00", "EFTPOS 11.00"])
        )

        await assert(useCase, throws: .noProductLinesFound)
    }

    func test_execute_throwsNoFoodItems_whenNothingOnTheReceiptIsAnIngredient() async {
        let interpreter = MockReceiptIngredientInterpreter(result: .success(
            ReceiptInterpretationResult(items: [
                SampleReceipt.item("DISHWASH TABLETS", "Dishwashing Tablets", "dishwashing tablet", .household, .other)
            ])
        ))
        let useCase = makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: ["DISHWASH TABLETS 12.00"]),
            interpreter: interpreter
        )

        await assert(useCase, throws: .noFoodItemsFound)
    }

    // MARK: - Availability and failure

    func test_execute_throwsWhenAppleIntelligenceIsUnavailable() async {
        let useCase = makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: SampleReceipt.ocrLines),
            interpreter: MockReceiptIngredientInterpreter(availability: .appleIntelligenceNotEnabled)
        )

        await assert(useCase, throws: .scanUnavailable(.appleIntelligenceNotEnabled))
    }

    /// Availability is checked before any work, so an unavailable model
    /// doesn't run OCR over the photo for nothing.
    func test_execute_doesNotRunOCR_whenScanningIsUnavailable() async {
        let recognizer = MockReceiptTextRecognizer(lines: SampleReceipt.ocrLines)
        let useCase = makeUseCase(
            recognizer: recognizer,
            interpreter: MockReceiptIngredientInterpreter(availability: .deviceNotSupported)
        )

        _ = try? await useCase.execute(image: TestImage.make())

        XCTAssertEqual(recognizer.recognizeCallCount, 0)
    }

    func test_execute_propagatesOCRFailure() async {
        let useCase = makeUseCase(
            recognizer: MockReceiptTextRecognizer(result: .failure(ReceiptScanError.invalidImage))
        )

        await assert(useCase, throws: .invalidImage)
    }

    func test_execute_propagatesInterpretationFailure() async {
        let useCase = makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: SampleReceipt.ocrLines),
            interpreter: MockReceiptIngredientInterpreter(result: .failure(ReceiptScanError.modelBusy))
        )

        await assert(useCase, throws: .modelBusy)
    }

    func test_execute_isCancellable() async throws {
        let useCase = makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: SampleReceipt.ocrLines, delay: .milliseconds(400))
        )

        let task = Task { try await useCase.execute(image: TestImage.make()) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    // MARK: - Helpers

    private func assert(
        _ useCase: ScanReceiptUseCase,
        throws expected: ReceiptScanError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await useCase.execute(image: TestImage.make())
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as ReceiptScanError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error \(error)", file: file, line: line)
        }
    }
}
