import XCTest
@testable import FridgeFit

// receipt line price -> review screen -> pantry -> Budget tab
@MainActor
final class ReceiptPriceToBudgetTests: XCTestCase {

    // records what it was told, nothing else
    private final class SpyRecorder: PurchasePriceRecording {
        var recorded: [(total: Decimal, item: PantryItem)] = []
        func recordPurchasePrice(_ total: Decimal, for item: PantryItem) {
            recorded.append((total, item))
        }
    }

    private func line(_ text: String, price: Double?, order: Int = 0) -> ReceiptLineItem {
        ReceiptLineItem(originalText: text, productDescription: text, price: price, order: order)
    }

    private func candidate(_ name: String, price: Decimal?, quantity: ReceiptQuantity? = ReceiptQuantity(value: 500, unit: .grams)) -> ReceiptIngredientCandidate {
        ReceiptIngredientCandidate(displayName: name, canonicalName: name.lowercased(), classification: .ingredient,
                                   category: .meat, quantity: quantity, sourceText: name.uppercased(), order: 0,
                                   price: price)
    }

    // normalizer

    func test_normalizer_keepsThePriceFromTheReceiptLine() {
        let lines = [line("CHKN BREAST 500G", price: 8.5)]
        let raw = SampleReceipt.item("CHKN BREAST 500G", "Chicken Breast", "chicken breast", .ingredient, .meat)

        let outcome = ReceiptItemNormalizer().normalize(ReceiptInterpretationResult(items: [raw]), against: lines)

        XCTAssertEqual(outcome.pantryCandidates.first?.price, Decimal(string: "8.50"))
    }

    func test_normalizer_noPriceOnTheLine_meansNoPrice() {
        let lines = [line("BANANA CAVENDISH", price: nil)]
        let raw = SampleReceipt.item("BANANA CAVENDISH", "Banana", "banana", .ingredient, .produce)

        let outcome = ReceiptItemNormalizer().normalize(ReceiptInterpretationResult(items: [raw]), against: lines)

        XCTAssertNil(outcome.pantryCandidates.first?.price)
    }

    func test_normalizer_sameItemTwice_addsThePricesUp() {
        let lines = [line("CHKN BREAST 500G", price: 8.5), line("CHKN BREAST 500G ", price: 8.5, order: 1)]
        let raws = [
            SampleReceipt.item("CHKN BREAST 500G", "Chicken Breast", "chicken breast", .ingredient, .meat),
            SampleReceipt.item("CHKN BREAST 500G ", "Chicken Breast", "chicken breast", .ingredient, .meat)
        ]

        let outcome = ReceiptItemNormalizer().normalize(ReceiptInterpretationResult(items: raws), against: lines)

        XCTAssertEqual(outcome.pantryCandidates.count, 1)
        XCTAssertEqual(outcome.pantryCandidates.first?.price, Decimal(17))
    }

    func test_markingAlreadyInPantry_doesntLoseThePrice() {
        let marked = candidate("Chicken Breast", price: 8).markingAlreadyInPantry(true)

        XCTAssertEqual(marked.price, 8)
    }

    // draft (review screen row)

    func test_draft_prefillsPriceFromReceipt() {
        let draft = ReceiptItemDraft(candidate: candidate("Chicken Breast", price: Decimal(string: "8.5")))

        XCTAssertEqual(draft.priceText, "8.50")
        XCTAssertEqual(draft.price, Decimal(string: "8.50"))
        XCTAssertTrue(draft.hasDetectedPrice)
    }

    func test_draft_withoutPrice_isEmpty_andJunkIsIgnored() {
        var draft = ReceiptItemDraft(candidate: candidate("Banana", price: nil))
        XCTAssertEqual(draft.priceText, "")
        XCTAssertNil(draft.price)

        draft.priceText = "abc"
        XCTAssertNil(draft.price)
        draft.priceText = "-2"
        XCTAssertNil(draft.price)
    }

    // adding to the pantry

    func test_addingScannedItems_sendsTheirPrice() async throws {
        let recorder = SpyRecorder()
        let useCase = AddDetectedIngredientsUseCase(pantryRepository: InMemoryPantryRepository(), priceRecorder: recorder)

        _ = await useCase.execute(drafts: [ReceiptItemDraft(candidate: candidate("Chicken Breast", price: Decimal(string: "8.5")))])

        XCTAssertEqual(recorder.recorded.count, 1)
        XCTAssertEqual(recorder.recorded.first?.total, Decimal(string: "8.50"))
        XCTAssertEqual(recorder.recorded.first?.item.name, "Chicken Breast")
    }

    func test_userCanChangeThePrice_beforeAdding() async {
        let recorder = SpyRecorder()
        let useCase = AddDetectedIngredientsUseCase(pantryRepository: InMemoryPantryRepository(), priceRecorder: recorder)
        var draft = ReceiptItemDraft(candidate: candidate("Chicken Breast", price: 8))
        draft.priceText = "6.40"

        _ = await useCase.execute(drafts: [draft])

        XCTAssertEqual(recorder.recorded.first?.total, Decimal(string: "6.40"))
    }

    func test_noPrice_nothingSent() async {
        let recorder = SpyRecorder()
        let useCase = AddDetectedIngredientsUseCase(pantryRepository: InMemoryPantryRepository(), priceRecorder: recorder)

        _ = await useCase.execute(drafts: [ReceiptItemDraft(candidate: candidate("Banana", price: nil))])

        XCTAssertTrue(recorder.recorded.isEmpty)
    }

    func test_rejectedDuplicate_doesntGetAPrice() async {
        let recorder = SpyRecorder()
        let existing = PantryItem(ingredient: Ingredient(name: "Chicken Breast", category: .meat), quantity: 200, unit: .grams)
        let useCase = AddDetectedIngredientsUseCase(pantryRepository: InMemoryPantryRepository(seedItems: [existing]),
                                                    priceRecorder: recorder)

        let summary = await useCase.execute(drafts: [ReceiptItemDraft(candidate: candidate("Chicken Breast", price: 8))])

        XCTAssertEqual(summary.duplicateNames, ["Chicken Breast"])
        XCTAssertTrue(recorder.recorded.isEmpty)
    }

    // FridgeFunds side. these have to be async - releasing a main-actor object at the
    // end of a plain sync test crashes in this target (see ReceiptScannerViewModel)

    func test_fundsRecorder_storesPerUnitCost_inTheBudgetCurrency() async {
        let environment = FundsEnvironment.inMemory(pantryRepository: InMemoryPantryRepository())
        environment.budgetStore.saveBudget(makeWeeklyBudget(limit: 100))
        let chicken = PantryItem(ingredient: Ingredient(name: "Chicken Breast"), quantity: 500, unit: .grams)

        FundsPurchasePriceRecorder(environment: environment).recordPurchasePrice(Decimal(string: "8.50")!, for: chicken)

        let info = environment.priceStore.info(for: FridgeFitPantryReading.id(for: chicken))
        XCTAssertEqual(info?.unitCost, Money(Decimal(string: "0.017")!, .aud))
    }

    func test_fundsRecorder_keepsAnExpiryThatWasAlreadySet() async {
        let environment = FundsEnvironment.inMemory(pantryRepository: InMemoryPantryRepository())
        let eggs = PantryItem(ingredient: Ingredient(name: "Eggs"), quantity: 12, unit: .pieces)
        let id = FridgeFitPantryReading.id(for: eggs)
        environment.priceStore.save(ItemPriceInfo(pantryItemID: id, expiryDate: TestDates.day(10)))

        FundsPurchasePriceRecorder(environment: environment).recordPurchasePrice(6, for: eggs)

        XCTAssertEqual(environment.priceStore.info(for: id)?.expiryDate, TestDates.day(10))
        XCTAssertEqual(environment.priceStore.info(for: id)?.unitCost, Money(Decimal(string: "0.5")!, .aud))
    }

    func test_fundsRecorder_skipsZeroQuantity() async {
        let environment = FundsEnvironment.inMemory(pantryRepository: InMemoryPantryRepository())
        let salt = PantryItem(ingredient: Ingredient(name: "Salt"), quantity: 0, unit: .grams)

        FundsPurchasePriceRecorder(environment: environment).recordPurchasePrice(2, for: salt)

        XCTAssertNil(environment.priceStore.info(for: FridgeFitPantryReading.id(for: salt)))
    }

    // the whole thing in one go: scan -> add -> shows up as money in the fridge
    func test_endToEnd_scannedPrice_showsUpAsMoneyInTheFridge() async throws {
        let pantry = InMemoryPantryRepository()
        let environment = FundsEnvironment.inMemory(pantryRepository: pantry)
        environment.budgetStore.saveBudget(makeWeeklyBudget(limit: 100))
        let useCase = AddDetectedIngredientsUseCase(pantryRepository: pantry,
                                                    priceRecorder: FundsPurchasePriceRecorder(environment: environment))

        _ = await useCase.execute(drafts: [ReceiptItemDraft(candidate: candidate("Chicken Breast", price: Decimal(string: "8.50")))])

        let viewModel = MoneyInFridgeViewModel(environment: environment)
        await viewModel.reload()
        XCTAssertEqual(viewModel.valuation?.totalValue, Money(Decimal(string: "8.5")!, .aud))
        XCTAssertEqual(viewModel.valuation?.unvaluedItemCount, 0)
    }
}
