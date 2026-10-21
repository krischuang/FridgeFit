//
//  SubstitutionPromptBuilderTests.swift
//  FridgeFitTests
//
//  The prompt is the part of an on-device feature that can be tested
//  without the device, which is why it's a separate type - the same reason
//  `ReceiptInterpretationPromptBuilderTests` exists.
//
//  These tests assert on what the prompt *carries* and on the rules it
//  states, not on its exact prose, so wording can be improved without
//  rewriting the suite.
//

import XCTest
@testable import FridgeFit

final class SubstitutionPromptBuilderTests: XCTestCase {
    private let builder = SubstitutionPromptBuilder()

    private func request(
        recipeTitle: String = "Creamy Pasta",
        targetIngredientName: String = "Cream",
        requiredQuantity: Double = 200,
        requiredUnit: MeasurementUnit = .milliliters,
        role: IngredientRole = .essential,
        pantryIngredients: [PantryIngredientSummary] = [],
        feasibilityStatus: RecipeFeasibilityStatus = .notMakeable,
        dietaryRestrictions: [String] = []
    ) -> SubstitutionRequest {
        SubstitutionRequest(
            recipeID: UUID(),
            recipeTitle: recipeTitle,
            targetIngredientName: targetIngredientName,
            requiredQuantity: requiredQuantity,
            requiredUnit: requiredUnit,
            role: role,
            pantryIngredients: pantryIngredients,
            feasibilityStatus: feasibilityStatus,
            dietaryRestrictions: dietaryRestrictions
        )
    }

    // MARK: - Context carried into the prompt

    func test_prompt_carriesRecipeAndIngredientContext() {
        let prompt = builder.makePrompt(for: request())

        XCTAssertTrue(prompt.contains("Creamy Pasta"))
        XCTAssertTrue(prompt.contains("Cream"))
        XCTAssertTrue(prompt.contains("200 ml"), "The required amount has to reach the model")
        XCTAssertTrue(prompt.contains("Essential"), "The ingredient's role changes what substitutes are acceptable")
    }

    func test_prompt_includesPantryContents_withQuantities() {
        let prompt = builder.makePrompt(for: request(pantryIngredients: [
            PantryIngredientSummary(name: "Milk", quantity: 1000, unit: .milliliters),
            PantryIngredientSummary(name: "Butter", quantity: 250, unit: .grams),
        ]))

        XCTAssertTrue(prompt.contains("Milk (1000 ml)"))
        XCTAssertTrue(prompt.contains("Butter (250 g)"))
    }

    /// An empty pantry is stated rather than omitted - "no pantry section"
    /// and "an empty pantry" are different facts, and the second one should
    /// push the model towards common staples.
    func test_prompt_emptyPantry_isStatedExplicitly() {
        let prompt = builder.makePrompt(for: request(pantryIngredients: []))

        XCTAssertTrue(prompt.lowercased().contains("pantry list is empty"))
    }

    func test_prompt_includesDietaryRestrictions_whenPresent() {
        let prompt = builder.makePrompt(for: request(dietaryRestrictions: ["peanut", "dairy"]))

        XCTAssertTrue(prompt.contains("peanut"))
        XCTAssertTrue(prompt.contains("dairy"))
    }

    /// `dietaryRestrictions` is empty for every user today. The prompt must
    /// not invent a restrictions section saying "none", which reads to a
    /// small model as a topic worth discussing.
    func test_prompt_noDietaryRestrictions_omitsTheSectionEntirely() {
        let prompt = builder.makePrompt(for: request(dietaryRestrictions: []))

        XCTAssertFalse(prompt.lowercased().contains("dietary restriction"))
    }

    // MARK: - Prompt size

    /// A long pantry is the only unbounded part of this prompt. Truncating
    /// it can only cost a *preference* for something the user owns - the
    /// full pantry is still checked deterministically afterwards - so it is
    /// the right thing to bound.
    func test_prompt_longPantry_isTruncated_andSaysSo() {
        let pantry = (1...120).map {
            PantryIngredientSummary(name: "Item \($0)", quantity: Double($0), unit: .grams)
        }

        let prompt = builder.makePrompt(for: request(pantryIngredients: pantry))

        XCTAssertTrue(prompt.contains("Item 1 ("))
        XCTAssertFalse(prompt.contains("Item 120"), "The pantry should have been truncated")
        XCTAssertTrue(prompt.contains("other items"), "Truncation should be stated, not silent")
    }

    func test_prompt_staysSmallEvenForALargePantry() {
        let pantry = (1...400).map {
            PantryIngredientSummary(name: "Ingredient number \($0)", quantity: Double($0), unit: .grams)
        }

        let prompt = builder.makePrompt(for: request(pantryIngredients: pantry))

        // Comfortably inside the on-device context window, and small enough
        // that the recipe facts aren't crowded out by inventory.
        XCTAssertLessThan(prompt.count, 2_000, "Prompt grew to \(prompt.count) characters")
    }

    func test_prompt_shortPantry_isNotTruncated() {
        let pantry = (1...5).map {
            PantryIngredientSummary(name: "Item \($0)", quantity: 1, unit: .pieces)
        }

        let prompt = builder.makePrompt(for: request(pantryIngredients: pantry))

        XCTAssertTrue(prompt.contains("Item 5"))
        XCTAssertFalse(prompt.contains("other items"))
    }

    // MARK: - Instructions preserve the OpenRouter prompt's intent

    func test_instructions_keepThePantryAvailabilityRule() {
        let instructions = SubstitutionPromptBuilder.instructions.lowercased()

        XCTAssertTrue(instructions.contains("never say the user has an ingredient"))
        XCTAssertTrue(instructions.contains("fridgefit checks availability itself"))
    }

    func test_instructions_keepTheDietaryRestrictionRule() {
        XCTAssertTrue(SubstitutionPromptBuilder.instructions.lowercased().contains("respect every dietary restriction"))
    }

    func test_instructions_keepThePantryFirstPreference_withoutMakingItPantryOnly() {
        let instructions = SubstitutionPromptBuilder.instructions.lowercased()

        XCTAssertTrue(instructions.contains("prefer substitutes from the user's pantry"))
        XCTAssertTrue(instructions.contains("not on the pantry list"), "A near-empty pantry must still get suggestions")
    }

    func test_instructions_keepTheLimitationsRule() {
        XCTAssertTrue(SubstitutionPromptBuilder.instructions.lowercased().contains("limitations"))
    }

    /// New rules, added because an on-device model is smaller and more
    /// prone to these than the hosted model was.
    func test_instructions_forbidNutritionAndAllergenClaims() {
        let instructions = SubstitutionPromptBuilder.instructions.lowercased()

        XCTAssertTrue(instructions.contains("do not state nutritional values"))
        XCTAssertTrue(instructions.contains("safe for an"))
    }

    func test_instructions_forbidSuggestingTheOriginalIngredientBack() {
        XCTAssertTrue(SubstitutionPromptBuilder.instructions.lowercased().contains("never suggest the original ingredient"))
    }

    /// Guided generation makes the response shape a type. The prompt should
    /// no longer spend its budget describing JSON.
    func test_instructions_doNotDescribeAJSONSchema() {
        let instructions = SubstitutionPromptBuilder.instructions.lowercased()

        for leftover in ["json", "schema", "code block", "markdown"] {
            XCTAssertFalse(instructions.contains(leftover), "Instructions still mention \"\(leftover)\"")
        }
    }

    func test_instructions_areShortEnoughForAnOnDeviceModel() {
        XCTAssertLessThan(SubstitutionPromptBuilder.instructions.count, 1_600)
    }
}
