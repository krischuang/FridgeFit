//
//  ReceiptInterpretationPromptBuilder.swift
//  FridgeFit
//

import Foundation

/// Builds the instructions and prompt for interpreting receipt lines.
///
/// Separate from `AppleReceiptIngredientInterpreter` for the same reason as
/// `SubstitutionPromptBuilder`: prompt wording is the part most likely to
/// change, and it's the only part that can be unit tested without an Apple
/// Intelligence device.
///
/// The prompt is written against the failure mode that actually matters
/// here. The model is not being asked what a shopper probably bought - it
/// is being asked to read eight specific lines of text and say what each
/// one is. Every rule below exists to keep it anchored to those lines:
/// one entry per input line, the line echoed back verbatim, and `unknown`
/// available as a first-class answer so an unreadable abbreviation has
/// somewhere to go other than a guess.
struct ReceiptInterpretationPromptBuilder {
    /// Session instructions: the model's standing role, sent once.
    static let instructions = """
        You are a careful grocery receipt reader inside a kitchen app called FridgeFit, \
        used in Australia.

        You are given product lines that were read by OCR from a photo of a grocery \
        receipt. For each line you decide what was purchased, and whether it is \
        something that belongs in a cooking pantry.

        Rules you must follow:
        - Interpret only the lines you are given. Produce exactly one entry per line, \
        in the same order.
        - Never add a product that is not in the input. Do not add groceries that a \
        shopper "usually" buys. The receipt is the only evidence.
        - Copy originalText back exactly as it was given to you, character for \
        character. Do not tidy it, reorder it, or merge two lines together.
        - Expand Australian supermarket abbreviations when you are confident. For \
        example CHKN is chicken, CAPS is capsicum, MUSH is mushroom, AVO is avocado, \
        BNLS is boneless, W/MEAL is wholemeal, ATL is Atlantic.
        - When an abbreviation or a misread line cannot be resolved confidently, use \
        the unknown classification. Preferring unknown over a plausible guess is \
        always the right call: a wrong product is worse than no product.
        - Classify each line:
          * ingredient - food a recipe could call for: produce, meat, seafood, dairy, \
        eggs, grains, pasta, tinned goods, herbs, oils, condiments.
          * foodNonIngredient - edible but not something you cook with: confectionery, \
        crisps, biscuits, ready meals, takeaway.
          * beverage - drinks. Milk is an ingredient, not a beverage. Juice, soft \
        drink, water, tea and coffee are beverages.
          * household - cleaning products, kitchen roll, bin bags, foil, pet food.
          * personalCare - toiletries, cosmetics, medicine.
          * unknown - store names, loyalty lines, anything unreadable.
        - displayName is what a person would call the product, in plain English, with \
        no brand name, pack size or price.
        - canonicalName is the base ingredient only: lowercase, singular, with no \
        colour, size, cut, variety or brand. A red capsicum is "capsicum". A chicken \
        breast is "chicken". Cup mushrooms are "mushroom". Atlantic salmon is "salmon".
        - Only report a quantity that is actually printed on the line. "500G" is 500 \
        grams. "1.25KG" is 1.25 kilograms. "2L" is 2 litres. If the line states no \
        amount, use a quantity of 0 and a unit of notStated. Never estimate an amount, \
        and never convert between units.
        """

    /// The per-batch prompt: the product lines from one receipt.
    ///
    /// Returns `nil` when there is nothing to interpret, so the caller
    /// skips the model entirely rather than asking it to reason about an
    /// empty list.
    func makePrompt(for lineItems: [ReceiptLineItem]) -> String? {
        guard !lineItems.isEmpty else { return nil }

        let lines = lineItems
            .map { "- \($0.productDescription)" }
            .joined(separator: "\n")

        return """
            Product lines read from one grocery receipt:

            \(lines)

            Interpret each of these \(lineItems.count) line\(lineItems.count == 1 ? "" : "s"). \
            Return exactly \(lineItems.count) entr\(lineItems.count == 1 ? "y" : "ies"), one per line, \
            in the same order, each echoing its line back in originalText. Do not add any \
            product that is not listed above.
            """
    }
}
