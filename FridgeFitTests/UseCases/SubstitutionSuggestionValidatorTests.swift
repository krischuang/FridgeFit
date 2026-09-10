//
//  SubstitutionSuggestionValidatorTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class SubstitutionSuggestionValidatorTests: XCTestCase {
    private func raw(
        name: String = "Greek Yogurt",
        quantity: Double? = 200,
        unit: String? = "g",
        confidence: Double? = 0.8,
        explanation: String = "Adds a similar creamy texture.",
        limitations: String? = "Slightly tangier flavor."
    ) -> RawSubstitutionSuggestion {
        RawSubstitutionSuggestion(ingredientName: name, suggestedQuantity: quantity, suggestedUnit: unit, confidence: confidence, explanation: explanation, limitations: limitations)
    }

    // MARK: - Pantry detection

    func test_validate_pantryIngredientDetected_exactMatch() {
        let pantry = [PantryItem(ingredient: Ingredient(name: "Greek Yogurt", category: .dairy), quantity: 300, unit: .grams)]

        let result = SubstitutionSuggestionValidator.validate(raw(), against: pantry, dietaryRestrictions: [])

        XCTAssertEqual(result?.validationStatus, .availableInPantry)
        XCTAssertEqual(result?.pantryQuantity, 300)
    }

    func test_validate_pantryIngredientDetected_caseInsensitiveAndTrimmed() {
        let pantry = [PantryItem(ingredient: Ingredient(name: "  greek yogurt  ", category: .dairy), quantity: 300, unit: .grams)]

        let result = SubstitutionSuggestionValidator.validate(raw(name: "GREEK YOGURT"), against: pantry, dietaryRestrictions: [])

        XCTAssertEqual(result?.validationStatus, .availableInPantry)
    }

    func test_validate_unknownIngredient_isNeverClaimedAsAvailable() {
        let pantry = [PantryItem(ingredient: Ingredient(name: "Milk", category: .dairy), quantity: 1000, unit: .milliliters)]

        let result = SubstitutionSuggestionValidator.validate(raw(name: "Coconut Milk"), against: pantry, dietaryRestrictions: [])

        XCTAssertEqual(result?.validationStatus, .notInPantry)
        XCTAssertNil(result?.pantryQuantity)
    }

    // MARK: - Quantity sufficiency

    func test_validate_pantryQuantitySufficient() {
        let pantry = [PantryItem(ingredient: Ingredient(name: "Greek Yogurt", category: .dairy), quantity: 300, unit: .grams)]

        let result = SubstitutionSuggestionValidator.validate(raw(quantity: 200, unit: "g"), against: pantry, dietaryRestrictions: [])

        XCTAssertEqual(result?.validationStatus, .availableInPantry)
    }

    func test_validate_pantryQuantityInsufficient_neverClaimsEnough() {
        // Scenario 2 from the spec: AI suggests 200 g, pantry only has 100 g.
        let pantry = [PantryItem(ingredient: Ingredient(name: "Greek Yogurt", category: .dairy), quantity: 100, unit: .grams)]

        let result = SubstitutionSuggestionValidator.validate(raw(quantity: 200, unit: "g"), against: pantry, dietaryRestrictions: [])

        XCTAssertEqual(result?.validationStatus, .insufficientQuantity)
        XCTAssertNotEqual(result?.validationStatus, .availableInPantry)
    }

    func test_validate_noSuggestedQuantity_reportsPresenceOnly() {
        let pantry = [PantryItem(ingredient: Ingredient(name: "Butter", category: .dairy), quantity: 200, unit: .grams)]

        let result = SubstitutionSuggestionValidator.validate(raw(name: "Butter", quantity: nil, unit: nil), against: pantry, dietaryRestrictions: [])

        XCTAssertEqual(result?.validationStatus, .availableInPantry)
        XCTAssertEqual(result?.pantryQuantity, 200)
    }

    // MARK: - Unit conversion

    func test_validate_gramsToKilograms() {
        let pantry = [PantryItem(ingredient: Ingredient(name: "Chicken Breast", category: .meat), quantity: 0.5, unit: .kilograms)]

        let result = SubstitutionSuggestionValidator.validate(raw(name: "Chicken Breast", quantity: 400, unit: "g"), against: pantry, dietaryRestrictions: [])

        XCTAssertEqual(result?.validationStatus, .availableInPantry)
    }

    func test_validate_millilitersToLiters() {
        let pantry = [PantryItem(ingredient: Ingredient(name: "Milk", category: .dairy), quantity: 1, unit: .liters)]

        let result = SubstitutionSuggestionValidator.validate(raw(name: "Milk", quantity: 750, unit: "ml"), against: pantry, dietaryRestrictions: [])

        XCTAssertEqual(result?.validationStatus, .availableInPantry)
    }

    func test_validate_incompatibleUnitDimensions_isUnsupportedUnit() {
        let pantry = [PantryItem(ingredient: Ingredient(name: "Butter", category: .dairy), quantity: 200, unit: .grams)]

        let result = SubstitutionSuggestionValidator.validate(raw(name: "Butter", quantity: 100, unit: "ml"), against: pantry, dietaryRestrictions: [])

        XCTAssertEqual(result?.validationStatus, .unsupportedUnit)
    }

    // MARK: - Structural validity

    func test_validate_blankIngredientName_isRejectedEntirely() {
        let result = SubstitutionSuggestionValidator.validate(raw(name: "   "), against: [], dietaryRestrictions: [])

        XCTAssertNil(result)
    }

    func test_validate_blankExplanation_isRejectedEntirely() {
        let result = SubstitutionSuggestionValidator.validate(raw(explanation: "  "), against: [], dietaryRestrictions: [])

        XCTAssertNil(result)
    }

    func test_validate_unparseableSuggestedUnit_isTreatedAsNoUnitGiven() {
        let pantry = [PantryItem(ingredient: Ingredient(name: "Greek Yogurt", category: .dairy), quantity: 300, unit: .grams)]

        let result = SubstitutionSuggestionValidator.validate(raw(quantity: 200, unit: "handfuls"), against: pantry, dietaryRestrictions: [])

        XCTAssertEqual(result?.validationStatus, .availableInPantry)
        XCTAssertNil(result?.suggestedUnit)
    }

    // MARK: - Dietary restrictions

    func test_validate_conflictingDietaryRestriction_isRejected() {
        let pantry = [PantryItem(ingredient: Ingredient(name: "Peanut Butter", category: .other), quantity: 200, unit: .grams)]

        let result = SubstitutionSuggestionValidator.validate(raw(name: "Peanut Butter"), against: pantry, dietaryRestrictions: ["peanut"])

        XCTAssertEqual(result?.validationStatus, .rejected)
    }

    func test_validate_nonConflictingDietaryRestriction_isUnaffected() {
        let pantry = [PantryItem(ingredient: Ingredient(name: "Greek Yogurt", category: .dairy), quantity: 300, unit: .grams)]

        let result = SubstitutionSuggestionValidator.validate(raw(), against: pantry, dietaryRestrictions: ["shellfish"])

        XCTAssertEqual(result?.validationStatus, .availableInPantry)
    }
}
