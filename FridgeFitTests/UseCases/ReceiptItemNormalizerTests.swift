//
//  ReceiptItemNormalizerTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class ReceiptItemNormalizerTests: XCTestCase {
    private let normalizer = ReceiptItemNormalizer()

    private func line(_ description: String, originalText: String? = nil, order: Int = 0) -> ReceiptLineItem {
        ReceiptLineItem(
            originalText: originalText ?? description,
            productDescription: description,
            price: nil,
            order: order
        )
    }

    private func normalize(
        _ items: [RawInterpretedReceiptItem],
        against lines: [ReceiptLineItem]
    ) -> ReceiptScanOutcome {
        normalizer.normalize(ReceiptInterpretationResult(items: items), against: lines)
    }

    // MARK: - Classification decides what reaches the pantry

    func test_normalize_keepsIngredientsAndExcludesEverythingElse() {
        let lines = SampleReceipt.expectedProductDescriptions.enumerated().map { line($1, order: $0) }
        let outcome = normalize(SampleReceipt.interpretation(for: lines).items, against: lines)

        XCTAssertEqual(
            outcome.pantryCandidates.map(\.displayName),
            ["Banana", "Chicken Breast", "Cup Mushrooms", "Red Capsicum", "Atlantic Salmon"]
        )
        XCTAssertEqual(
            outcome.excluded.map(\.displayName),
            ["Woolworths", "Coca Cola", "Dishwashing Tablets", "Paper Towel"]
        )
    }

    func test_normalize_excludesHouseholdAndPersonalCare() {
        let lines = [line("DISHWASH TABLETS"), line("PAPER TOWEL", order: 1), line("SHAMPOO", order: 2)]
        let outcome = normalize([
            SampleReceipt.item("DISHWASH TABLETS", "Dishwashing Tablets", "dishwashing tablet", .household, .other),
            SampleReceipt.item("PAPER TOWEL", "Paper Towel", "paper towel", .household, .other),
            SampleReceipt.item("SHAMPOO", "Shampoo", "shampoo", .personalCare, .other)
        ], against: lines)

        XCTAssertTrue(outcome.pantryCandidates.isEmpty)
        XCTAssertEqual(outcome.excluded.count, 3)
    }

    func test_normalize_excludesBeveragesAndNonCookingFood() {
        let lines = [line("COCA COLA"), line("CHOC BAR", order: 1)]
        let outcome = normalize([
            SampleReceipt.item("COCA COLA", "Coca Cola", "cola", .beverage, .other),
            SampleReceipt.item("CHOC BAR", "Chocolate Bar", "chocolate", .foodNonIngredient, .other)
        ], against: lines)

        XCTAssertTrue(outcome.pantryCandidates.isEmpty)
        XCTAssertEqual(outcome.excluded.map(\.classification), [.beverage, .foodNonIngredient])
    }

    /// Milk is a cooking ingredient even though it is a drink, so the
    /// classification the model gives is what counts, not the category.
    func test_normalize_keepsMilkWhenClassifiedAsAnIngredient() {
        let lines = [line("MILK FULL CREAM 2L")]
        let outcome = normalize([
            SampleReceipt.item("MILK FULL CREAM 2L", "Full Cream Milk", "milk", .ingredient, .dairy, 2, "L")
        ], against: lines)

        XCTAssertEqual(outcome.pantryCandidates.map(\.displayName), ["Full Cream Milk"])
    }

    // MARK: - Anti-hallucination

    /// The defining safety property: the model cannot add groceries that
    /// were never on the receipt.
    func test_normalize_dropsItemsThatEchoALineNeverSent() {
        let lines = [line("CAPS RED")]
        let outcome = normalize([
            SampleReceipt.item("CAPS RED", "Red Capsicum", "capsicum", .ingredient, .produce),
            SampleReceipt.item("MILK 2L", "Milk", "milk", .ingredient, .dairy),
            SampleReceipt.item("BREAD WHITE", "White Bread", "bread", .ingredient, .grain)
        ], against: lines)

        XCTAssertEqual(outcome.pantryCandidates.map(\.displayName), ["Red Capsicum"])
        XCTAssertTrue(outcome.excluded.isEmpty)
    }

    /// A line echoed twice is still one purchase, not two.
    func test_normalize_consumesEachLineOnlyOnce() {
        let lines = [line("CAPS RED")]
        let outcome = normalize([
            SampleReceipt.item("CAPS RED", "Red Capsicum", "capsicum", .ingredient, .produce),
            SampleReceipt.item("CAPS RED", "Red Capsicum", "capsicum", .ingredient, .produce)
        ], against: lines)

        XCTAssertEqual(outcome.pantryCandidates.count, 1)
    }

    /// Minor echo drift is tolerated, because a round-tripped string picks
    /// up spacing and punctuation differences that mean nothing.
    func test_normalize_matchesEchoesDespiteSpacingAndCaseDrift() {
        let lines = [line("CHKN BREAST 500G")]
        let outcome = normalize([
            SampleReceipt.item("Chkn  Breast 500g", "Chicken Breast", "chicken", .ingredient, .meat, 500, "g")
        ], against: lines)

        XCTAssertEqual(outcome.pantryCandidates.map(\.displayName), ["Chicken Breast"])
    }

    // MARK: - Quantity

    func test_normalize_takesQuantityFromTheReceiptText() throws {
        let lines = [line("CHKN BREAST 500G", originalText: "CHKN BREAST 500G 8.50")]
        let outcome = normalize([
            SampleReceipt.item("CHKN BREAST 500G", "Chicken Breast", "chicken", .ingredient, .meat)
        ], against: lines)

        let candidate = try XCTUnwrap(outcome.pantryCandidates.first)
        XCTAssertEqual(candidate.quantity, ReceiptQuantity(value: 500, unit: .grams))
    }

    /// The receipt is the authority. A model that converts 500 g into
    /// 0.5 kg must not override what is printed.
    func test_normalize_prefersTheReceiptQuantityOverTheModels() throws {
        let lines = [line("CHKN BREAST 500G", originalText: "CHKN BREAST 500G 8.50")]
        let outcome = normalize([
            SampleReceipt.item("CHKN BREAST 500G", "Chicken Breast", "chicken", .ingredient, .meat, 0.5, "kg")
        ], against: lines)

        let candidate = try XCTUnwrap(outcome.pantryCandidates.first)
        XCTAssertEqual(candidate.quantity, ReceiptQuantity(value: 500, unit: .grams))
    }

    /// A quantity the line never mentioned is rejected outright, however
    /// confidently the model asserts it.
    func test_normalize_rejectsAModelQuantityThatIsNotInTheLine() throws {
        let lines = [line("CAPS RED", originalText: "CAPS RED 2.71")]
        let outcome = normalize([
            SampleReceipt.item("CAPS RED", "Red Capsicum", "capsicum", .ingredient, .produce, 500, "g")
        ], against: lines)

        let candidate = try XCTUnwrap(outcome.pantryCandidates.first)
        XCTAssertNil(candidate.quantity, "A quantity absent from the receipt must stay unknown")
    }

    /// When the deterministic parser can't see it but the number really is
    /// on the line, the model's reading is accepted.
    func test_normalize_acceptsAModelQuantityCorroboratedByTheLine() throws {
        let lines = [line("EGGS FREE RANGE 12 PACK", originalText: "EGGS FREE RANGE 12 PACK 7.50")]
        let outcome = normalize([
            SampleReceipt.item("EGGS FREE RANGE 12 PACK", "Free Range Eggs", "egg", .ingredient, .other, 12, "pcs")
        ], against: lines)

        let candidate = try XCTUnwrap(outcome.pantryCandidates.first)
        XCTAssertEqual(candidate.quantity, ReceiptQuantity(value: 12, unit: .pieces))
    }

    func test_normalize_leavesQuantityUnknownWhenNobodyStatedOne() throws {
        let lines = [line("MUSHROOM CUP")]
        let outcome = normalize([
            SampleReceipt.item("MUSHROOM CUP", "Cup Mushrooms", "mushroom", .ingredient, .produce)
        ], against: lines)

        XCTAssertNil(try XCTUnwrap(outcome.pantryCandidates.first).quantity)
    }

    // MARK: - Deduplication

    func test_normalize_collapsesSynonymsOntoOnePantryCandidate() {
        let lines = [
            line("CAPS RED", order: 0),
            line("CAPSICUM YELLOW", order: 1),
            line("BELL PEPPER GREEN", order: 2)
        ]
        let outcome = normalize([
            SampleReceipt.item("CAPS RED", "Red Capsicum", "capsicum", .ingredient, .produce),
            SampleReceipt.item("CAPSICUM YELLOW", "Yellow Capsicum", "capsicum", .ingredient, .produce),
            SampleReceipt.item("BELL PEPPER GREEN", "Green Bell Pepper", "bell pepper", .ingredient, .produce)
        ], against: lines)

        XCTAssertEqual(outcome.pantryCandidates.count, 1, "Three spellings of one vegetable is one pantry item")
        XCTAssertEqual(outcome.pantryCandidates.first?.canonicalName, "bell_pepper")
        XCTAssertEqual(outcome.pantryCandidates.first?.displayName, "Red Capsicum", "The first line's wording is kept")
    }

    /// Two lines of the same thing really is twice as much of it.
    func test_normalize_addsQuantitiesOfTheSameUnitWhenMerging() throws {
        let lines = [
            line("CHKN BREAST 500G", originalText: "CHKN BREAST 500G 8.50", order: 0),
            line("CHICKEN FILLET 300G", originalText: "CHICKEN FILLET 300G 6.00", order: 1)
        ]
        let outcome = normalize([
            SampleReceipt.item("CHKN BREAST 500G", "Chicken Breast", "chicken", .ingredient, .meat),
            SampleReceipt.item("CHICKEN FILLET 300G", "Chicken Fillet", "chicken", .ingredient, .meat)
        ], against: lines)

        XCTAssertEqual(outcome.pantryCandidates.count, 1)
        let candidate = try XCTUnwrap(outcome.pantryCandidates.first)
        XCTAssertEqual(candidate.quantity, ReceiptQuantity(value: 800, unit: .grams))
    }

    /// Mixed units are not converted - inventing a conversion would be
    /// worse than keeping the first stated amount.
    func test_normalize_keepsFirstQuantityWhenUnitsDiffer() throws {
        let lines = [
            line("CHKN BREAST 500G", originalText: "CHKN BREAST 500G", order: 0),
            line("CHICKEN 1.2KG", originalText: "CHICKEN 1.2KG", order: 1)
        ]
        let outcome = normalize([
            SampleReceipt.item("CHKN BREAST 500G", "Chicken Breast", "chicken", .ingredient, .meat),
            SampleReceipt.item("CHICKEN 1.2KG", "Chicken", "chicken", .ingredient, .meat)
        ], against: lines)

        XCTAssertEqual(try XCTUnwrap(outcome.pantryCandidates.first).quantity, ReceiptQuantity(value: 500, unit: .grams))
    }

    /// Distinct foods must survive deduplication.
    func test_normalize_doesNotMergeDifferentIngredients() {
        let lines = [line("POTATO BRUSHED", order: 0), line("SWEET POTATO", order: 1)]
        let outcome = normalize([
            SampleReceipt.item("POTATO BRUSHED", "Brushed Potato", "potato", .ingredient, .produce),
            SampleReceipt.item("SWEET POTATO", "Sweet Potato", "sweet potato", .ingredient, .produce)
        ], against: lines)

        XCTAssertEqual(outcome.pantryCandidates.count, 2)
    }

    // MARK: - Malformed and degenerate model output

    func test_normalize_returnsEmpty_forEmptyInterpretation() {
        let outcome = normalize([], against: [line("CAPS RED")])

        XCTAssertTrue(outcome.pantryCandidates.isEmpty)
        XCTAssertTrue(outcome.excluded.isEmpty)
        XCTAssertTrue(outcome.isEmpty)
    }

    func test_normalize_returnsEmpty_whenNoLinesWereSent() {
        let outcome = normalize([
            SampleReceipt.item("CAPS RED", "Red Capsicum", "capsicum", .ingredient, .produce)
        ], against: [])

        XCTAssertTrue(outcome.isEmpty)
    }

    func test_normalize_dropsItemsWithNoUsableName() {
        let lines = [line("CAPS RED"), line("???", order: 1)]
        let outcome = normalize([
            SampleReceipt.item("CAPS RED", "", "", .ingredient, .produce),
            SampleReceipt.item("???", "   ", "   ", .ingredient, .produce)
        ], against: lines)

        XCTAssertTrue(outcome.pantryCandidates.isEmpty)
    }

    func test_normalize_dropsOverlongNames() {
        let lines = [line("MYSTERY")]
        let outcome = normalize([
            SampleReceipt.item("MYSTERY", String(repeating: "a", count: 61), "mystery", .ingredient, .produce)
        ], against: lines)

        XCTAssertTrue(outcome.pantryCandidates.isEmpty)
    }

    /// An unreadable classification is not an ingredient.
    func test_normalize_treatsUnrecognisedClassificationAsUnknown() {
        let lines = [line("MYSTERY ITEM")]
        let outcome = normalize([
            SampleReceipt.item("MYSTERY ITEM", "Mystery Item", "mystery", .ingredient, .produce)
                .replacingClassification(with: "extremely-foodlike")
        ], against: lines)

        XCTAssertTrue(outcome.pantryCandidates.isEmpty)
        XCTAssertEqual(outcome.excluded.first?.classification, .unknown)
    }

    func test_normalize_fallsBackToOtherCategory_forUnrecognisedCategory() {
        let lines = [line("KIMCHI 500G")]
        let outcome = normalize([
            SampleReceipt.item("KIMCHI 500G", "Kimchi", "kimchi", .ingredient, .produce)
                .replacingCategory(with: "fermented-mystery")
        ], against: lines)

        XCTAssertEqual(outcome.pantryCandidates.first?.category, .other)
    }

    /// `unknown` is the model's honest answer for an unreadable line, and
    /// it must not become a pantry item.
    func test_normalize_excludesUnknownItems() {
        let lines = [line("WOOLWORTHS")]
        let outcome = normalize([
            SampleReceipt.item("WOOLWORTHS", "Woolworths", "woolworths", .unknown, .other)
        ], against: lines)

        XCTAssertTrue(outcome.pantryCandidates.isEmpty)
        XCTAssertEqual(outcome.excluded.map(\.classification), [.unknown])
    }

    // MARK: - Provenance

    /// The confirmation screen shows the receipt line, so it has to be the
    /// untouched original, price and all.
    func test_normalize_carriesTheOriginalReceiptLineThrough() throws {
        let lines = [line("CHKN BREAST 500G", originalText: "CHKN BREAST 500G       8.50")]
        let outcome = normalize([
            SampleReceipt.item("CHKN BREAST 500G", "Chicken Breast", "chicken", .ingredient, .meat)
        ], against: lines)

        XCTAssertEqual(try XCTUnwrap(outcome.pantryCandidates.first).sourceText, "CHKN BREAST 500G       8.50")
    }

    func test_normalize_ordersCandidatesByPositionOnTheReceipt() {
        let lines = [line("SALMON ATL", order: 5), line("BANANA", order: 1)]
        // Deliberately out of order, as a model that reordered its answers
        // would produce.
        let outcome = normalize([
            SampleReceipt.item("SALMON ATL", "Atlantic Salmon", "salmon", .ingredient, .meat),
            SampleReceipt.item("BANANA", "Banana", "banana", .ingredient, .produce)
        ], against: lines)

        XCTAssertEqual(outcome.pantryCandidates.map(\.displayName), ["Banana", "Atlantic Salmon"])
    }
}

private extension RawInterpretedReceiptItem {
    func replacingClassification(with classification: String) -> RawInterpretedReceiptItem {
        RawInterpretedReceiptItem(
            originalText: originalText,
            displayName: displayName,
            canonicalName: canonicalName,
            classification: classification,
            category: category,
            quantity: quantity,
            unit: unit
        )
    }

    func replacingCategory(with category: String) -> RawInterpretedReceiptItem {
        RawInterpretedReceiptItem(
            originalText: originalText,
            displayName: displayName,
            canonicalName: canonicalName,
            classification: classification,
            category: category,
            quantity: quantity,
            unit: unit
        )
    }
}
