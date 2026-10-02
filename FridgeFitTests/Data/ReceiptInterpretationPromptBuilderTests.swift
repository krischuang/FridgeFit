//
//  ReceiptInterpretationPromptBuilderTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class ReceiptInterpretationPromptBuilderTests: XCTestCase {
    private let builder = ReceiptInterpretationPromptBuilder()

    private func lineItem(_ description: String, order: Int = 0) -> ReceiptLineItem {
        ReceiptLineItem(
            originalText: "\(description)   4.00",
            productDescription: description,
            price: 4.00,
            order: order
        )
    }

    func test_makePrompt_includesEveryProductLine() throws {
        let prompt = try XCTUnwrap(builder.makePrompt(for: [
            lineItem("CHKN BREAST 500G"),
            lineItem("CAPS RED", order: 1),
            lineItem("MUSHROOM CUP 200G", order: 2)
        ]))

        XCTAssertTrue(prompt.contains("CHKN BREAST 500G"))
        XCTAssertTrue(prompt.contains("CAPS RED"))
        XCTAssertTrue(prompt.contains("MUSHROOM CUP 200G"))
    }

    /// The model is told how many entries to return, which is what makes a
    /// missing or invented entry detectable.
    func test_makePrompt_statesTheExpectedNumberOfEntries() throws {
        let prompt = try XCTUnwrap(builder.makePrompt(for: [
            lineItem("CHKN BREAST 500G"),
            lineItem("CAPS RED", order: 1)
        ]))

        XCTAssertTrue(prompt.contains("Interpret each of these 2 lines"))
        XCTAssertTrue(prompt.contains("Return exactly 2 entries"))
    }

    func test_makePrompt_usesSingularWordingForOneLine() throws {
        let prompt = try XCTUnwrap(builder.makePrompt(for: [lineItem("CAPS RED")]))

        XCTAssertTrue(prompt.contains("Interpret each of these 1 line."))
        XCTAssertTrue(prompt.contains("Return exactly 1 entry"))
    }

    func test_makePrompt_asksForTheLineToBeEchoedBack() throws {
        let prompt = try XCTUnwrap(builder.makePrompt(for: [lineItem("CAPS RED")]))

        XCTAssertTrue(prompt.contains("originalText"))
    }

    /// No lines means no prompt - asking a generative model to interpret
    /// an empty list is how an invented receipt happens.
    func test_makePrompt_returnsNil_whenThereAreNoLines() {
        XCTAssertNil(builder.makePrompt(for: []))
    }

    /// The anti-hallucination rules are the reason this feature is
    /// trustworthy, so assert they're actually in the instructions.
    func test_instructions_forbidInventingProducts() {
        let instructions = ReceiptInterpretationPromptBuilder.instructions

        XCTAssertTrue(instructions.contains("Never add a product that is not in the input"))
        XCTAssertTrue(instructions.contains("The receipt is the only evidence"))
        XCTAssertTrue(instructions.contains("Interpret only the lines you are given"))
    }

    func test_instructions_preferUnknownOverGuessing() {
        let instructions = ReceiptInterpretationPromptBuilder.instructions

        XCTAssertTrue(instructions.contains("unknown classification"))
        XCTAssertTrue(instructions.contains("a wrong product is worse than no product"))
    }

    func test_instructions_coverAustralianAbbreviations() {
        let instructions = ReceiptInterpretationPromptBuilder.instructions

        XCTAssertTrue(instructions.contains("CHKN"))
        XCTAssertTrue(instructions.contains("CAPS"))
        XCTAssertTrue(instructions.contains("MUSH"))
        XCTAssertTrue(instructions.contains("Australia"))
    }

    func test_instructions_defineEveryClassification() {
        let instructions = ReceiptInterpretationPromptBuilder.instructions

        for classification in ReceiptItemClassification.allCases {
            XCTAssertTrue(
                instructions.contains(classification.rawValue),
                "Instructions must explain the \(classification.rawValue) classification"
            )
        }
    }

    /// Quantities are only ever read, never estimated or converted.
    func test_instructions_forbidInventingOrConvertingQuantities() {
        let instructions = ReceiptInterpretationPromptBuilder.instructions

        XCTAssertTrue(instructions.contains("Only report a quantity that is actually printed"))
        XCTAssertTrue(instructions.contains("Never estimate an amount"))
        XCTAssertTrue(instructions.contains("never convert between units"))
    }

    func test_instructions_describeCanonicalNaming() {
        let instructions = ReceiptInterpretationPromptBuilder.instructions

        XCTAssertTrue(instructions.contains("canonicalName"))
        XCTAssertTrue(instructions.contains("A red capsicum is \"capsicum\""))
    }
}
