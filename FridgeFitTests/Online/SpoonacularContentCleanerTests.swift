//
//  SpoonacularContentCleanerTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

@MainActor
final class SpoonacularContentCleanerTests: XCTestCase {

    // MARK: - Text

    func test_plainText_stripsTags_decodesNamedAndNumericEntities_collapsesSpace() {
        let html = "Mom&#8217;s <b>quick</b>&nbsp;pasta &amp; cheese<br/>dish &#x2014; ready"
        XCTAssertEqual(SpoonacularContentCleaner.plainText(fromHTML: html), "Mom’s quick pasta & cheese dish — ready")
    }

    func test_decodeEntities_doesNotDoubleDecode() {
        XCTAssertEqual(SpoonacularContentCleaner.decodeEntities("&amp;lt;"), "&lt;")
    }

    func test_title_cleansEntities_andNeverEmpty() {
        XCTAssertEqual(SpoonacularContentCleaner.title("Mac &amp; Cheese "), "Mac & Cheese")
        XCTAssertEqual(SpoonacularContentCleaner.title("  <b></b> "), "Untitled recipe")
    }

    func test_summary_removesGeneratedBoilerplate_keepsTheRest() {
        let html = """
        Garlic Pasta is a <b>vegetarian</b> main course. This recipe serves 2 and costs $1.12 per serving. \
        It has a spoonacular score of <b>45%</b>. If you like this recipe, you might also like <a href="x">Lemon Pasta</a>. \
        Try <a href="y">Pesto Pasta</a> for similar recipes.
        """
        XCTAssertEqual(
            SpoonacularContentCleaner.summary(fromHTML: html),
            "Garlic Pasta is a vegetarian main course. This recipe serves 2 and costs $1.12 per serving."
        )
    }

    func test_summary_onlyBoilerplate_isNil() {
        XCTAssertNil(SpoonacularContentCleaner.summary(fromHTML: "It has a spoonacular score of 12%."))
    }

    // MARK: - Steps

    func test_steps_preferAnalyzed_cleaned() {
        let steps = SpoonacularContentCleaner.steps(
            analyzed: ["1. Boil the <b>pasta</b>.", "  ", "Add 1.5 cups of stock.", "Add 1.5 cups of stock.", "..."],
            instructionsHTML: "<p>Ignored when analyzed steps exist.</p>"
        )
        XCTAssertEqual(steps, ["Boil the pasta.", "Add 1.5 cups of stock."])
    }

    func test_steps_fallBackToInstructionsListItems() {
        let html = "<ol><li>Preheat oven to 350&deg;F.</li><li>Step 2: Bake for 20 minutes.</li></ol>"
        XCTAssertEqual(
            SpoonacularContentCleaner.steps(analyzed: [], instructionsHTML: html),
            ["Preheat oven to 350°F.", "Bake for 20 minutes."]
        )
    }

    func test_steps_fallBackToSentences_forOneParagraph() {
        let html = "Chop the onion. Fry it until golden! Serve warm."
        XCTAssertEqual(
            SpoonacularContentCleaner.steps(analyzed: [], instructionsHTML: html),
            ["Chop the onion.", "Fry it until golden!", "Serve warm."]
        )
    }

    func test_steps_fallBackToLineBreaks() {
        let html = "Mix everything.<br>Rest 10 minutes.\nServe."
        XCTAssertEqual(
            SpoonacularContentCleaner.steps(analyzed: [], instructionsHTML: html),
            ["Mix everything.", "Rest 10 minutes.", "Serve."]
        )
    }

    func test_steps_nothingUsable_isEmpty() {
        XCTAssertEqual(SpoonacularContentCleaner.steps(analyzed: ["1.", "--"], instructionsHTML: nil), [])
        XCTAssertEqual(SpoonacularContentCleaner.steps(analyzed: [], instructionsHTML: "   "), [])
    }

    // MARK: - Images

    func test_imageURL_upgradesHTTP_completesFileNames_andUsesImageType() {
        XCTAssertEqual(
            SpoonacularContentCleaner.imageURL(image: "http://img.spoonacular.com/recipes/1-312x231.jpg", imageType: nil, recipeID: 1)?.absoluteString,
            "https://img.spoonacular.com/recipes/1-312x231.jpg"
        )
        XCTAssertEqual(
            SpoonacularContentCleaner.imageURL(image: "1-556x370.png", imageType: nil, recipeID: 1)?.absoluteString,
            "https://img.spoonacular.com/recipes/1-556x370.png"
        )
        XCTAssertEqual(
            SpoonacularContentCleaner.imageURL(image: nil, imageType: "jpg", recipeID: 42)?.absoluteString,
            "https://img.spoonacular.com/recipes/42-556x370.jpg"
        )
    }

    func test_imageURL_unusable_isNil() {
        XCTAssertNil(SpoonacularContentCleaner.imageURL(image: "  ", imageType: nil, recipeID: 1))
        XCTAssertNil(SpoonacularContentCleaner.imageURL(image: nil, imageType: "../x", recipeID: 1))
    }

    // MARK: - Through the parser

    func test_parseMatches_messyRecipe_isCleaned() throws {
        let json = """
        {"results": [{
          "id": 7,
          "title": "Mac &amp; Cheese",
          "image": "http://img.spoonacular.com/recipes/7-312x231.jpg",
          "summary": "Creamy &#8216;mac&#8217;. It has a spoonacular score of 30%.",
          "analyzedInstructions": [],
          "instructions": "<ol><li>Boil macaroni.</li><li>Stir in cheese.</li></ol>",
          "extendedIngredients": [{"id": 1, "name": "macaroni", "amount": 200, "unit": "g"}]
        }]}
        """
        let recipe = try XCTUnwrap(SpoonacularRecipeService.parseMatches(from: Data(json.utf8)).first?.recipe)

        XCTAssertEqual(recipe.title, "Mac & Cheese")
        XCTAssertEqual(recipe.imageURL?.scheme, "https")
        XCTAssertEqual(recipe.summary, "Creamy ‘mac’.")
        XCTAssertEqual(recipe.steps, ["Boil macaroni.", "Stir in cheese."])
    }

    func test_ranking_putsRecipesWithStepsAboveOnesWithout() {
        var noSteps = OnlineRecipeFixtures.match(id: 1, missedCount: 0)
        noSteps.recipe.steps = []
        let withSteps = OnlineRecipeFixtures.match(id: 2, missedCount: 2)

        let ranked = OnlineRecipeExpiryRanking.ranked([noSteps, withSteps], expiryUse: [:])

        XCTAssertEqual(ranked.map(\.id), [2, 1])
    }
}
