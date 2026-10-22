//
//  ScanReceiptUseCaseCacheTests.swift
//  FridgeFitTests
//

import CoreGraphics
import ImageIO
import UIKit
import XCTest
@testable import FridgeFit

/// The cache's contract with the recognition pipeline.
///
/// The questions here are all variations on one: can a replay ever be
/// mistaken for, or substituted for, a real Apple Intelligence run?
@MainActor
final class ScanReceiptUseCaseCacheTests: XCTestCase {

    private func makeUseCase(
        recognizer: MockReceiptTextRecognizer,
        interpreter: MockReceiptIngredientInterpreter = MockReceiptIngredientInterpreter(),
        repository: PantryRepository = InMemoryPantryRepository(),
        cache: ReceiptRecognitionCacheStoring? = nil
    ) -> ScanReceiptUseCase {
        ScanReceiptUseCase(
            textRecognizer: recognizer,
            interpreter: interpreter,
            pantryRepository: repository,
            recognitionCache: cache
        )
    }

    /// Receipt text that the real parser and normaliser will turn into
    /// pantry candidates, so these tests exercise the whole chain.
    private var colesLines: [String] {
        [
            "Coles Supermarkets Australia Pty Ltd",
            "COLS TOMATOES 1KG       3.60",
            "FREE RANGE EGGS 12PK    5.20",
            "FULL CREAM MILK 2L      3.00",
            "Total for 3 items:     11.80"
        ]
    }

    private func interpreterReturningColes() -> MockReceiptIngredientInterpreter {
        MockReceiptIngredientInterpreter(result: .success(ReceiptInterpretationResult(items: [
            RawInterpretedReceiptItem(
                originalText: "COLS TOMATOES 1KG",
                displayName: "Tomatoes",
                canonicalName: "tomato",
                classification: "ingredient",
                category: "Produce",
                quantity: 1,
                unit: "kg"
            ),
            RawInterpretedReceiptItem(
                originalText: "FREE RANGE EGGS 12PK",
                displayName: "Free Range Eggs",
                canonicalName: "egg",
                classification: "ingredient",
                category: "Dairy",
                quantity: 12,
                unit: "pcs"
            ),
            RawInterpretedReceiptItem(
                originalText: "FULL CREAM MILK 2L",
                displayName: "Full Cream Milk",
                canonicalName: "milk",
                classification: "ingredient",
                category: "Dairy",
                quantity: 2,
                unit: "L"
            )
        ])))
    }

    private var demoImage: CGImage { ReceiptImageFixtures.demoLikeReceipt() }
    private var otherImage: CGImage { ReceiptImageFixtures.visuallySimilarDifferentReceipt() }

    private func cacheContainingDemoResult() async throws -> (InMemoryReceiptRecognitionCacheStore, ReceiptScanOutcome) {
        let cache = InMemoryReceiptRecognitionCacheStore()
        let outcome = try await makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: interpreterReturningColes()
        ).execute(image: demoImage)

        let fingerprint = try XCTUnwrap(ReceiptImageFingerprint.make(of: demoImage))
        try cache.save(ReceiptRecognitionCacheEntry(
            fingerprint: fingerprint,
            outcome: outcome,
            preparedAt: Date()
        ))
        return (cache, outcome)
    }

    // MARK: - First run uses the real pipeline

    func testAnUncachedImageRunsTheExistingPipeline() async throws {
        let recognizer = MockReceiptTextRecognizer(lines: colesLines)
        let interpreter = interpreterReturningColes()
        let cache = InMemoryReceiptRecognitionCacheStore()

        let outcome = try await makeUseCase(recognizer: recognizer, interpreter: interpreter, cache: cache)
            .execute(image: demoImage)

        XCTAssertEqual(recognizer.recognizeCallCount, 1, "OCR must still run on a miss.")
        XCTAssertEqual(interpreter.interpretCallCount, 1, "The model must still run on a miss.")
        XCTAssertEqual(outcome.source, .appleIntelligence)
        XCTAssertEqual(outcome.pantryCandidates.count, 3)
    }

    /// A scan never writes to the cache. Only the DEBUG preparation flow
    /// does, after a human has looked at the result.
    func testANormalScanDoesNotPopulateTheCache() async throws {
        let cache = InMemoryReceiptRecognitionCacheStore()
        _ = try await makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: interpreterReturningColes(),
            cache: cache
        ).execute(image: demoImage)

        XCTAssertTrue(cache.stored.isEmpty, "An unverified result must never become a cache entry.")
    }

    // MARK: - Cache hits

    func testACacheHitDoesNotInvokeTheModelAgain() async throws {
        let (cache, _) = try await cacheContainingDemoResult()
        let recognizer = MockReceiptTextRecognizer(lines: colesLines)
        let interpreter = interpreterReturningColes()

        let outcome = try await makeUseCase(recognizer: recognizer, interpreter: interpreter, cache: cache)
            .execute(image: demoImage)

        XCTAssertEqual(interpreter.interpretCallCount, 0, "The whole point: no model invocation on a hit.")
        XCTAssertEqual(recognizer.recognizeCallCount, 0, "OCR is skipped too - it is wasted work on a hit.")
        XCTAssertEqual(outcome.source, .verifiedCache)
    }

    func testACacheHitPreservesTheStructuredOutput() async throws {
        let (cache, original) = try await cacheContainingDemoResult()

        let replayed = try await makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: interpreterReturningColes(),
            cache: cache
        ).execute(image: demoImage)

        XCTAssertEqual(
            replayed.pantryCandidates.map(\.displayName),
            original.pantryCandidates.map(\.displayName)
        )
        XCTAssertEqual(
            replayed.pantryCandidates.map(\.quantity),
            original.pantryCandidates.map(\.quantity),
            "Quantities - including absent ones - must replay exactly."
        )
        XCTAssertEqual(
            replayed.pantryCandidates.map(\.canonicalName),
            original.pantryCandidates.map(\.canonicalName)
        )
    }

    /// Pantry membership is recomputed against the live pantry, so a replay
    /// cannot offer to add something the user already has.
    func testACacheHitRecomputesPantryMembershipFromTheLivePantry() async throws {
        let (cache, _) = try await cacheContainingDemoResult()

        let pantry = InMemoryPantryRepository(seedItems: [
            PantryItem(
                ingredient: Ingredient(name: "Full Cream Milk", category: .dairy),
                quantity: 1,
                unit: .liters
            )
        ])

        let replayed = try await makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: interpreterReturningColes(),
            repository: pantry,
            cache: cache
        ).execute(image: demoImage)

        let milk = try XCTUnwrap(replayed.pantryCandidates.first { $0.displayName.contains("Milk") })
        XCTAssertTrue(milk.isAlreadyInPantry, "A replay must see the pantry as it is now, not as it was.")

        let tomato = try XCTUnwrap(replayed.pantryCandidates.first { $0.displayName.contains("Tomato") })
        XCTAssertFalse(tomato.isAlreadyInPantry)
    }

    func testAReplayedResultIsStillEditableBeforePantryInsertion() async throws {
        let (cache, _) = try await cacheContainingDemoResult()
        let viewModel = ReceiptScannerViewModel(
            textRecognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: interpreterReturningColes(),
            pantryRepository: InMemoryPantryRepository(),
            recognitionCache: cache
        )

        viewModel.selectImage(UIImage(cgImage: demoImage))
        viewModel.scan()
        try await waitForCompletion(of: viewModel)

        let draft = try XCTUnwrap(viewModel.drafts.first)
        viewModel.updateName("Roma Tomatoes", for: draft.id)
        viewModel.updateQuantityText("500", for: draft.id)
        viewModel.updateUnit(.grams, for: draft.id)

        XCTAssertEqual(viewModel.drafts.first?.name, "Roma Tomatoes")
        XCTAssertEqual(viewModel.drafts.first?.quantity, 500)
        XCTAssertEqual(viewModel.drafts.first?.unit, .grams)
    }

    // MARK: - Other receipts are untouched

    func testADifferentReceiptStillGoesToTheModel() async throws {
        let (cache, _) = try await cacheContainingDemoResult()
        let recognizer = MockReceiptTextRecognizer(lines: colesLines)
        let interpreter = interpreterReturningColes()

        let outcome = try await makeUseCase(recognizer: recognizer, interpreter: interpreter, cache: cache)
            .execute(image: otherImage)

        XCTAssertEqual(interpreter.interpretCallCount, 1, "A receipt nobody prepared must be analysed.")
        XCTAssertEqual(outcome.source, .appleIntelligence)
    }

    func testACropOfTheDemoReceiptStillGoesToTheModel() async throws {
        let (cache, _) = try await cacheContainingDemoResult()
        let cropped = try XCTUnwrap(demoImage.cropping(to: CGRect(
            x: 0, y: 0, width: demoImage.width, height: demoImage.height - 4
        )))
        let interpreter = interpreterReturningColes()

        let outcome = try await makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: interpreter,
            cache: cache
        ).execute(image: cropped)

        XCTAssertEqual(interpreter.interpretCallCount, 1)
        XCTAssertEqual(outcome.source, .appleIntelligence)
    }

    /// The demo receipt photographed again is a different picture, and must
    /// not inherit the prepared answer.
    func testASinglePixelDifferenceStillGoesToTheModel() async throws {
        let (cache, _) = try await cacheContainingDemoResult()
        let interpreter = interpreterReturningColes()

        let outcome = try await makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: interpreter,
            cache: cache
        ).execute(image: ReceiptImageFixtures.demoReceiptWithOnePixelChanged())

        XCTAssertEqual(interpreter.interpretCallCount, 1)
        XCTAssertEqual(outcome.source, .appleIntelligence)
    }

    // MARK: - Fallback

    func testAnUnreadableCacheFallsBackToANormalScan() async throws {
        let (cache, _) = try await cacheContainingDemoResult()
        cache.readFailure = true
        let interpreter = interpreterReturningColes()

        let outcome = try await makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: interpreter,
            cache: cache
        ).execute(image: demoImage)

        XCTAssertEqual(interpreter.interpretCallCount, 1, "A broken cache must cost speed, never correctness.")
        XCTAssertEqual(outcome.source, .appleIntelligence)
        XCTAssertEqual(outcome.pantryCandidates.count, 3)
    }

    func testNoCacheAtAllBehavesExactlyAsBefore() async throws {
        let interpreter = interpreterReturningColes()
        let outcome = try await makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: interpreter,
            cache: nil
        ).execute(image: demoImage)

        XCTAssertEqual(interpreter.interpretCallCount, 1)
        XCTAssertEqual(outcome.source, .appleIntelligence)
    }

    /// An entry written by an older pipeline must not be served.
    func testAnIncompatibleEntryFallsBackToTheModel() async throws {
        let cache = InMemoryReceiptRecognitionCacheStore()
        let fresh = try await makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: interpreterReturningColes()
        ).execute(image: demoImage)

        // Written directly, bypassing `save`, to simulate a file left behind
        // by a build with a different pipeline.
        let fingerprint = try XCTUnwrap(ReceiptImageFingerprint.make(of: demoImage))
        cache.insertBypassingValidation(ReceiptRecognitionCacheEntry(
            fingerprint: fingerprint,
            outcome: fresh,
            preparedAt: Date(),
            pipelineVersion: "an-older-pipeline"
        ))

        let interpreter = interpreterReturningColes()
        let outcome = try await makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: interpreter,
            cache: cache
        ).execute(image: demoImage)

        XCTAssertEqual(interpreter.interpretCallCount, 1)
        XCTAssertEqual(outcome.source, .appleIntelligence)
    }

    /// Errors must stay identical to the uncached path.
    func testScanErrorsAreUnchangedWhenACacheIsAttached() async {
        let cache = InMemoryReceiptRecognitionCacheStore()
        let useCase = makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: []),
            interpreter: interpreterReturningColes(),
            cache: cache
        )

        do {
            _ = try await useCase.execute(image: demoImage)
            XCTFail("An empty OCR result should still fail the scan.")
        } catch {
            XCTAssertEqual(error as? ReceiptScanError, .noTextRecognized)
        }
    }

    func testAnUnavailableModelStillFailsOnAMiss() async {
        let cache = InMemoryReceiptRecognitionCacheStore()
        let useCase = makeUseCase(
            recognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: MockReceiptIngredientInterpreter(availability: .appleIntelligenceNotEnabled),
            cache: cache
        )

        do {
            _ = try await useCase.execute(image: demoImage)
            XCTFail("An unavailable model should still fail an uncached scan.")
        } catch {
            XCTAssertEqual(error as? ReceiptScanError, .scanUnavailable(.appleIntelligenceNotEnabled))
        }
    }

    // MARK: - Helpers

    private func waitForCompletion(
        of viewModel: ReceiptScannerViewModel,
        timeout: Duration = .seconds(5)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if case .completed = viewModel.scanState { return }
            if case .failed(let message) = viewModel.scanState {
                XCTFail("Scan failed: \(message)")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for the scan to finish.")
    }
}
