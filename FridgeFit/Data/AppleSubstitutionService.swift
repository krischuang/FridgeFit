//
//  AppleSubstitutionService.swift
//  FridgeFit
//

import Foundation
import FoundationModels
import OSLog

/// `SubstitutionService` backed by Apple Intelligence, running entirely
/// on-device.
///
/// Replaces `OpenRouterSubstitutionService`. Nothing about the feature's
/// contract changed: it still answers one `SubstitutionRequest` with
/// untrusted `RawSubstitutionSuggestion`s, and
/// `SubstitutionSuggestionValidator` is still the only thing allowed to say
/// what's in the pantry. What changed is where the answer comes from - the
/// recipe title, the ingredient, and the user's pantry list no longer leave
/// the device, and there is no API key to configure.
///
/// Text-only, so the SDK's text-only limitation doesn't bite here: a recipe
/// ingredient and a pantry list are naturally names and quantities.
///
/// ## Why a timeout
///
/// On-device generation has no network to time out, but it can still take
/// longer than a cook tapping "Find Substitute" will wait - a cold model, a
/// busy device, a long pantry. `OpenRouterSubstitutionService` had a 20s
/// `URLRequest` timeout; this keeps an equivalent bound as an explicit race,
/// because an unbounded spinner is a worse outcome than an error with a
/// retry.
///
/// That bound turned out to be load-bearing, not belt-and-braces.
/// **`availability` can report `.available` on a device that cannot actually
/// generate anything.** On the iOS 26.1 simulator,
/// `SystemLanguageModel.default.availability` is `.available` and
/// `isAvailable` is `true`, but no model assets exist - the log shows
/// `com.apple.modelcatalog` has "no underlying assets" - and `respond` never
/// returns rather than throwing `assetsUnavailable`. Without this timeout the
/// "Finding substitutes…" spinner would run forever there. Checking
/// availability is necessary but not sufficient; the timeout is what makes
/// the failure visible and recoverable.
///
/// ## One session per request
///
/// A fresh `LanguageModelSession` per request, like
/// `AppleReceiptIngredientInterpreter`. Substitution requests are
/// independent - different recipes, different ingredients, often different
/// pantries - and a shared transcript would let one ingredient's answer bias
/// the next, as well as grow the context window for no benefit. The feature
/// is also already protected from repeat work upstream by
/// `SubstitutionCache`, so a fresh session does not mean a repeated
/// generation.
nonisolated struct AppleSubstitutionService: SubstitutionService {
    /// How long one generation may take before FridgeFit gives up. Matches
    /// the 20s bound the OpenRouter implementation used.
    static let generationTimeout: Duration = .seconds(20)

    private let model: SystemLanguageModel
    private let promptBuilder: SubstitutionPromptBuilder
    private let timeout: Duration
    private let logger = Logger(subsystem: "com.fridgefit.app", category: "AppleSubstitutionService")

    init(
        model: SystemLanguageModel = .default,
        promptBuilder: SubstitutionPromptBuilder = SubstitutionPromptBuilder(),
        timeout: Duration = Self.generationTimeout
    ) {
        self.model = model
        self.promptBuilder = promptBuilder
        self.timeout = timeout
    }

    /// Maps `SystemLanguageModel.Availability` onto FridgeFit's own states.
    ///
    /// Read fresh every time: the user can enable Apple Intelligence, or the
    /// model assets can finish downloading, while the app is running.
    var availability: AppleIntelligenceAvailability {
        switch model.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.deviceNotEligible):
            return .deviceNotSupported
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable(let reason):
            // A reason this build doesn't know about. Fail closed rather
            // than assuming a generation would work.
            logger.notice("Unrecognised model unavailability: \(String(describing: reason), privacy: .public)")
            return .unavailableForUnknownReason
        }
    }

    func suggestSubstitutions(for request: SubstitutionRequest) async throws -> [RawSubstitutionSuggestion] {
        let availability = self.availability
        guard availability.canScan else {
            throw SubstitutionServiceError.substitutionUnavailable(availability)
        }

        try Task.checkCancellation()

        let prompt = promptBuilder.makePrompt(for: request)
        let model = self.model

        do {
            return try await Self.withTimeout(timeout) {
                // The session is built inside the child task rather than
                // captured: `LanguageModelSession` isn't `Sendable`, while
                // `SystemLanguageModel` and the prompt string are.
                let session = LanguageModelSession(model: model) {
                    SubstitutionPromptBuilder.instructions
                }

                let response = try await session.respond(
                    to: Prompt(prompt),
                    generating: GeneratedSubstitutionSuggestions.self,
                    // Low temperature: a substitution is closer to a lookup
                    // than a creative act, and creativity here means
                    // ingredients that don't work or don't exist. Slightly
                    // above the receipt scanner's 0.1 because there is more
                    // than one right answer here.
                    options: GenerationOptions(temperature: 0.3)
                )
                return response.content.rawSuggestions
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SubstitutionServiceError {
            // Already mapped - the timeout race, or a nested throw.
            throw error
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapped(error, logger: logger)
        } catch {
            logger.error("Substitution generation failed: \(error.localizedDescription, privacy: .public)")
            throw SubstitutionServiceError.suggestionFailed
        }
    }

    /// Collapses the SDK's generation errors into the handful of outcomes a
    /// user can act on. Details go to the log, not the screen.
    ///
    /// Internal rather than private so the tests can drive it directly:
    /// `GenerationError.Context` has a public initialiser, which means every
    /// branch here is checkable on the simulator even though a real
    /// generation isn't.
    static func mapped(
        _ error: LanguageModelSession.GenerationError,
        logger: Logger = Logger(subsystem: "com.fridgefit.app", category: "AppleSubstitutionService")
    ) -> SubstitutionServiceError {
        logger.error("Generation failed: \(String(describing: error), privacy: .public)")

        switch error {
        case .rateLimited, .concurrentRequests:
            return .modelBusy
        case .guardrailViolation, .refusal:
            return .requestNotAllowed
        case .assetsUnavailable:
            // The model was available when we checked and isn't now - the
            // assets state is the honest explanation, not a generic failure.
            return .substitutionUnavailable(.modelNotReady)
        case .exceededContextWindowSize, .unsupportedGuide, .unsupportedLanguageOrLocale, .decodingFailure:
            return .suggestionFailed
        @unknown default:
            return .suggestionFailed
        }
    }

    /// Runs `operation`, throwing `SubstitutionServiceError.timeout` if it
    /// hasn't finished within `duration`.
    ///
    /// Delegates to `BoundedWork.run`, which is where the reason this
    /// is not a `withThrowingTaskGroup` race is written down. The short
    /// version: this function used to be that race, and a task group awaits
    /// its remaining children when its body returns. `cancelAll()` only
    /// *flags* a child, so a `respond` call that never returns - exactly what
    /// happens where the model reports itself available with no assets
    /// installed - kept the group's scope open and the caller suspended. The
    /// timeout fired and nobody could receive it, so the spinner the bound
    /// existed to prevent ran forever anyway.
    ///
    /// Internal rather than private, and generic over any operation, so the
    /// timeout and cancellation behaviour can be tested with a plain `async`
    /// closure. That matters here: the simulator has no Apple Intelligence
    /// model, so a test can never reach this code through
    /// `suggestSubstitutions`.
    static func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await BoundedWork.run(
            timeout: duration,
            timeoutError: { SubstitutionServiceError.timeout },
            operation: operation
        )
    }
}
