//
//  AppleModelDeadlineTests.swift
//  FridgeFitTests
//
//  The deadlines on the two Foundation Models features that previously had
//  none: receipt interpretation and pantry recipe ideas.
//
//  Both are driven through their injected generation function rather than the
//  real `LanguageModelSession`, which is what makes these deterministic. The
//  fake used for every timeout case parks on a continuation nobody resumes
//  and ignores cancellation - the behaviour `respond` actually exhibits on a
//  device that reports `.available` with no model assets installed, and the
//  only version of "slow" that a structured task-group race fails to escape.
//
//  Neither suite asserts anything about model output. What the model says is
//  covered by `ReceiptItemNormalizerTests` and
//  `SuggestRecipesFromPantryUseCaseTests`, which is where the untrusted-output
//  rules live.
//

import XCTest
@testable import FridgeFit

/// Shared fake generation behaviours.
private enum FakeGeneration {
    /// Never returns, and cannot be cancelled.
    static func hangs() async {
        await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
    }
}

/// A raw interpretation, built at file scope so the `@Sendable` generation
/// fakes can call it without capturing a test case.
private func rawItem(_ name: String) -> RawInterpretedReceiptItem {
    RawInterpretedReceiptItem(
        originalText: name,
        displayName: name,
        canonicalName: name.lowercased(),
        classification: "food",
        category: "other",
        quantity: 0,
        unit: ""
    )
}

// MARK: - Receipt interpretation

final class AppleReceiptInterpreterDeadlineTests: XCTestCase {

    private static let slack: Duration = .seconds(5)

    private func lines(_ count: Int) -> [ReceiptLineItem] {
        (0 ..< count).map { index in
            ReceiptLineItem(
                originalText: "ITEM \(index) 3.50",
                productDescription: "ITEM \(index)",
                price: 3.50,
                order: index
            )
        }
    }

    /// One batch, hanging generation, nothing interpreted: the user must get
    /// a recoverable error rather than an endless spinner.
    func test_interpret_firstBatchHangs_throwsTimeoutRatherThanHanging() async {
        let interpreter = AppleReceiptIngredientInterpreter(
            batchTimeout: .milliseconds(50),
            overallTimeout: .seconds(30),
            interpretPrompt: { _ in
                await FakeGeneration.hangs()
                return []
            }
        )

        let started = ContinuousClock.now
        do {
            _ = try await interpreter.interpretBatches(of: lines(3))
            XCTFail("Expected ReceiptScanError.timeout")
        } catch let error as ReceiptScanError {
            XCTAssertEqual(error, .timeout)
            XCTAssertLessThan(ContinuousClock.now - started, Self.slack)
        } catch {
            XCTFail("Expected ReceiptScanError.timeout, got \(error)")
        }
    }

    /// The timeout message has to point somewhere useful. Manual entry is the
    /// fallback for a receipt the model could not read, and the wording is
    /// what tells the user it exists.
    func test_timeoutError_offersManualEntryAsTheWayOut() {
        let message = ReceiptScanError.timeout.localizedDescription
        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(
            message.lowercased().contains("by hand"),
            "The timeout message must point at manual entry, got: \(message)"
        )
        for leak in ["FoundationModels", "GenerationError", "Optional", "nil"] {
            XCTAssertFalse(message.contains(leak), "Timeout message leaks \"\(leak)\"")
        }
    }

    /// A receipt whose later batches time out keeps the lines that were read.
    /// The review screen shows exactly these and nothing is saved without the
    /// user confirming, so a short list is honest rather than silent.
    func test_interpret_laterBatchHangs_keepsWhatWasAlreadyInterpreted() async throws {
        // 24 lines at a batch size of 12 is two model requests: the first
        // answers, the second hangs.
        let callCount = Counter()
        let interpreter = AppleReceiptIngredientInterpreter(
            batchTimeout: .milliseconds(50),
            overallTimeout: .seconds(30),
            interpretPrompt: { _ in
                if callCount.increment() == 1 {
                    return [rawItem("Milk"), rawItem("Eggs")]
                }
                await FakeGeneration.hangs()
                return []
            }
        )

        let result = try await interpreter.interpretBatches(of: lines(24))

        XCTAssertEqual(result.items.map(\.displayName), ["Milk", "Eggs"])
        XCTAssertEqual(callCount.value, 2, "Both batches should have been attempted")
    }

    /// The whole-receipt budget has to bound the whole receipt, not each
    /// request. Seven batches each finishing just inside a per-batch bound
    /// would otherwise add up to minutes.
    func test_interpret_overallBudgetStopsTheReceipt_notJustOneBatch() async throws {
        let callCount = Counter()
        let interpreter = AppleReceiptIngredientInterpreter(
            // Per batch this is permissive; in total it allows roughly one
            // batch's worth of work.
            batchTimeout: .seconds(10),
            overallTimeout: .milliseconds(150),
            interpretPrompt: { _ in
                _ = callCount.increment()
                try await Task.sleep(for: .milliseconds(120))
                return [rawItem("Item")]
            }
        )

        // 84 lines is seven batches. Unbounded in total, this would run for
        // roughly 840ms; the overall budget must cut it off far sooner.
        let started = ContinuousClock.now
        let result = try await interpreter.interpretBatches(of: lines(84))
        let elapsed = ContinuousClock.now - started

        XCTAssertLessThan(elapsed, .seconds(1), "The overall budget did not bound the receipt")
        XCTAssertLessThan(callCount.value, 7, "The receipt should have stopped before every batch ran")
        XCTAssertFalse(result.items.isEmpty, "Batches that did finish must be kept")
    }

    /// A generation that fails for its own reason is not a timeout.
    func test_interpret_generationFails_surfacesThatFailureNotTimeout() async {
        let interpreter = AppleReceiptIngredientInterpreter(
            batchTimeout: .seconds(30),
            overallTimeout: .seconds(30),
            interpretPrompt: { _ in throw ReceiptScanError.modelBusy }
        )

        do {
            _ = try await interpreter.interpretBatches(of: lines(3))
            XCTFail("Expected modelBusy")
        } catch let error as ReceiptScanError {
            XCTAssertEqual(error, .modelBusy)
        } catch {
            XCTFail("Expected ReceiptScanError, got \(error)")
        }
    }

    /// An unknown framework error must not reach the user as framework text.
    func test_interpret_unknownFailure_becomesInterpretationFailed() async {
        struct Mystery: Error {}
        let interpreter = AppleReceiptIngredientInterpreter(
            batchTimeout: .seconds(30),
            overallTimeout: .seconds(30),
            interpretPrompt: { _ in throw Mystery() }
        )

        do {
            _ = try await interpreter.interpretBatches(of: lines(3))
            XCTFail("Expected interpretationFailed")
        } catch let error as ReceiptScanError {
            XCTAssertEqual(error, .interpretationFailed)
        } catch {
            XCTFail("Expected ReceiptScanError, got \(error)")
        }
    }

    /// Cancelling a scan must end it as cancellation - not as a timeout, and
    /// not after the deadline - even when the generation ignores cancellation.
    func test_interpret_cancelled_throwsCancellationPromptly() async throws {
        let interpreter = AppleReceiptIngredientInterpreter(
            batchTimeout: .seconds(120),
            overallTimeout: .seconds(120),
            interpretPrompt: { _ in
                await FakeGeneration.hangs()
                return []
            }
        )

        let started = ContinuousClock.now
        let lineItems = lines(3)
        let task = Task { try await interpreter.interpretBatches(of: lineItems) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertLessThan(ContinuousClock.now - started, Self.slack)
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    /// No lines means no model call at all.
    func test_interpret_noLines_returnsEmptyWithoutGenerating() async throws {
        let callCount = Counter()
        let interpreter = AppleReceiptIngredientInterpreter(
            interpretPrompt: { _ in
                _ = callCount.increment()
                return []
            }
        )

        let result = try await interpreter.interpretBatches(of: [])

        XCTAssertEqual(result, .empty)
        XCTAssertEqual(callCount.value, 0)
    }

    /// The shipped bounds have to be consistent with each other, or the
    /// per-batch bound would be the only one that ever applied.
    func test_shippedDeadlines_areOrderedAndFinite() {
        XCTAssertGreaterThan(AppleReceiptIngredientInterpreter.batchTimeout, .zero)
        XCTAssertGreaterThanOrEqual(
            AppleReceiptIngredientInterpreter.overallTimeout,
            AppleReceiptIngredientInterpreter.batchTimeout,
            "An overall budget below one batch's bound makes the batch bound unreachable"
        )
    }
}

// MARK: - Recipe suggestions

final class AppleRecipeSuggestionDeadlineTests: XCTestCase {

    private static let slack: Duration = .seconds(5)

    private func pantry() -> [PantryItem] {
        [PantryItem(ingredient: Ingredient(name: "egg", category: .other), quantity: 2, unit: .pieces)]
    }

    func test_suggestRecipes_generationHangs_throwsTimeoutRatherThanHanging() async {
        let service = AppleRecipeSuggestionService(
            timeout: .milliseconds(50),
            generate: { _ in
                await FakeGeneration.hangs()
                return []
            }
        )

        let started = ContinuousClock.now
        do {
            _ = try await service.generateSuggestions(from: pantry())
            XCTFail("Expected RecipeSuggestionError.timeout")
        } catch let error as RecipeSuggestionError {
            XCTAssertEqual(error, .timeout)
            XCTAssertLessThan(ContinuousClock.now - started, Self.slack)
        } catch {
            XCTFail("Expected RecipeSuggestionError.timeout, got \(error)")
        }
    }

    /// Recipe ideas are an enhancement, not the Recipes tab. The timeout
    /// wording has to say so, because browsing still works.
    func test_timeoutError_pointsAtTheCatalogueThatStillWorks() {
        let message = RecipeSuggestionError.timeout.localizedDescription
        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(
            message.lowercased().contains("catalogue") || message.lowercased().contains("browse"),
            "The timeout message must point at the non-AI fallback, got: \(message)"
        )
        for leak in ["FoundationModels", "GenerationError", "Optional", "nil"] {
            XCTAssertFalse(message.contains(leak), "Timeout message leaks \"\(leak)\"")
        }
    }

    func test_suggestRecipes_generationSucceeds_returnsItsSuggestions() async throws {
        let service = AppleRecipeSuggestionService(
            timeout: .seconds(30),
            generate: { _ in
                [RawRecipeSuggestion(
                    name: "Scrambled eggs",
                    requiredIngredients: ["egg", "butter"],
                    shortInstructions: "Beat and cook.",
                    estimatedPreparationMinutes: 8
                )]
            }
        )

        let suggestions = try await service.generateSuggestions(from: pantry())

        XCTAssertEqual(suggestions.map(\.name), ["Scrambled eggs"])
    }

    func test_suggestRecipes_generationFails_surfacesThatFailureNotTimeout() async {
        let service = AppleRecipeSuggestionService(
            timeout: .seconds(30),
            generate: { _ in throw RecipeSuggestionError.modelBusy }
        )

        do {
            _ = try await service.generateSuggestions(from: pantry())
            XCTFail("Expected modelBusy")
        } catch let error as RecipeSuggestionError {
            XCTAssertEqual(error, .modelBusy)
        } catch {
            XCTFail("Expected RecipeSuggestionError, got \(error)")
        }
    }

    func test_suggestRecipes_emptyPantry_doesNotGenerate() async throws {
        let callCount = Counter()
        let service = AppleRecipeSuggestionService(
            generate: { _ in
                _ = callCount.increment()
                return []
            }
        )

        let suggestions = try await service.generateSuggestions(from: [])

        XCTAssertTrue(suggestions.isEmpty)
        XCTAssertEqual(callCount.value, 0, "An empty pantry must not spend a generation")
    }

    func test_suggestRecipes_cancelled_throwsCancellationPromptly() async throws {
        let service = AppleRecipeSuggestionService(
            timeout: .seconds(120),
            generate: { _ in
                await FakeGeneration.hangs()
                return []
            }
        )

        let started = ContinuousClock.now
        let items = pantry()
        let task = Task { try await service.generateSuggestions(from: items) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertLessThan(ContinuousClock.now - started, Self.slack)
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }
}

// MARK: - Substitutions, through the shared primitive

final class AppleSubstitutionDeadlineTests: XCTestCase {

    /// `AppleSubstitutionService.withTimeout` kept its signature when its
    /// body moved onto `BoundedWork`. The existing suite covers it
    /// with a `Task.sleep` operation, which the old task-group race also
    /// passed. This is the case that one could not survive.
    func test_withTimeout_operationIgnoresCancellation_stillThrowsTimeoutPromptly() async {
        let started = ContinuousClock.now
        do {
            let _: Int = try await AppleSubstitutionService.withTimeout(.milliseconds(50)) {
                await FakeGeneration.hangs()
                return 1
            }
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? SubstitutionServiceError, .timeout)
            XCTAssertLessThan(
                ContinuousClock.now - started,
                .seconds(5),
                "The substitution bound must not wait for an uncancellable generation"
            )
        }
    }
}

// MARK: - Test helpers

/// A call counter usable from a `@Sendable` closure.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    /// Increments and returns the new value.
    @discardableResult
    func increment() -> Int {
        lock.lock()
        count += 1
        let updated = count
        lock.unlock()
        return updated
    }
}
