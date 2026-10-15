//
//  AppDependencies.swift
//  FridgeFit
//

import Foundation

/// Everything ContentView needs to build its view models. The real app uses
/// `live()`; the UI tests launch with `-uiTesting` and get `uiTesting()`
/// instead, so they never touch Firebase, the camera or Apple Intelligence.
struct AppDependencies {
    let pantryRepository: PantryRepository
    let textRecognizer: ReceiptTextRecognizer
    let interpreter: ReceiptIngredientInterpreter
    let recipeSuggestionService: RecipeSuggestionService
    let substitutionService: SubstitutionService
    /// FridgeFunds reads the same pantry, so it's built from whichever repository the rest of the app uses.
    let makeFundsEnvironment: (PantryRepository) -> FundsEnvironment

    static func live() -> AppDependencies {
        AppDependencies(
            pantryRepository: FirestorePantryRepository(),
            textRecognizer: VisionReceiptTextRecognizer(),
            interpreter: AppleReceiptIngredientInterpreter(),
            recipeSuggestionService: AppleRecipeSuggestionService(),
            substitutionService: OpenRouterConfiguration.loadFromInfoPlist()
                .map { OpenRouterSubstitutionService(configuration: $0) }
                ?? UnconfiguredSubstitutionService(),
            makeFundsEnvironment: { FundsEnvironment.firestore(pantryRepository: $0) }
        )
    }

    static func uiTesting() -> AppDependencies {
        AppDependencies(
            pantryRepository: InMemoryPantryRepository(seedItems: UITestSupport.seededPantry()),
            textRecognizer: MockReceiptTextRecognizer(lines: SampleReceiptPreviewData.lines),
            interpreter: MockReceiptIngredientInterpreter(),
            recipeSuggestionService: MockRecipeSuggestionService(result: .success([
                RawRecipeSuggestion(
                    name: "Cheesy Scrambled Eggs",
                    requiredIngredients: ["Eggs", "Cheddar"],
                    shortInstructions: "Scramble the eggs, throw the cheese in at the end.",
                    estimatedPreparationMinutes: 10
                )
            ])),
            substitutionService: MockSubstitutionService(result: .success([
                RawSubstitutionSuggestion(
                    ingredientName: "Mozzarella",
                    suggestedQuantity: 50,
                    suggestedUnit: "g",
                    confidence: 0.8,
                    explanation: "Melts about the same, a bit milder.",
                    limitations: nil
                )
            ])),
            makeFundsEnvironment: { FundsEnvironment.inMemory(pantryRepository: $0) }
        )
    }
}

enum UITestSupport {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    /// Lets a UI test start with stuff already in the pantry instead of
    /// typing it all in. Format is `name:quantity:unit`, comma separated,
    /// e.g. UITEST_PANTRY="Eggs:6:pcs,Milk:500:ml".
    static func seededPantry() -> [PantryItem] {
        guard let raw = ProcessInfo.processInfo.environment["UITEST_PANTRY"], !raw.isEmpty else {
            return []
        }
        return raw.split(separator: ",").compactMap { entry in
            let parts = entry.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 3,
                  let quantity = Double(parts[1]),
                  let unit = MeasurementUnit(rawValue: parts[2])
            else { return nil }
            return PantryItem(ingredient: Ingredient(name: parts[0]), quantity: quantity, unit: unit)
        }
    }
}
