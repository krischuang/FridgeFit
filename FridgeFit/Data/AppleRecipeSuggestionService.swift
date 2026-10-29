//
//  AppleRecipeSuggestionService.swift
//  FridgeFit
//

import Foundation
import FoundationModels
import OSLog

/// The guided-generation schema for pantry-based recipe ideas.
///
/// Note what the model is *not* asked for: there's no "available" or
/// "missing" field. It lists what a recipe needs, and
/// `SuggestRecipesFromPantryUseCase` works out which of those the pantry
/// actually has. Asking the model to split them would be inviting it to
/// contradict the pantry.
@Generable(description: "Recipe ideas that can be cooked from a given list of pantry ingredients")
struct GeneratedRecipeIdeas {
    @Guide(description: "Recipe suggestions, best first.", .maximumCount(5))
    var recipes: [GeneratedRecipeIdea]
}

@Generable(description: "A single recipe idea")
struct GeneratedRecipeIdea {
    @Guide(description: "Short dish name, such as 'Tomato and egg scramble'.")
    var name: String

    @Guide(
        description: "Every ingredient this recipe needs, using simple names. Include ingredients that are not in the pantry list.",
        .count(2...12)
    )
    var requiredIngredients: [String]

    @Guide(description: "How to cook it, in two or three short sentences.")
    var shortInstructions: String

    @Guide(description: "Rough total preparation and cooking time in minutes.", .range(0...240))
    var estimatedPreparationMinutes: Int
}

/// `RecipeSuggestionService` backed by Apple Intelligence, on-device.
///
/// Text-only, so no SDK limitation applies here - the pantry is naturally a
/// list of names and quantities. Enhances the recipe tab rather than
/// replacing any of it: `EvaluateRecipeFeasibilityUseCase` remains the only
/// thing that decides whether a *bundled* recipe is makeable, and these
/// suggestions are shown separately as ideas.
///
/// ## Why there is a deadline
///
/// There wasn't one, and `respond` provides none of its own. A device that
/// reports a model it has no assets installed for never returns from the
/// call at all, so "Finding recipe ideas…" had no exit. The bound is the
/// same shape and size as the substitution service's, and failing it is
/// genuinely recoverable here: the bundled recipe catalogue and
/// `EvaluateRecipeFeasibilityUseCase` do not involve a model, so the user
/// keeps a full browsable Recipes tab either way.
nonisolated struct AppleRecipeSuggestionService: RecipeSuggestionService {
    /// How long one generation may take before FridgeFit gives up.
    static let generationTimeout: Duration = .seconds(20)

    /// One generation, as a function. Injectable for the same reason as
    /// `AppleReceiptIngredientInterpreter.BatchInterpreting`: the deadline
    /// has to be provable without an Apple Intelligence device, and a
    /// generation that never returns cannot be staged with the real SDK.
    typealias Generating = @Sendable (_ prompt: String) async throws -> [RawRecipeSuggestion]

    private let model: SystemLanguageModel
    private let timeout: Duration
    private let generate: Generating
    private let logger = Logger(subsystem: "com.fridgefit.app", category: "AppleRecipeSuggestionService")

    private static let instructions = """
        You are a practical home cooking assistant inside a kitchen app called FridgeFit.

        You are given the ingredients a user currently has in their pantry. Suggest realistic \
        recipes they could cook.

        Rules you must follow:
        - Strongly prefer recipes that use the pantry ingredients you were given.
        - List every ingredient a recipe genuinely needs, including ones that are not in the \
        pantry. Do not hide a missing ingredient to make a recipe look achievable.
        - Do not claim an ingredient is in the pantry. Only list what the recipe requires; the \
        app checks the pantry itself.
        - Use simple ingredient names that match how the pantry list is written.
        - Keep instructions to two or three short sentences.
        - Suggest ordinary, cookable food. Do not invent ingredients that do not exist.
        - If the pantry is too sparse to cook anything sensible, return an empty list.
        """

    init(
        model: SystemLanguageModel = .default,
        timeout: Duration = Self.generationTimeout,
        generate: Generating? = nil
    ) {
        self.model = model
        self.timeout = timeout
        self.generate = generate ?? Self.onDeviceGeneration(model: model)
    }

    /// The real thing: one guided generation, on-device.
    private static func onDeviceGeneration(model: SystemLanguageModel) -> Generating {
        { prompt in
            // Built here rather than captured because
            // `LanguageModelSession` isn't `Sendable`.
            let session = LanguageModelSession(model: model) {
                Self.instructions
            }

            let response = try await session.respond(
                to: Prompt(prompt),
                generating: GeneratedRecipeIdeas.self,
                options: GenerationOptions(temperature: 0.4)
            )
            return response.content.recipes.map(\.rawSuggestion)
        }
    }

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
            logger.notice("Unrecognised model unavailability: \(String(describing: reason), privacy: .public)")
            return .unavailableForUnknownReason
        }
    }

    func suggestRecipes(from pantryItems: [PantryItem]) async throws -> [RawRecipeSuggestion] {
        let availability = self.availability
        guard availability.canScan else {
            throw RecipeSuggestionError.suggestionUnavailable(availability)
        }
        return try await generateSuggestions(from: pantryItems)
    }

    /// Everything `suggestRecipes` does except the availability gate, split
    /// out so the deadline is testable on a machine whose Apple Intelligence
    /// state the test does not control. Same reasoning as
    /// `AppleReceiptIngredientInterpreter.interpretBatches(of:)`.
    func generateSuggestions(from pantryItems: [PantryItem]) async throws -> [RawRecipeSuggestion] {
        guard !pantryItems.isEmpty else { return [] }

        try Task.checkCancellation()

        let pantryList = pantryItems
            .map { "- \($0.name) (\($0.formattedQuantity))" }
            .joined(separator: "\n")

        let prompt = """
            Pantry ingredients:
            \(pantryList)

            Suggest recipes that make the most of these ingredients.
            """

        let generate = self.generate

        do {
            return try await BoundedWork.run(
                timeout: timeout,
                timeoutError: { RecipeSuggestionError.timeout }
            ) {
                try await generate(prompt)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as RecipeSuggestionError {
            // Already mapped - the timeout, or a nested throw.
            throw error
        } catch let error as LanguageModelSession.GenerationError {
            logger.error("Recipe suggestion failed: \(String(describing: error), privacy: .public)")
            switch error {
            case .rateLimited, .concurrentRequests:
                throw RecipeSuggestionError.modelBusy
            case .guardrailViolation, .refusal:
                throw RecipeSuggestionError.requestNotAllowed
            case .assetsUnavailable:
                throw RecipeSuggestionError.suggestionUnavailable(.modelNotReady)
            default:
                throw RecipeSuggestionError.suggestionFailed
            }
        } catch {
            logger.error("Recipe suggestion failed: \(error.localizedDescription, privacy: .public)")
            throw RecipeSuggestionError.suggestionFailed
        }
    }
}

extension GeneratedRecipeIdea {
    var rawSuggestion: RawRecipeSuggestion {
        RawRecipeSuggestion(
            name: name,
            requiredIngredients: requiredIngredients,
            shortInstructions: shortInstructions,
            estimatedPreparationMinutes: estimatedPreparationMinutes
        )
    }
}
