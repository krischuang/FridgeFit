//
//  RecipeIntoleranceAnalysisTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// Covers the allergen screen's two jobs: finding what is really there, and
/// refusing to clear what it cannot rule out.
@MainActor
final class RecipeIntoleranceAnalysisTests: XCTestCase {

    // MARK: - Unverified stays unverified

    func test_noIngredientNames_returnsNil_unverified() {
        XCTAssertNil(RecipeIntoleranceAnalysis.intolerances(inIngredientNames: []))
        XCTAssertNil(RecipeIntoleranceAnalysis.intolerances(inIngredientNames: ["  "]))
    }

    func test_safeIngredients_returnEmptySet_notNil() {
        // Empty set and nil are different facts: "screened, found nothing"
        // versus "could not screen". Only the first may be shown as a clear
        // screen; the second excludes the recipe.
        XCTAssertEqual(RecipeIntoleranceAnalysis.intolerances(inIngredientNames: ["carrot", "potato"]), [])
    }

    // MARK: - Detection

    func test_detectsKeywordsInIngredientNames() {
        let found = RecipeIntoleranceAnalysis.intolerances(inIngredientNames: ["Shrimp", "cheddar cheese"])
        XCTAssertEqual(found?.contains(.shellfish), true)
        XCTAssertEqual(found?.contains(.dairy), true)
    }

    func test_detectsSimplePlurals() {
        let found = RecipeIntoleranceAnalysis.intolerances(inIngredientNames: ["Eggs", "rolled oats", "anchovies"])
        XCTAssertEqual(found?.contains(.egg), true)
        XCTAssertEqual(found?.contains(.grain), true)
        XCTAssertEqual(found?.contains(.seafood), true)
    }

    func test_detectsMultiWordKeywords() {
        let found = RecipeIntoleranceAnalysis.intolerances(inIngredientNames: ["Pine Nuts", "dried apricots"])
        XCTAssertEqual(found?.contains(.treeNut), true)
        XCTAssertEqual(found?.contains(.sulfite), true)
    }

    func test_normalisationHandlesPunctuationAndDigits() {
        // "2% milk" and "all-purpose flour" must still tokenise.
        let found = RecipeIntoleranceAnalysis.intolerances(inIngredientNames: ["2% Milk", "all-purpose flour"])
        XCTAssertEqual(found?.contains(.dairy), true)
        XCTAssertEqual(found?.contains(.wheat), true)
    }

    // MARK: - Word boundaries, not substrings

    func test_eggplantIsNotEgg() {
        let found = RecipeIntoleranceAnalysis.intolerances(inIngredientNames: ["eggplant"])
        XCTAssertEqual(found?.contains(.egg), false, "Substring matching reported aubergine as egg")
    }

    func test_butternutSquashIsNotDairy() {
        let found = RecipeIntoleranceAnalysis.intolerances(inIngredientNames: ["butternut squash"])
        XCTAssertEqual(found?.contains(.dairy), false, "Substring matching reported butternut as butter")
    }

    func test_crabappleIsNotShellfish() {
        let found = RecipeIntoleranceAnalysis.intolerances(inIngredientNames: ["crabapple"])
        XCTAssertEqual(found?.contains(.shellfish), false)
    }

    // MARK: - Compositional exclusions

    func test_peanutButterIsPeanutButNotDairy() {
        let found = RecipeIntoleranceAnalysis.intolerances(inIngredientNames: ["Peanut Butter"])
        XCTAssertEqual(found?.contains(.peanut), true)
        XCTAssertEqual(found?.contains(.dairy), false, "Peanut butter contains no dairy")
    }

    func test_plantMilksAreNotDairy() {
        for name in ["coconut milk", "almond milk", "soy milk", "oat milk"] {
            let found = RecipeIntoleranceAnalysis.intolerances(inIngredientNames: [name])
            XCTAssertEqual(found?.contains(.dairy), false, "\(name) was reported as dairy")
        }
    }

    func test_plantMilksStillReportTheirOwnAllergen() {
        // Excluding dairy must not exclude the ingredient's real allergen.
        let almond = RecipeIntoleranceAnalysis.intolerances(inIngredientNames: ["almond milk"])
        XCTAssertEqual(almond?.contains(.treeNut), true)

        let soy = RecipeIntoleranceAnalysis.intolerances(inIngredientNames: ["soy milk"])
        XCTAssertEqual(soy?.contains(.soy), true)
    }

    func test_nonWheatFloursAreNotWheat() {
        let found = RecipeIntoleranceAnalysis.intolerances(inIngredientNames: ["almond flour"])
        XCTAssertEqual(found?.contains(.wheat), false)
        XCTAssertEqual(found?.contains(.treeNut), true)
    }

    func test_dairyIsStillReportedForRealDairy() {
        // The exclusions must not have opened a hole in the common case.
        for name in ["whole milk", "unsalted butter", "double cream", "greek yogurt", "buttermilk"] {
            let found = RecipeIntoleranceAnalysis.intolerances(inIngredientNames: [name])
            XCTAssertEqual(found?.contains(.dairy), true, "\(name) was not reported as dairy")
        }
    }

    // MARK: - No provider boolean can clear an allergen

    func test_providerGlutenFreeClaimCannotClearDetectedGluten() throws {
        // The provider says glutenFree, the ingredient list says flour.
        // The ingredient list wins: a provider boolean is not evidence, and
        // gluten-free is a claim FridgeFit does not make from recipe data.
        let json = """
        {"results": [{
          "id": 1, "title": "Flatbread",
          "glutenFree": true, "dairyFree": true, "vegan": true, "vegetarian": true,
          "extendedIngredients": [
            {"id": 1, "name": "wheat flour", "nameClean": "wheat flour", "amount": 200, "unit": "g"}
          ]
        }]}
        """
        let matches = try SpoonacularRecipeService.parseMatches(from: Data(json.utf8))
        let contained = try XCTUnwrap(matches.first?.recipe.containsIntolerances)
        XCTAssertTrue(contained.contains(.gluten), "A provider flag cleared a detected allergen")
        XCTAssertTrue(contained.contains(.wheat))
    }

    func test_providerVeganClaimCannotClearDetectedDairy() throws {
        let json = """
        {"results": [{
          "id": 2, "title": "Creamy Soup",
          "vegan": true, "dairyFree": true,
          "extendedIngredients": [
            {"id": 1, "name": "heavy cream", "nameClean": "cream", "amount": 100, "unit": "ml"}
          ]
        }]}
        """
        let matches = try SpoonacularRecipeService.parseMatches(from: Data(json.utf8))
        let contained = try XCTUnwrap(matches.first?.recipe.containsIntolerances)
        XCTAssertTrue(contained.contains(.dairy), "A provider flag cleared a detected allergen")
    }
}
