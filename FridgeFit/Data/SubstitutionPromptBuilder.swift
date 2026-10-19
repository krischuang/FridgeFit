//
//  SubstitutionPromptBuilder.swift
//  FridgeFit
//

import Foundation

/// Builds the instructions and prompt for suggesting ingredient substitutes.
///
/// Separate from `AppleSubstitutionService` for the same reason as
/// `ReceiptInterpretationPromptBuilder`: prompt wording is the part most
/// likely to change, and it's the only part that can be unit tested without
/// an Apple Intelligence device.
///
/// ## What changed moving off OpenRouter
///
/// The old prompt spent nearly half its length describing a JSON schema and
/// forbidding markdown code fences. None of that is needed now - guided
/// generation into `GeneratedSubstitutionSuggestions` makes the shape of the
/// answer a type, not a request, so the prompt only has to carry the rules
/// that are actually about cooking.
///
/// Every behavioural rule from the OpenRouter prompt is kept, because each
/// one exists for a reason:
///
/// - **Pantry-first, but not pantry-only.** Suggesting something the user
///   already has is the most useful answer; refusing to suggest anything
///   else would make the feature useless to a near-empty pantry.
/// - **The model never claims pantry availability.** It does not know what
///   is in the pantry, and `SubstitutionSuggestionValidator` decides that
///   from FridgeFit's own data. A model that writes "you already have milk"
///   into an explanation can contradict the badge next to it.
/// - **Dietary restrictions are respected.** Instructions alone aren't
///   trusted for this: `SubstitutionSuggestionValidator` independently
///   rejects any suggestion that matches a stated restriction, so a model
///   that ignores the rule still can't put that ingredient on screen.
/// - **Limitations are stated.** "Use yogurt instead of cream" without
///   "it can split if boiled" is the kind of advice that ruins a dinner.
///
/// ## Language
///
/// The prompt and instructions are English, which matches the app: FridgeFit
/// has no localization catalogue and `knownRegions` is `en` only, so every
/// user-facing string here is already English. That is within what the
/// on-device model supports - `SystemLanguageModel.supportedLanguages`
/// includes `en-AU`, the locale this app is written for, alongside 22
/// others.
///
/// The limitation to know about for a future localization pass: the model's
/// language set is fixed and does not cover every locale iOS does. A request
/// in an unsupported language fails with
/// `GenerationError.unsupportedLanguageOrLocale`, which
/// `AppleSubstitutionService` maps to a retryable `suggestionFailed` rather
/// than silently answering in the wrong language. Localizing this feature
/// means translating these strings *and* checking
/// `supportedLanguages` first - it is not automatic.
nonisolated struct SubstitutionPromptBuilder {
    /// Session instructions: the model's standing role, sent once.
    ///
    /// Kept deliberately short. This is a small on-device model, and a long
    /// preamble competes for attention with the recipe facts in the prompt
    /// itself - which are the part that actually varies.
    static let instructions = """
        You suggest culinary ingredient substitutions inside a kitchen app called FridgeFit. \
        That is the only thing you do: you do not plan meals, chat, or answer questions about \
        anything else.

        Rules you must follow:
        - Suggest substitutes that genuinely work for the specific recipe and the specific job \
        the original ingredient is doing in it.
        - Prefer substitutes from the user's pantry list when they are culinarily viable. \
        Suggesting something they already have is the most useful answer.
        - You may also suggest an ingredient that is not on the pantry list when it is clearly \
        the better swap.
        - Never say the user has an ingredient, or how much of it they have. You are shown the \
        pantry list only to choose good substitutes. FridgeFit checks availability itself from \
        its own data and shows that separately.
        - Never suggest the original ingredient back as its own substitute.
        - Respect every dietary restriction you are given. Never suggest an ingredient that \
        conflicts with one, including an ingredient that ordinarily contains it.
        - Be honest about limitations: how the texture, flavour or cooking behaviour will \
        differ from the original.
        - Do not state nutritional values, calorie counts, or that something is safe for an \
        allergy. You cannot know those.
        - Suggest real, ordinary ingredients a home cook can buy. Never invent one.
        - If nothing sensible substitutes for the ingredient in this recipe, return no \
        suggestions rather than a poor one.
        """

    /// The per-request prompt: the recipe facts for one missing ingredient.
    ///
    /// Only the context FridgeFit actually has is included - an absent
    /// section is left out rather than sent as "unknown", so the model isn't
    /// reasoning about placeholders.
    func makePrompt(for request: SubstitutionRequest) -> String {
        var lines = [
            "Recipe: \(request.recipeTitle)",
            "Ingredient needing a substitute: \(request.targetIngredientName)",
            "Amount the recipe needs: \(request.requiredUnit.formatted(request.requiredQuantity))",
            "How important it is to the dish: \(request.role.displayName)",
        ]

        if request.pantryIngredients.isEmpty {
            lines.append("The user's pantry list is empty.")
        } else {
            lines.append("The user's pantry contains: \(Self.pantryDescription(for: request.pantryIngredients))")
        }

        if !request.dietaryRestrictions.isEmpty {
            lines.append("Dietary restrictions you must respect: \(request.dietaryRestrictions.joined(separator: ", "))")
        }

        lines.append("")
        lines.append(
            "Suggest what to use instead of \(request.targetIngredientName) in this recipe."
        )

        return lines.joined(separator: "\n")
    }

    /// Caps how much pantry goes into the prompt.
    ///
    /// A long pantry is the only part of this prompt that can grow without
    /// bound, and a hundred lines of inventory would crowd out the recipe
    /// facts the model actually has to reason about - and cost context
    /// window for no benefit, since the full pantry is still checked
    /// deterministically afterwards by `SubstitutionSuggestionValidator`.
    /// A truncated list can only cost a *preference* for something the user
    /// owns, never a wrong availability badge.
    static let maximumPantryItemsInPrompt = 40

    private static func pantryDescription(for pantryIngredients: [PantryIngredientSummary]) -> String {
        let included = pantryIngredients.prefix(maximumPantryItemsInPrompt)
        let description = included
            .map { "\($0.name) (\($0.unit.formatted($0.quantity)))" }
            .joined(separator: ", ")

        guard pantryIngredients.count > included.count else { return description }
        return "\(description), and \(pantryIngredients.count - included.count) other items"
    }
}
