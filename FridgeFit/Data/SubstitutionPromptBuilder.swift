//
//  SubstitutionPromptBuilder.swift
//  FridgeFit
//

import Foundation

/// Builds the OpenRouter chat-completion request body for a
/// `SubstitutionRequest`.
///
/// Kept as the one place that constructs prompt text, instead of building
/// prose inline in `OpenRouterSubstitutionService` or, worse, in a view.
/// The prompt tells the model what it may and may not claim - pantry
/// availability is explicitly reserved for the app, never the model.
nonisolated enum SubstitutionPromptBuilder {
    static func chatCompletionBody(for request: SubstitutionRequest, model: String) -> OpenRouterChatCompletionRequest {
        OpenRouterChatCompletionRequest(
            model: model,
            messages: [
                OpenRouterChatMessage(role: "system", content: systemPrompt),
                OpenRouterChatMessage(role: "user", content: userPrompt(for: request)),
            ],
            response_format: OpenRouterResponseFormat(type: "json_object"),
            temperature: 0.4,
            max_tokens: 700
        )
    }

    private static let systemPrompt = """
    You suggest culinary ingredient substitutions only. You never chat about anything else, plan meals, or discuss topics outside recipe substitutions.

    Rules:
    - Prioritize substitute ingredients already present in the user's pantry when they are culinarily viable.
    - You may also suggest ingredients not in the pantry.
    - Never claim the user has an ingredient in their pantry or state a pantry quantity - the application determines pantry availability itself from its own data, not from you.
    - Respect any dietary restrictions supplied. Never suggest an ingredient that conflicts with a stated restriction.
    - Return between 1 and 3 suggestions, ranked best first.
    - Be explicit about limitations (texture, flavor, or cooking differences versus the original ingredient).
    - Respond with a single JSON object and nothing else - no markdown formatting, no prose outside the JSON - matching exactly this schema:
    {"suggestions": [{"ingredientName": string, "suggestedQuantity": number or null, "suggestedUnit": one of "g", "kg", "ml", "L", "pcs", "cup", "tbsp", "tsp" or null, "confidence": number between 0 and 1 or null, "explanation": string, "limitations": string or null}]}
    Do not add fields outside this schema. Do not wrap the JSON in a code block.
    """

    private static func userPrompt(for request: SubstitutionRequest) -> String {
        var lines = [
            "Recipe: \(request.recipeTitle)",
            "Ingredient needing a substitute: \(request.targetIngredientName)",
            "Required amount: \(request.requiredUnit.formatted(request.requiredQuantity))",
            "Ingredient role: \(request.role.displayName)",
            "Current recipe feasibility: \(request.feasibilityStatus.title)",
        ]

        if request.pantryIngredients.isEmpty {
            lines.append("Pantry: empty")
        } else {
            let pantryDescription = request.pantryIngredients
                .map { "\($0.name) (\($0.unit.formatted($0.quantity)))" }
                .joined(separator: ", ")
            lines.append("Pantry contains: \(pantryDescription)")
        }

        if !request.dietaryRestrictions.isEmpty {
            lines.append("Dietary restrictions to respect: \(request.dietaryRestrictions.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - OpenRouter wire format (OpenAI-compatible)

nonisolated struct OpenRouterChatCompletionRequest: Encodable {
    let model: String
    let messages: [OpenRouterChatMessage]
    let response_format: OpenRouterResponseFormat?
    let temperature: Double
    let max_tokens: Int
}

nonisolated struct OpenRouterChatMessage: Codable {
    let role: String
    let content: String
}

nonisolated struct OpenRouterResponseFormat: Encodable {
    let type: String
}

nonisolated struct OpenRouterChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}
