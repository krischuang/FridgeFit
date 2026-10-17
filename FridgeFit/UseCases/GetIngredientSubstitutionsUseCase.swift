//
//  GetIngredientSubstitutionsUseCase.swift
//  FridgeFit
//

import Foundation

/// Answers "what can I use instead of this ingredient?" for one recipe
/// ingredient, against the signed-in user's current pantry.
///
/// Orchestrates the whole Phase 3 flow: build a request, check the cache,
/// call the provider, validate every candidate against the real pantry,
/// drop anything rejected/structurally invalid, deduplicate, prioritize
/// pantry-backed options, and cap the result to a short list.
nonisolated struct GetIngredientSubstitutionsUseCase {
    private let substitutionService: SubstitutionService
    private let pantryRepository: PantryRepository
    private let cache: SubstitutionCache

    init(substitutionService: SubstitutionService, pantryRepository: PantryRepository, cache: SubstitutionCache) {
        self.substitutionService = substitutionService
        self.pantryRepository = pantryRepository
        self.cache = cache
    }

    /// - Parameters:
    ///   - targetIngredient: the recipe ingredient the user needs a
    ///     substitute for.
    ///   - dietaryRestrictions: always empty until a future phase adds a
    ///     real dietary/allergy profile.
    func execute(
        recipe: Recipe,
        targetIngredient: RecipeIngredient,
        feasibility: RecipeFeasibilityResult,
        dietaryRestrictions: [String] = []
    ) async throws -> [SubstitutionSuggestion] {
        let pantryItems = try await pantryRepository.fetchAll()

        let cacheKey = SubstitutionCacheKey(
            recipeID: recipe.id,
            ingredientName: targetIngredient.ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            pantrySnapshotHash: SubstitutionCache.pantrySnapshotHash(pantryItems)
        )
        if let cached = cache.suggestions(for: cacheKey) {
            return cached
        }

        let request = SubstitutionRequest(
            recipeID: recipe.id,
            recipeTitle: recipe.title,
            targetIngredientName: targetIngredient.ingredient.name,
            requiredQuantity: targetIngredient.quantity,
            requiredUnit: targetIngredient.unit,
            role: targetIngredient.role,
            pantryIngredients: pantryItems.map { PantryIngredientSummary(name: $0.name, quantity: $0.quantity, unit: $0.unit) },
            feasibilityStatus: feasibility.status,
            dietaryRestrictions: dietaryRestrictions
        )

        let rawSuggestions = try await substitutionService.suggestSubstitutions(for: request)
        let result = Self.validateAndRank(rawSuggestions, pantryItems: pantryItems, dietaryRestrictions: dietaryRestrictions)

        cache.store(result, for: cacheKey)
        return result
    }

    /// Validates every raw candidate, drops rejected/invalid ones,
    /// deduplicates by normalized ingredient name (first occurrence wins),
    /// sorts pantry-backed suggestions first, and caps to 3 - "a small
    /// list", not everything the provider returned.
    static func validateAndRank(
        _ rawSuggestions: [RawSubstitutionSuggestion],
        pantryItems: [PantryItem],
        dietaryRestrictions: [String]
    ) -> [SubstitutionSuggestion] {
        var seenNames = Set<String>()
        var validated: [SubstitutionSuggestion] = []

        for raw in rawSuggestions {
            guard let suggestion = SubstitutionSuggestionValidator.validate(raw, against: pantryItems, dietaryRestrictions: dietaryRestrictions) else {
                continue
            }
            guard suggestion.validationStatus != .rejected else { continue }

            let normalizedName = suggestion.ingredientName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !seenNames.contains(normalizedName) else { continue }
            seenNames.insert(normalizedName)
            validated.append(suggestion)
        }

        let sorted = validated.sorted { priority(for: $0.validationStatus) < priority(for: $1.validationStatus) }
        return Array(sorted.prefix(3))
    }

    private static func priority(for status: SubstitutionValidationStatus) -> Int {
        switch status {
        case .availableInPantry: return 0
        case .insufficientQuantity: return 1
        case .unsupportedUnit: return 2
        case .notInPantry: return 3
        case .rejected: return 4
        }
    }
}
