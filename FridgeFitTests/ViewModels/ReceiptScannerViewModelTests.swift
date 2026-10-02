//
//  ReceiptScannerViewModelTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// Drives the whole receipt flow off mocks, so none of this needs Apple
/// Intelligence, Vision, a camera or a device.
@MainActor
final class ReceiptScannerViewModelTests: XCTestCase {
    private func makeViewModel(
        recognizer: MockReceiptTextRecognizer,
        interpreter: MockReceiptIngredientInterpreter = MockReceiptIngredientInterpreter(),
        repository: PantryRepository = InMemoryPantryRepository()
    ) -> ReceiptScannerViewModel {
        ReceiptScannerViewModel(
            textRecognizer: recognizer,
            interpreter: interpreter,
            pantryRepository: repository
        )
    }

    private func sampleInterpreter() -> MockReceiptIngredientInterpreter {
        let interpreter = MockReceiptIngredientInterpreter()
        let lines = ReceiptLineParser().parse(SampleReceipt.recognizedText)
        interpreter.result = .success(SampleReceipt.interpretation(for: lines))
        return interpreter
    }

    private func sampleViewModel(
        repository: PantryRepository = InMemoryPantryRepository()
    ) -> ReceiptScannerViewModel {
        makeViewModel(
            recognizer: MockReceiptTextRecognizer(lines: SampleReceipt.ocrLines),
            interpreter: sampleInterpreter(),
            repository: repository
        )
    }

    private func scanAndWait(_ viewModel: ReceiptScannerViewModel) async {
        viewModel.selectImage(TestImage.makeUIImage())
        viewModel.scan()
        await waitUntilNotScanning(viewModel)
    }

    private func waitUntilNotScanning(_ viewModel: ReceiptScannerViewModel) async {
        for _ in 0 ..< 200 where viewModel.scanState.isScanning {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Happy path

    func test_scan_populatesConfirmationDrafts() async {
        let viewModel = sampleViewModel()

        await scanAndWait(viewModel)

        XCTAssertEqual(viewModel.scanState, .completed)
        XCTAssertTrue(viewModel.isPresentingReview)
        XCTAssertEqual(
            viewModel.drafts.map(\.name),
            ["Banana", "Chicken Breast", "Cup Mushrooms", "Red Capsicum", "Atlantic Salmon"]
        )
    }

    /// Household and beverage lines are kept out of the confirmation list
    /// but stay available for DEBUG inspection.
    func test_scan_keepsExcludedItemsOutOfTheDraftsButAvailableForDiagnostics() async {
        let viewModel = sampleViewModel()

        await scanAndWait(viewModel)

        XCTAssertFalse(viewModel.drafts.contains { $0.name.contains("Dishwashing") })
        XCTAssertFalse(viewModel.drafts.contains { $0.name.contains("Paper Towel") })
        XCTAssertEqual(
            viewModel.excludedItems.map(\.displayName),
            ["Woolworths", "Coca Cola", "Dishwashing Tablets", "Paper Towel"]
        )
    }

    /// The behaviour that replaced "everything is 1 pcs": a stated amount
    /// is filled in, an unstated one is left for the user.
    func test_scan_fillsQuantityOnlyWhenTheReceiptStatedOne() async throws {
        let viewModel = sampleViewModel()

        await scanAndWait(viewModel)
        let byName = Dictionary(uniqueKeysWithValues: viewModel.drafts.map { ($0.name, $0) })

        let chicken = try XCTUnwrap(byName["Chicken Breast"])
        XCTAssertEqual(chicken.quantityText, "500")
        XCTAssertEqual(chicken.unit, .grams)
        XCTAssertTrue(chicken.hasDetectedQuantity)

        let capsicum = try XCTUnwrap(byName["Red Capsicum"])
        XCTAssertEqual(capsicum.quantityText, "", "An unstated quantity must stay empty")
        XCTAssertFalse(capsicum.hasDetectedQuantity)
        XCTAssertNil(capsicum.quantity)
    }

    /// The receipt line is shown under each row as checkable evidence.
    func test_scan_carriesTheReceiptLineOntoEachDraft() async throws {
        let viewModel = sampleViewModel()

        await scanAndWait(viewModel)
        let chicken = try XCTUnwrap(viewModel.drafts.first { $0.name == "Chicken Breast" })

        XCTAssertTrue(chicken.sourceText.contains("CHKN BREAST 500G"))
    }

    func test_scan_startsItemsAlreadyInThePantryUnticked() async throws {
        let repository = InMemoryPantryRepository(seedItems: [
            PantryItem(ingredient: Ingredient(name: "Banana", category: .produce), quantity: 3, unit: .pieces)
        ])
        let viewModel = sampleViewModel(repository: repository)

        await scanAndWait(viewModel)
        let banana = try XCTUnwrap(viewModel.drafts.first { $0.name == "Banana" })

        XCTAssertTrue(banana.isAlreadyInPantry)
        XCTAssertFalse(banana.isSelected)
    }

    // MARK: - Failures

    func test_scan_reportsFailure_whenNoTextIsRecognized() async {
        let viewModel = makeViewModel(recognizer: MockReceiptTextRecognizer(lines: []))

        await scanAndWait(viewModel)

        XCTAssertEqual(
            viewModel.scanState,
            .failed(message: ReceiptScanError.noTextRecognized.localizedDescription)
        )
        XCTAssertTrue(viewModel.drafts.isEmpty)
        XCTAssertFalse(viewModel.isPresentingReview)
    }

    func test_scan_reportsFailure_whenNothingIsAnIngredient() async {
        let interpreter = MockReceiptIngredientInterpreter(result: .success(
            ReceiptInterpretationResult(items: [
                SampleReceipt.item("PAPER TOWEL", "Paper Towel", "paper towel", .household, .other)
            ])
        ))
        let viewModel = makeViewModel(
            recognizer: MockReceiptTextRecognizer(lines: ["PAPER TOWEL 5.00"]),
            interpreter: interpreter
        )

        await scanAndWait(viewModel)

        XCTAssertEqual(
            viewModel.scanState,
            .failed(message: ReceiptScanError.noFoodItemsFound.localizedDescription)
        )
    }

    func test_scan_reportsFailure_withoutSelectedImage() async {
        let viewModel = makeViewModel(recognizer: MockReceiptTextRecognizer(lines: SampleReceipt.ocrLines))

        viewModel.scan()

        XCTAssertEqual(
            viewModel.scanState,
            .failed(message: ReceiptScanError.noImageSelected.localizedDescription)
        )
    }

    /// Framework error text must never reach the user.
    func test_scan_mapsUnknownErrorsToTheGenericMessage() async {
        struct OpaqueFailure: Error {}
        let viewModel = makeViewModel(
            recognizer: MockReceiptTextRecognizer(result: .failure(OpaqueFailure()))
        )

        await scanAndWait(viewModel)

        XCTAssertEqual(
            viewModel.scanState,
            .failed(message: ReceiptScanError.interpretationFailed.localizedDescription)
        )
    }

    // MARK: - Availability

    /// `async` like every other test here, and deliberately so. Releasing
    /// a main-actor-isolated class synchronously aborts in this target -
    /// see the note on `ReceiptScannerViewModel.deinit` - and that applies
    /// to pre-existing types such as `InMemoryPantryRepository` just as
    /// much as to anything added here.
    func test_canScan_isFalse_whenAppleIntelligenceIsUnavailable() async {
        let viewModel = makeViewModel(
            recognizer: MockReceiptTextRecognizer(lines: SampleReceipt.ocrLines),
            interpreter: MockReceiptIngredientInterpreter(availability: .deviceNotSupported)
        )

        XCTAssertFalse(viewModel.canScan)
        XCTAssertEqual(viewModel.availability, .deviceNotSupported)
        XCTAssertNotNil(viewModel.availability.unavailableTitle)
        XCTAssertNotNil(viewModel.availability.unavailableExplanation)
    }

    // MARK: - Cancellation and staleness

    func test_cancelScan_leavesNoResults() async {
        let viewModel = makeViewModel(
            recognizer: MockReceiptTextRecognizer(lines: SampleReceipt.ocrLines, delay: .milliseconds(400)),
            interpreter: sampleInterpreter()
        )

        viewModel.selectImage(TestImage.makeUIImage())
        viewModel.scan()
        viewModel.cancelScan()
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(viewModel.scanState, .idle)
        XCTAssertTrue(viewModel.drafts.isEmpty)
        XCTAssertFalse(viewModel.isPresentingReview)
    }

    /// A slow first scan must not overwrite the results of a later one.
    func test_selectingANewImage_discardsTheInFlightScan() async {
        let viewModel = makeViewModel(
            recognizer: MockReceiptTextRecognizer(lines: SampleReceipt.ocrLines, delay: .milliseconds(300)),
            interpreter: sampleInterpreter()
        )

        viewModel.selectImage(TestImage.makeUIImage())
        viewModel.scan()
        viewModel.selectImage(TestImage.makeUIImage())
        try? await Task.sleep(for: .milliseconds(450))

        XCTAssertEqual(viewModel.scanState, .idle)
        XCTAssertTrue(viewModel.drafts.isEmpty)
    }

    func test_scan_isIgnoredWhileAScanIsAlreadyRunning() async {
        let recognizer = MockReceiptTextRecognizer(lines: SampleReceipt.ocrLines, delay: .milliseconds(200))
        let viewModel = makeViewModel(recognizer: recognizer, interpreter: sampleInterpreter())

        viewModel.selectImage(TestImage.makeUIImage())
        viewModel.scan()
        viewModel.scan()
        await waitUntilNotScanning(viewModel)

        XCTAssertEqual(recognizer.recognizeCallCount, 1)
    }

    // MARK: - Editing

    func test_editing_updatesTheDraftWithoutRescanning() async throws {
        let viewModel = sampleViewModel()
        await scanAndWait(viewModel)
        let id = try XCTUnwrap(viewModel.drafts.first).id

        viewModel.updateName("Chicken Thigh", for: id)
        viewModel.updateCategory(.meat, for: id)
        viewModel.updateQuantityText("250", for: id)
        viewModel.updateUnit(.grams, for: id)
        viewModel.toggleSelection(for: id)

        let draft = try XCTUnwrap(viewModel.drafts.first)
        XCTAssertEqual(draft.name, "Chicken Thigh")
        XCTAssertEqual(draft.category, .meat)
        XCTAssertEqual(draft.quantityText, "250")
        XCTAssertEqual(draft.unit, .grams)
        XCTAssertFalse(draft.isSelected)
    }

    func test_removeDraft_dropsTheRow() async throws {
        let viewModel = sampleViewModel()
        await scanAndWait(viewModel)
        let before = viewModel.drafts.count
        let id = try XCTUnwrap(viewModel.drafts.first).id

        viewModel.removeDraft(id: id)

        XCTAssertEqual(viewModel.drafts.count, before - 1)
    }

    // MARK: - Pantry insertion

    func test_addSelectedToPantry_storesOnlyTickedItemsWithQuantities() async throws {
        let repository = InMemoryPantryRepository()
        let viewModel = sampleViewModel(repository: repository)
        await scanAndWait(viewModel)

        // Only the two rows the receipt gave quantities for are ticked.
        for draft in viewModel.drafts where !draft.hasDetectedQuantity {
            viewModel.toggleSelection(for: draft.id)
        }
        XCTAssertEqual(viewModel.selectedDrafts.count, 2)

        await viewModel.addSelectedToPantry()

        let stored = try await repository.fetchAll()
        XCTAssertEqual(stored.map(\.name).sorted(), ["Chicken Breast", "Cup Mushrooms"])
        XCTAssertEqual(viewModel.addSummary?.addedNames.sorted(), ["Chicken Breast", "Cup Mushrooms"])
    }

    /// Nothing is stored until the user confirms.
    func test_scan_storesNothingOnItsOwn() async throws {
        let repository = InMemoryPantryRepository()
        let viewModel = sampleViewModel(repository: repository)

        await scanAndWait(viewModel)

        let stored = try await repository.fetchAll()
        XCTAssertTrue(stored.isEmpty)
    }

    func test_reset_clearsEverything() async {
        let viewModel = sampleViewModel()
        await scanAndWait(viewModel)

        viewModel.reset()

        XCTAssertNil(viewModel.selectedImage)
        XCTAssertTrue(viewModel.drafts.isEmpty)
        XCTAssertTrue(viewModel.excludedItems.isEmpty)
        XCTAssertEqual(viewModel.scanState, .idle)
        XCTAssertFalse(viewModel.isPresentingReview)
    }
}
