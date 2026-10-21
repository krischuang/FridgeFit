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

    /// Whether substitutions can be generated right now.
    ///
    /// Passed straight through from the provider so the UI can show an
    /// explained unavailable state instead of a button that always fails -
    /// the same passthrough `ScanReceiptUseCase.availability` does.
    var availability: AppleIntelligenceAvailability {
        substitutionService.availability
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
        // A cache hit is served even when the provider has since become
        // unavailable: these suggestions were really generated for this
        // pantry, so showing them again is honest, and it means toggling
        // Apple Intelligence off doesn't blank a screen the user is reading.
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
        let result = Self.validateAndRank(
            rawSuggestions,
            pantryItems: pantryItems,
            dietaryRestrictions: dietaryRestrictions,
            targetIngredientName: targetIngredient.ingredient.name
        )

        cache.store(result, for: cacheKey)
        return result
    }

    /// Validates every raw candidate, drops rejected/invalid/irrelevant
    /// ones, deduplicates by normalized ingredient name (first occurrence
    /// wins), sorts pantry-backed suggestions first, and caps to 3 - "a
    /// small list", not everything the provider returned.
    ///
    /// Every rule here is deterministic and applied after the fact, which is
    /// the point: the prompt asks the model for the same things, but what
    /// reaches the UI is decided by this function, not by whether the model
    /// complied. That mattered with a hosted model and matters just as much
    /// with an on-device one.
    ///
    /// - Parameter targetIngredientName: the ingredient a substitute was
    ///   asked for. Used to drop the model suggesting it back as its own
    ///   substitute - a small model's most likely irrelevant answer, and one
    ///   that looks like a bug on screen.
    static func validateAndRank(
        _ rawSuggestions: [RawSubstitutionSuggestion],
        pantryItems: [PantryItem],
        dietaryRestrictions: [String],
        targetIngredientName: String
    ) -> [SubstitutionSuggestion] {
        let normalizedTarget = normalized(targetIngredientName)
        var seenNames = Set<String>()
        var validated: [SubstitutionSuggestion] = []

        for raw in rawSuggestions {
            guard let suggestion = SubstitutionSuggestionValidator.validate(raw, against: pantryItems, dietaryRestrictions: dietaryRestrictions) else {
                continue
            }
            guard suggestion.validationStatus != .rejected else { continue }

            let normalizedName = normalized(suggestion.ingredientName)
            // "Instead of cream, use cream" is not a substitution.
            guard normalizedName != normalizedTarget else { continue }
            guard !seenNames.contains(normalizedName) else { continue }
            seenNames.insert(normalizedName)
            validated.append(suggestion)
        }

        let sorted = validated.sorted { priority(for: $0.validationStatus) < priority(for: $1.validationStatus) }
        return Array(sorted.prefix(3))
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
