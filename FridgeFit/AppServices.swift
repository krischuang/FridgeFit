//
//  AppServices.swift
//  FridgeFit
//

import Foundation

// the non-storage half of what ContentView needs: AI services and FridgeFunds.
// storage (pantry + kitchen events, SwiftData or Firebase) is AppDependencies'
// job. the real app uses `live()`; UI tests launch with `-uiTesting` and get
// `uiTesting()`, so they never touch Firebase, the camera or Apple Intelligence.
struct AppServices {
    let textRecognizer: ReceiptTextRecognizer
    let interpreter: ReceiptIngredientInterpreter
    let recipeSuggestionService: RecipeSuggestionService
    let substitutionService: SubstitutionService
    // FridgeFunds reads the same pantry as everything else, so it's built from
    // whatever AppDependencies picked
    let makeFundsEnvironment: (AppDependencies) -> FundsEnvironment

    static func live() -> AppServices {
        AppServices(
            textRecognizer: VisionReceiptTextRecognizer(),
            interpreter: AppleReceiptIngredientInterpreter(),
            recipeSuggestionService: AppleRecipeSuggestionService(),
            substitutionService: OpenRouterConfiguration.loadFromInfoPlist()
                .map { OpenRouterSubstitutionService(configuration: $0) }
                ?? UnconfiguredSubstitutionService(),
            makeFundsEnvironment: { FundsEnvironment.matching($0) }
        )
    }

    static func uiTesting() -> AppServices {
        AppServices(
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
            makeFundsEnvironment: { FundsEnvironment.inMemory(pantryRepository: $0.pantryRepository) }
        )
    }
}

enum UITestSupport {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    // storage for UI tests: in-memory pantry (optionally seeded) and kitchen
    // history, using AppDependencies' own "already-made pair" init
    static func dependencies() -> AppDependencies {
        AppDependencies(
            backend: .swiftData,
            pantryRepository: InMemoryPantryRepository(seedItems: seededPantry()),
            eventRepository: InMemoryInventoryEventRepository()
        )
    }

    // Lets a UI test start with stuff already in the pantry instead of
    // typing it all in. Format is `name:quantity:unit`, comma separated,
    // e.g. UITEST_PANTRY="Eggs:6:pcs,Milk:500:ml".
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
