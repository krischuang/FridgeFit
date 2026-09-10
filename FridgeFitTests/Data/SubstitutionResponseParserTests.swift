//
//  SubstitutionResponseParserTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class SubstitutionResponseParserTests: XCTestCase {
    func test_parseSuggestions_decodesCleanJSON() throws {
        let content = """
        {"suggestions": [{"ingredientName": "Greek Yogurt", "suggestedQuantity": 200, "suggestedUnit": "g", "confidence": 0.8, "explanation": "Similar tang and texture.", "limitations": "Slightly tangier."}]}
        """

        let suggestions = try SubstitutionResponseParser.parseSuggestions(fromModelOutput: content)

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.ingredientName, "Greek Yogurt")
        XCTAssertEqual(suggestions.first?.suggestedQuantity, 200)
        XCTAssertEqual(suggestions.first?.suggestedUnit, "g")
    }

    func test_parseSuggestions_toleratesMarkdownCodeFence() throws {
        let content = """
        ```json
        {"suggestions": [{"ingredientName": "Milk", "suggestedQuantity": null, "suggestedUnit": null, "confidence": null, "explanation": "Thins the sauce.", "limitations": null}]}
        ```
        """

        let suggestions = try SubstitutionResponseParser.parseSuggestions(fromModelOutput: content)

        XCTAssertEqual(suggestions.first?.ingredientName, "Milk")
    }

    func test_parseSuggestions_toleratesSurroundingProse() throws {
        let content = """
        Sure, here you go:
        {"suggestions": [{"ingredientName": "Butter", "suggestedQuantity": null, "suggestedUnit": null, "confidence": null, "explanation": "Adds richness.", "limitations": null}]}
        Hope that helps!
        """

        let suggestions = try SubstitutionResponseParser.parseSuggestions(fromModelOutput: content)

        XCTAssertEqual(suggestions.first?.ingredientName, "Butter")
    }

    func test_parseSuggestions_malformedJSON_throwsMalformedResponse() {
        let content = "not json at all"

        XCTAssertThrowsError(try SubstitutionResponseParser.parseSuggestions(fromModelOutput: content)) { error in
            XCTAssertEqual(error as? SubstitutionServiceError, .malformedResponse)
        }
    }

    func test_parseSuggestions_validJSON_wrongShape_throwsMalformedResponse() {
        let content = #"{"unexpectedKey": "value"}"#

        XCTAssertThrowsError(try SubstitutionResponseParser.parseSuggestions(fromModelOutput: content)) { error in
            XCTAssertEqual(error as? SubstitutionServiceError, .malformedResponse)
        }
    }

    func test_parseSuggestions_emptySuggestionsArray_returnsEmpty() throws {
        let content = #"{"suggestions": []}"#

        let suggestions = try SubstitutionResponseParser.parseSuggestions(fromModelOutput: content)

        XCTAssertTrue(suggestions.isEmpty)
    }
}
