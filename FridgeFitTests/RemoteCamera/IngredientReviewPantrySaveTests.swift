//
//  IngredientReviewPantrySaveTests.swift
//  FridgeFitTests
//

import CoreGraphics
import Foundation
import XCTest
@testable import FridgeFit

/// Stage 3: confirmed ingredients reaching the pantry.
///
/// The thing under test is not "does a write happen" - `AddPantryItemUseCase`
/// already has its own tests. It is *what* is allowed to reach it: only rows
/// the user explicitly accepted, only with an amount they supplied, and only
/// once per tap.
@MainActor
final class IngredientReviewPantrySaveTests: XCTestCase {

    // MARK: - Fixtures

    /// A repository that counts writes and can be told to fail.
    private final class CountingPantryRepository: PantryRepository {
        private(set) var added: [PantryItem] = []
        var addError: Error?
        /// Fails only for items whose name is in here, so a partial outcome
        /// can be produced deliberately.
        var failingNames: Set<String> = []
        private(set) var addCallCount = 0

        func fetchAll() async throws -> [PantryItem] { added }

        func add(_ item: PantryItem) async throws {
            addCallCount += 1
            if let addError { throw addError }
            if failingNames.contains(item.name) {
                throw AddPantryItemError.invalidQuantity
            }
            added.append(item)
        }

        func update(_ item: PantryItem) async throws {}
        func remove(id: UUID) async throws {}
    }

    private func item(
        _ name: String,
        tier: ConfidenceTier = .agreed,
        category: IngredientGroup = .fruit,
        accepted: Bool = true,
        quantity: String = "2",
        unit: MeasurementUnit = .pieces,
        asserts: Bool = true
    ) -> IngredientReviewItem {
        IngredientReviewItem(
            origin: .recognised,
            recognised: FusedIngredient(
                ingredientId: name.lowercased(), displayName: name,
                category: category, tier: tier, sources: .detector,
                boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                detectorConfidence: 0.8, assertsIngredient: asserts
            ),
            displayName: name,
            category: category,
            isAccepted: accepted,
            quantityText: quantity,
            unit: unit
        )
    }

    private func model(
        _ items: [IngredientReviewItem],
        repository: CountingPantryRepository
    ) -> IngredientReviewViewModel {
        IngredientReviewViewModel(
            items: items,
            addIngredientsUseCase: AddDetectedIngredientsUseCase(pantryRepository: repository)
        )
    }

    // MARK: - Only confirmed items are stored

    func test_onlyAcceptedItemsReachThePantry() async {
        let repository = CountingPantryRepository()
        let viewModel = model(
            [item("Apple"), item("Banana", accepted: false), item("Pear")],
            repository: repository
        )

        await viewModel.saveToPantry()

        XCTAssertEqual(Set(repository.added.map(\.name)), ["Apple", "Pear"])
        XCTAssertFalse(repository.added.contains { $0.name == "Banana" },
                       "a rejected row must never be written")
    }

    func test_nothingIsSavedWhenNothingIsAccepted() async {
        let repository = CountingPantryRepository()
        let viewModel = model([item("Apple", accepted: false)], repository: repository)

        await viewModel.saveToPantry()

        XCTAssertTrue(repository.added.isEmpty)
        XCTAssertNotNil(viewModel.saveState.failureMessage)
    }

    /// Precision is 56.4%, so a disagreement is never preselected, and
    /// therefore never saved by a user who just taps Save.
    func test_aConflictingPredictionIsNotPreselectedAndSoIsNotSaved() async {
        let repository = CountingPantryRepository()
        let conflicting = IngredientReviewItem(
            FusedIngredient(
                ingredientId: "tomato", displayName: "Tomato", category: .vegetable,
                tier: .conflicting, sources: [.detector, .regionClassifier],
                boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                detectorConfidence: 0.8, classifierConfidence: 0.7,
                conflictingClaim: "Apple"
            )
        )
        let viewModel = model([conflicting], repository: repository)

        XCTAssertEqual(viewModel.acceptedCount, 0, "a conflict starts unticked")
        await viewModel.saveToPantry()

        XCTAssertTrue(repository.added.isEmpty)
    }

    // MARK: - User edits are preserved

    func test_editedNamesAndCategoriesAreWhatGetStored() async {
        let repository = CountingPantryRepository()
        let viewModel = model([item("Apple", category: .fruit)], repository: repository)
        let id = viewModel.items[0].id

        viewModel.rename(id, to: "Braeburn")
        viewModel.setPantryCategory(.produce, for: id)
        viewModel.setQuantityText("3", for: id)
        viewModel.setUnit(.kilograms, for: id)
        await viewModel.saveToPantry()

        let stored = try! XCTUnwrap(repository.added.first)
        XCTAssertEqual(stored.name, "Braeburn")
        XCTAssertEqual(stored.quantity, 3)
        XCTAssertEqual(stored.unit, .kilograms)
        XCTAssertEqual(stored.ingredient.category, .produce)
    }

    /// The detection taxonomy is coarser than the pantry's in places, so the
    /// override has to win over the derived mapping.
    func test_aPantryCategoryOverrideBeatsTheDerivedMapping() async {
        let repository = CountingPantryRepository()
        let viewModel = model([item("Rice", category: .pantry)], repository: repository)

        XCTAssertEqual(viewModel.items[0].resolvedPantryCategory, .other, "derived")
        viewModel.setPantryCategory(.grain, for: viewModel.items[0].id)
        await viewModel.saveToPantry()

        XCTAssertEqual(repository.added.first?.ingredient.category, .grain)
    }

    func test_aManuallyAddedIngredientIsStored() async {
        let repository = CountingPantryRepository()
        let viewModel = model([], repository: repository)

        viewModel.addManualIngredient(name: "Cheddar", category: .dairy)
        viewModel.setQuantityText("200", for: viewModel.items[0].id)
        viewModel.setUnit(.grams, for: viewModel.items[0].id)
        await viewModel.saveToPantry()

        let stored = try! XCTUnwrap(repository.added.first)
        XCTAssertEqual(stored.name, "Cheddar")
        XCTAssertEqual(stored.quantity, 200)
        XCTAssertEqual(stored.ingredient.category, .dairy)
    }

    // MARK: - Quantity is required, never invented

    func test_savingIsRefusedUntilEveryAcceptedRowHasAnAmount() {
        let repository = CountingPantryRepository()
        let viewModel = model(
            [item("Apple", quantity: "2"), item("Pear", quantity: "")],
            repository: repository
        )

        XCTAssertFalse(viewModel.canSaveToPantry)
        XCTAssertEqual(viewModel.acceptedItemsMissingQuantity.map(\.displayName), ["Pear"])

        viewModel.setQuantityText("1", for: viewModel.items[1].id)

        XCTAssertTrue(viewModel.canSaveToPantry)
        XCTAssertTrue(viewModel.acceptedItemsMissingQuantity.isEmpty)
    }

    func test_aMissingQuantityIsNeverDefaulted() async {
        let repository = CountingPantryRepository()
        let viewModel = model([item("Apple", quantity: "")], repository: repository)

        await viewModel.saveToPantry()

        XCTAssertTrue(repository.added.isEmpty, "no amount means no write, not '1 pcs'")
        XCTAssertEqual(viewModel.saveState.summary?.failures.count ?? 0, 0)
        XCTAssertNotNil(viewModel.saveState.failureMessage)
    }

    func test_aZeroOrNegativeQuantityIsNotUsable() {
        let repository = CountingPantryRepository()
        let viewModel = model([item("Apple", quantity: "0")], repository: repository)

        XCTAssertFalse(viewModel.items[0].hasValidQuantity)
        viewModel.setQuantityText("-3", for: viewModel.items[0].id)
        XCTAssertFalse(viewModel.items[0].hasValidQuantity)
        viewModel.setQuantityText("abc", for: viewModel.items[0].id)
        XCTAssertFalse(viewModel.items[0].hasValidQuantity)
    }

    // MARK: - Duplicate writes

    /// A second tap landing before the first save returns must not write
    /// everything twice.
    func test_concurrentSavesDoNotWriteTwice() async {
        let repository = CountingPantryRepository()
        let viewModel = model([item("Apple")], repository: repository)

        async let first: Void = viewModel.saveToPantry()
        async let second: Void = viewModel.saveToPantry()
        _ = await (first, second)

        XCTAssertEqual(repository.added.count, 1, "the second tap must be ignored")
    }

    /// An ingredient already in the pantry is reported, not duplicated.
    func test_anIngredientAlreadyInThePantryIsReportedAsADuplicate() async {
        let repository = CountingPantryRepository()
        try? await repository.add(PantryItem(
            ingredient: Ingredient(name: "Apple", category: .produce),
            quantity: 1, unit: .pieces
        ))
        let viewModel = model([item("Apple"), item("Pear")], repository: repository)

        await viewModel.saveToPantry()

        let summary = try! XCTUnwrap(viewModel.saveState.summary)
        XCTAssertEqual(summary.duplicateNames, ["Apple"])
        XCTAssertEqual(summary.addedNames, ["Pear"])
        XCTAssertEqual(repository.added.filter { $0.name == "Apple" }.count, 1,
                       "the existing apple is untouched and no second one is added")
    }

    // MARK: - States

    func test_aCleanSaveSucceedsAndAllowsDismissal() async {
        let repository = CountingPantryRepository()
        let viewModel = model([item("Apple")], repository: repository)

        await viewModel.saveToPantry()

        guard case .succeeded(let summary) = viewModel.saveState else {
            return XCTFail("expected success, got \(viewModel.saveState)")
        }
        XCTAssertEqual(summary.addedNames, ["Apple"])
        XCTAssertTrue(viewModel.saveState.allowsAutomaticDismissal)
        XCTAssertFalse(viewModel.saveState.isRetryable)
    }

    func test_aMixedOutcomeIsReportedAsPartialAndKeepsTheSheetOpen() async {
        let repository = CountingPantryRepository()
        repository.failingNames = ["Pear"]
        let viewModel = model([item("Apple"), item("Pear")], repository: repository)

        await viewModel.saveToPantry()

        guard case .partial(let summary) = viewModel.saveState else {
            return XCTFail("expected partial, got \(viewModel.saveState)")
        }
        XCTAssertEqual(summary.addedNames, ["Apple"])
        XCTAssertEqual(summary.failures.map(\.name), ["Pear"])
        XCTAssertFalse(viewModel.saveState.allowsAutomaticDismissal,
                       "the user has something to read and retry")
        XCTAssertTrue(viewModel.saveState.isRetryable)
    }

    func test_aTotalFailureIsReportedAndRetryable() async {
        let repository = CountingPantryRepository()
        repository.addError = NSError(
            domain: "FIRFirestoreErrorDomain", code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Missing or insufficient permissions."]
        )
        let viewModel = model([item("Apple")], repository: repository)

        await viewModel.saveToPantry()

        XCTAssertNotNil(viewModel.saveState.failureMessage)
        XCTAssertTrue(viewModel.saveState.isRetryable)
        XCTAssertFalse(viewModel.saveState.allowsAutomaticDismissal)
    }

    func test_withNoUseCaseWiredSavingFailsLoudly() async {
        let viewModel = IngredientReviewViewModel(items: [item("Apple")])

        await viewModel.saveToPantry()

        XCTAssertNotNil(viewModel.saveState.failureMessage,
                        "a missing pantry must be reported, not silently succeed")
    }

    // MARK: - The review results survive a failure

    /// Requirement: do not clear the review until persistence succeeds or the
    /// user dismisses it.
    func test_theReviewListSurvivesAFailedSave() async {
        let repository = CountingPantryRepository()
        repository.addError = NSError(domain: "test", code: 1)
        let viewModel = model([item("Apple"), item("Pear")], repository: repository)

        await viewModel.saveToPantry()

        XCTAssertEqual(viewModel.items.count, 2, "nothing is thrown away on failure")
        XCTAssertEqual(viewModel.acceptedCount, 2, "and the user's choices are intact")
    }

    // MARK: - Retry

    /// A retry after a partial failure must not re-send what already landed.
    func test_retryOnlySendsWhatDidNotGetStored() async {
        let repository = CountingPantryRepository()
        repository.failingNames = ["Pear"]
        let viewModel = model([item("Apple"), item("Pear")], repository: repository)

        await viewModel.saveToPantry()
        XCTAssertEqual(repository.added.map(\.name), ["Apple"])

        // The transient problem clears, and the user retries.
        repository.failingNames = []
        await viewModel.retrySave()

        XCTAssertEqual(repository.added.map(\.name), ["Apple", "Pear"],
                       "Apple must not be written a second time")
        XCTAssertEqual(repository.added.filter { $0.name == "Apple" }.count, 1)
    }

    func test_retryDoesNotResendDuplicatesEither() async {
        let repository = CountingPantryRepository()
        try? await repository.add(PantryItem(
            ingredient: Ingredient(name: "Apple", category: .produce),
            quantity: 1, unit: .pieces
        ))
        repository.failingNames = ["Pear"]
        let viewModel = model([item("Apple"), item("Pear")], repository: repository)

        await viewModel.saveToPantry()
        let callsAfterFirst = repository.addCallCount

        repository.failingNames = []
        await viewModel.retrySave()

        // Only Pear should have been attempted on the retry.
        XCTAssertEqual(repository.addCallCount, callsAfterFirst + 1)
        XCTAssertEqual(repository.added.filter { $0.name == "Apple" }.count, 1)
    }

    func test_retryAfterATotalFailureResendsEverything() async {
        let repository = CountingPantryRepository()
        repository.addError = NSError(domain: "test", code: 1)
        let viewModel = model([item("Apple"), item("Pear")], repository: repository)

        await viewModel.saveToPantry()
        XCTAssertTrue(repository.added.isEmpty)

        repository.addError = nil
        await viewModel.retrySave()

        XCTAssertEqual(Set(repository.added.map(\.name)), ["Apple", "Pear"])
    }

    func test_dismissingTheResultReturnsToEditing() async {
        let repository = CountingPantryRepository()
        let viewModel = model([item("Apple")], repository: repository)

        await viewModel.saveToPantry()
        XCTAssertNotNil(viewModel.saveState.summary)

        viewModel.dismissSaveResult()

        XCTAssertEqual(viewModel.saveState, .idle)
    }
}
