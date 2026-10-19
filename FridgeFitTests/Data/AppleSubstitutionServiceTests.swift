//
//  AppleSubstitutionServiceTests.swift
//  FridgeFitTests
//
//  Exercises everything about the on-device substitution provider that can
//  be checked without an Apple Intelligence device.
//
//  ## What is and isn't covered here
//
//  A real generation can't run in this suite, so these tests never assert
//  on model output. What they do cover is every piece of logic around the
//  generation, which is where the behaviour the user notices lives:
//
//  - `GenerationError` mapping, for every case the SDK defines
//  - the timeout race and cancellation, driven through the generic helper
//  - the unavailable path, where the device allows it to be reached
//
//  ## The simulator claims a model it doesn't have
//
//  Worth knowing before reading the skips below: the iOS 26.1 simulator
//  reports `availability == .available`, but has no model assets, and a
//  `respond` call there never returns. So the simulator takes neither the
//  "available and working" path nor the "unavailable" path - it takes a
//  third one, where only the timeout gets the user out. That is what
//  `test_withTimeout_operationOverruns_throwsTimeout` stands in for.
//
//  It also means the unavailable-path test *skips* on the simulator rather
//  than covering it. The behaviour the user sees in that state is covered
//  without a device by `SubstitutionViewModelTests` and
//  `GetIngredientSubstitutionsUseCaseTests` through `MockSubstitutionService`.
//
//  Mapping from generated output onto `RawSubstitutionSuggestion` is in
//  `GeneratedSubstitutionMappingTests`; prompt wording is in
//  `SubstitutionPromptBuilderTests`.
//

import FoundationModels
import OSLog
import XCTest
@testable import FridgeFit

final class AppleSubstitutionServiceTests: XCTestCase {
    private func sampleRequest() -> SubstitutionRequest {
        SubstitutionRequest(
            recipeID: UUID(),
            recipeTitle: "Creamy Pasta",
            targetIngredientName: "Cream",
            requiredQuantity: 200,
            requiredUnit: .milliliters,
            role: .essential,
            pantryIngredients: [],
            feasibilityStatus: .notMakeable
        )
    }

    // MARK: - Availability

    /// Asserting the *consequence* rather than a specific reason, so this
    /// stays honest on whatever machine runs it. Skips where the model
    /// reports itself available - including the simulator, which reports
    /// available without having any assets.
    func test_suggestSubstitutions_whenModelUnavailable_throwsSubstitutionUnavailable_withoutFabricating() async throws {
        let service = AppleSubstitutionService()

        guard !service.availability.canScan else {
            throw XCTSkip("Model reports itself available here, so the unavailable path can't be exercised.")
        }

        do {
            let suggestions = try await service.suggestSubstitutions(for: sampleRequest())
            XCTFail("Expected substitutionUnavailable, got \(suggestions.count) suggestion(s)")
        } catch let error as SubstitutionServiceError {
            guard case .substitutionUnavailable(let availability) = error else {
                return XCTFail("Expected substitutionUnavailable, got \(error)")
            }
            XCTAssertFalse(availability.canScan)
            // The reason has to reach the user, not a generic failure.
            XCTAssertNotNil(error.errorDescription)
        } catch {
            XCTFail("Expected SubstitutionServiceError, got \(error)")
        }
    }

    func test_unavailableError_explanation_isSubstitutionSpecific_notPantryAdvice() {
        // The shared `AppleIntelligenceAvailability` copy tells the user to
        // "add ingredients to your pantry by hand", which is the wrong
        // advice for a cook asking what to use instead of cream.
        for availability in [
            AppleIntelligenceAvailability.appleIntelligenceNotEnabled,
            .deviceNotSupported,
            .modelNotReady,
            .unavailableForUnknownReason,
        ] {
            let message = SubstitutionServiceError.substitutionUnavailable(availability).localizedDescription
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(
                message.contains("add ingredients to your pantry by hand"),
                "Substitutions reused the shared pantry wording for \(availability)"
            )
        }
    }

    // MARK: - Generation error mapping

    private func context(_ description: String = "test") -> LanguageModelSession.GenerationError.Context {
        LanguageModelSession.GenerationError.Context(debugDescription: description)
    }

    func test_mapped_rateLimitedAndConcurrentRequests_becomeModelBusy() {
        XCTAssertEqual(AppleSubstitutionService.mapped(.rateLimited(context())), .modelBusy)
        XCTAssertEqual(AppleSubstitutionService.mapped(.concurrentRequests(context())), .modelBusy)
    }

    func test_mapped_guardrailViolation_becomesRequestNotAllowed() {
        XCTAssertEqual(AppleSubstitutionService.mapped(.guardrailViolation(context())), .requestNotAllowed)
    }

    func test_mapped_refusal_becomesRequestNotAllowed() {
        let refusal = LanguageModelSession.GenerationError.Refusal(transcriptEntries: [])
        XCTAssertEqual(AppleSubstitutionService.mapped(.refusal(refusal, context())), .requestNotAllowed)
    }

    /// The model was available when checked and isn't now. The assets state
    /// is the honest explanation, and it's retryable - a generic failure
    /// would tell the user to retry something that can't yet work.
    func test_mapped_assetsUnavailable_becomesUnavailableWithModelNotReady() {
        XCTAssertEqual(
            AppleSubstitutionService.mapped(.assetsUnavailable(context())),
            .substitutionUnavailable(.modelNotReady)
        )
    }

    func test_mapped_schemaAndContextFailures_becomeSuggestionFailed() {
        XCTAssertEqual(AppleSubstitutionService.mapped(.exceededContextWindowSize(context())), .suggestionFailed)
        XCTAssertEqual(AppleSubstitutionService.mapped(.unsupportedGuide(context())), .suggestionFailed)
        XCTAssertEqual(AppleSubstitutionService.mapped(.decodingFailure(context())), .suggestionFailed)
    }

    /// The on-device model doesn't support every language the app's UI can
    /// run in. That surfaces as an ordinary, retryable failure rather than a
    /// claim that the device is ineligible.
    func test_mapped_unsupportedLanguageOrLocale_becomesSuggestionFailed() {
        XCTAssertEqual(AppleSubstitutionService.mapped(.unsupportedLanguageOrLocale(context())), .suggestionFailed)
    }

    func test_everyMappedError_hasAUserFacingMessage() {
        let errors: [SubstitutionServiceError] = [
            .substitutionUnavailable(.deviceNotSupported),
            .suggestionFailed,
            .requestNotAllowed,
            .modelBusy,
            .timeout,
        ]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty, "\(error) has no message")
            // Framework and provider details must never reach the screen.
            for leak in ["FoundationModels", "GenerationError", "OpenRouter", "nil", "Optional"] {
                XCTAssertFalse(error.localizedDescription.contains(leak), "\(error) leaks \"\(leak)\"")
            }
        }
    }

    // MARK: - Timeout and cancellation

    func test_withTimeout_operationFinishesInTime_returnsItsValue() async throws {
        let value = try await AppleSubstitutionService.withTimeout(.seconds(10)) { 42 }
        XCTAssertEqual(value, 42)
    }

    func test_withTimeout_operationOverruns_throwsTimeout() async {
        do {
            _ = try await AppleSubstitutionService.withTimeout(.milliseconds(20)) {
                try await Task.sleep(for: .seconds(30))
                return 42
            }
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? SubstitutionServiceError, .timeout)
        }
    }

    /// A generation that fails for its own reason must surface that reason,
    /// not get reported as a timeout.
    func test_withTimeout_operationThrows_propagatesThatErrorNotTimeout() async {
        struct Boom: Error {}
        do {
            let _: Int = try await AppleSubstitutionService.withTimeout(.seconds(10)) {
                () async throws -> Int in throw Boom()
            }
            XCTFail("Expected Boom")
        } catch is Boom {
            // Expected.
        } catch {
            XCTFail("Expected Boom, got \(error)")
        }
    }

    /// Cancelling the surrounding task has to end the wait promptly and
    /// surface as cancellation - not as a timeout, and not by hanging until
    /// the timeout elapses.
    func test_withTimeout_outerTaskCancelled_throwsCancellation() async throws {
        let task = Task {
            try await AppleSubstitutionService.withTimeout(.seconds(60)) {
                try await Task.sleep(for: .seconds(60))
                return 1
            }
        }

        // Let the group start before cancelling, so this exercises
        // cancellation of running children rather than a pre-cancelled task.
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    /// The provider checks cancellation before building a session, so a
    /// caller that cancelled first never starts the model at all. Only
    /// meaningful where the model is actually available.
    func test_suggestSubstitutions_cancelledBeforeStart_throwsCancellationNotUnavailable() async throws {
        let service = AppleSubstitutionService()
        guard service.availability.canScan else {
            throw XCTSkip("Needs a device with Apple Intelligence available.")
        }

        let request = sampleRequest()
        let task = Task { try await service.suggestSubstitutions(for: request) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }
}
