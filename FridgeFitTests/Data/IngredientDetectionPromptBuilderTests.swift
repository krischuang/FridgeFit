//
//  IngredientDetectionPromptBuilderTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class IngredientDetectionPromptBuilderTests: XCTestCase {
    private let builder = IngredientDetectionPromptBuilder()

    func test_makePrompt_includesLabelsAndRecognizedText() throws {
        let evidence = FridgeImageEvidence(
            labels: [
                ObservedVisualLabel(identifier: "bottle", confidence: 0.91),
                ObservedVisualLabel(identifier: "citrus fruit", confidence: 0.42)
            ],
            recognizedText: ["Semi Skimmed Milk", "1 Litre"]
        )

        let prompt = try XCTUnwrap(builder.makePrompt(for: evidence))

        XCTAssertTrue(prompt.contains("bottle"))
        XCTAssertTrue(prompt.contains("0.91"))
        XCTAssertTrue(prompt.contains("citrus fruit"))
        XCTAssertTrue(prompt.contains("Semi Skimmed Milk"))
        XCTAssertTrue(prompt.contains("1 Litre"))
    }

    /// No evidence means no prompt - asking the model to identify ingredients
    /// from nothing is how a hallucinated pantry happens.
    func test_makePrompt_returnsNil_whenEvidenceIsEmpty() {
        XCTAssertNil(builder.makePrompt(for: .empty))
    }

    func test_makePrompt_statesWhenOneEvidenceKindIsMissing() throws {
        let labelsOnly = FridgeImageEvidence(
            labels: [ObservedVisualLabel(identifier: "broccoli", confidence: 0.7)],
            recognizedText: []
        )
        let textOnly = FridgeImageEvidence(labels: [], recognizedText: ["Greek Yogurt"])

        let labelsPrompt = try XCTUnwrap(builder.makePrompt(for: labelsOnly))
        XCTAssertTrue(labelsPrompt.contains("broccoli"))
        XCTAssertTrue(labelsPrompt.contains("Text read from packaging: none."))

        let textPrompt = try XCTUnwrap(builder.makePrompt(for: textOnly))
        XCTAssertTrue(textPrompt.contains("Visual labels: none detected."))
        XCTAssertTrue(textPrompt.contains("Greek Yogurt"))
    }

    /// The anti-hallucination rules are the reason this feature is
    /// trustworthy, so assert they're actually in the instructions.
    func test_instructions_containConservativeRules() {
        let instructions = IngredientDetectionPromptBuilder.instructions

        XCTAssertTrue(instructions.contains("conservative food inventory assistant"))
        XCTAssertTrue(instructions.contains("Never invent ingredients"))
        XCTAssertTrue(instructions.contains("opaque containers"))
        XCTAssertTrue(instructions.contains("normalized ingredient names"))
        XCTAssertTrue(instructions.contains("empty list"))
    }

    func test_makePrompt_asksForAnEmptyListRatherThanGuesses() throws {
        let evidence = FridgeImageEvidence(
            labels: [ObservedVisualLabel(identifier: "shelf", confidence: 0.3)],
            recognizedText: []
        )

        let prompt = try XCTUnwrap(builder.makePrompt(for: evidence))

        XCTAssertTrue(prompt.contains("Return an empty list rather than guessing."))
    }
}
