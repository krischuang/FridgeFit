//
//  InventoryUseCaseTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

final class InventoryUseCaseTests: XCTestCase {

    private func makeRepositories(
        seedItems: [PantryItem] = []
    ) -> (pantry: InMemoryPantryRepository, events: InMemoryInventoryEventRepository) {
        (InMemoryPantryRepository(seedItems: seedItems), InMemoryInventoryEventRepository())
    }

    private func sampleItem(
        name: String = "Milk",
        quantity: Double = 1,
        unit: MeasurementUnit = .liters,
        expiryDate: Date? = nil,
        storageLocation: StorageLocation? = .fridge,
        openedState: OpenedState? = nil,
        lowStockThreshold: Double? = nil,
        packageUnit: PackageUnit? = nil,
        packageLevel: PackageLevel? = nil
    ) -> PantryItem {
        PantryItem(
            ingredient: Ingredient(name: name, category: .dairy),
            quantity: quantity,
            unit: unit,
            expiryDate: expiryDate,
            storageLocation: storageLocation,
            openedState: openedState,
            lowStockThreshold: lowStockThreshold,
            packageUnit: packageUnit,
            packageLevel: packageLevel
        )
    }

    // MARK: - AddInventoryItemUseCase

    func test_add_storesTheItemWithItsKitchenFields() async throws {
        let (pantry, events) = makeRepositories()
        let useCase = AddInventoryItemUseCase(pantryRepository: pantry, eventRepository: events)
        let expiry = Calendar.current.date(byAdding: .day, value: 5, to: .now)!

        let result = try await useCase.execute(AddInventoryItemRequest(
            name: "Spinach",
            category: .produce,
            storageLocation: .fridge,
            quantity: .measure(150, unit: .grams),
            expiryDate: expiry,
            lowStockThreshold: 60
        ))

        let stored = try await pantry.fetchAll()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.name, "Spinach")
        XCTAssertEqual(stored.first?.quantity, 150)
        XCTAssertEqual(stored.first?.unit, .grams)
        XCTAssertEqual(stored.first?.storageLocation, .fridge)
        XCTAssertEqual(stored.first?.expiryDate, expiry)
        XCTAssertEqual(stored.first?.lowStockThreshold, 60)
        XCTAssertEqual(result.item.id, stored.first?.id)
    }

    func test_add_storesAPackageQuantityTruthfullyForBothReaders() async throws {
        let (pantry, events) = makeRepositories()
        let useCase = AddInventoryItemUseCase(pantryRepository: pantry, eventRepository: events)

        try await useCase.execute(AddInventoryItemRequest(
            name: "Milk",
            category: .dairy,
            storageLocation: .fridge,
            quantity: .package(count: 1, unit: .bottle, level: .full)
        ))

        let stored = try await pantry.fetchAll().first
        // Recipe feasibility sees a real number...
        XCTAssertEqual(stored?.quantity, 1)
        // ...and the kitchen UI sees a bottle.
        XCTAssertEqual(stored?.inventoryQuantity, .package(count: 1, unit: .bottle, level: .full))
    }

    func test_add_recordsExactlyOneAddedEvent() async throws {
        let (pantry, events) = makeRepositories()
        let useCase = AddInventoryItemUseCase(pantryRepository: pantry, eventRepository: events)

        try await useCase.execute(AddInventoryItemRequest(
            name: "Eggs",
            category: .dairy,
            storageLocation: .fridge,
            quantity: .count(6)
        ))

        let log = try await events.fetchAll(limit: 100)
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log.first?.kind, .added)
        XCTAssertEqual(log.first?.itemName, "Eggs")
        XCTAssertEqual(log.first?.note, "6 pcs")
    }

    func test_add_rejectsAZeroQuantity() async {
        let (pantry, events) = makeRepositories()
        let useCase = AddInventoryItemUseCase(pantryRepository: pantry, eventRepository: events)

        do {
            try await useCase.execute(AddInventoryItemRequest(
                name: "Eggs",
                category: .dairy,
                storageLocation: .fridge,
                quantity: .count(0)
            ))
            XCTFail("Expected invalidQuantity")
        } catch {
            XCTAssertEqual(error as? AddInventoryItemError, .invalidQuantity)
        }
    }

    func test_add_reusesThePantrysBlankNameRule() async {
        // Not reimplemented here - this is `AddPantryItemUseCase`'s error,
        // reaching the kitchen UI unchanged.
        let (pantry, events) = makeRepositories()
        let useCase = AddInventoryItemUseCase(pantryRepository: pantry, eventRepository: events)

        do {
            try await useCase.execute(AddInventoryItemRequest(
                name: "   ",
                category: .other,
                storageLocation: .fridge,
                quantity: .count(1)
            ))
            XCTFail("Expected emptyIngredientName")
        } catch {
            XCTAssertEqual(error as? AddPantryItemError, .emptyIngredientName)
        }
    }

    func test_add_reusesThePantrysDuplicateRule() async throws {
        // The whole point of routing through AddPantryItemUseCase: adding
        // from the Kitchen tab behaves the same as adding from the Pantry
        // tab, including being told to update the existing row.
        let existing = sampleItem(name: "Milk")
        let (pantry, events) = makeRepositories(seedItems: [existing])
        let useCase = AddInventoryItemUseCase(pantryRepository: pantry, eventRepository: events)

        do {
            try await useCase.execute(AddInventoryItemRequest(
                name: "milk",
                category: .dairy,
                storageLocation: .fridge,
                quantity: .count(1)
            ))
            XCTFail("Expected duplicateIngredient")
        } catch {
            XCTAssertEqual(error as? AddPantryItemError, .duplicateIngredient(name: "Milk"))
        }
        // And nothing was written on the failed path.
        let actual1 = try await pantry.fetchAll().count
        XCTAssertEqual(actual1, 1)
        let actual2 = try await events.fetchAll(limit: 100).count
        XCTAssertEqual(actual2, 0)
    }

    // MARK: - RecordIngredientUseUseCase

    func test_recordUse_reducesTheStoredAmount() async throws {
        let item = sampleItem(name: "Chicken", quantity: 500, unit: .grams)
        let (pantry, events) = makeRepositories(seedItems: [item])
        let useCase = RecordIngredientUseUseCase(pantryRepository: pantry, eventRepository: events)

        try await useCase.execute(itemID: item.id, usedAmount: 150)

        let actual3 = try await pantry.fetchAll().first?.quantity
        XCTAssertEqual(actual3, 350)
    }

    func test_recordUse_writesOneUsedEventNamingTheAmount() async throws {
        let item = sampleItem(name: "Chicken", quantity: 500, unit: .grams)
        let (pantry, events) = makeRepositories(seedItems: [item])
        let useCase = RecordIngredientUseUseCase(pantryRepository: pantry, eventRepository: events)

        try await useCase.execute(itemID: item.id, usedAmount: 150)

        let log = try await events.fetchAll(limit: 100)
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log.first?.kind, .used)
        XCTAssertEqual(log.first?.note, "Used 150 g")
    }

    func test_recordUse_refusesMoreThanIsAvailable_andChangesNothing() async throws {
        let item = sampleItem(name: "Chicken", quantity: 100, unit: .grams)
        let (pantry, events) = makeRepositories(seedItems: [item])
        let useCase = RecordIngredientUseUseCase(pantryRepository: pantry, eventRepository: events)

        do {
            try await useCase.execute(itemID: item.id, usedAmount: 150)
            XCTFail("Expected amountExceedsAvailable")
        } catch {
            XCTAssertEqual(
                error as? RecordIngredientUseError,
                .amountExceedsAvailable(available: 100, unit: "g")
            )
        }
        // The failure happened before any write, so the amount is untouched
        // and no event claims a use that did not happen.
        let actual4 = try await pantry.fetchAll().first?.quantity
        XCTAssertEqual(actual4, 100)
        let actual5 = try await events.fetchAll(limit: 100).count
        XCTAssertEqual(actual5, 0)
    }

    func test_recordUse_rejectsZero() async {
        let item = sampleItem(quantity: 100, unit: .grams)
        let (pantry, events) = makeRepositories(seedItems: [item])
        let useCase = RecordIngredientUseUseCase(pantryRepository: pantry, eventRepository: events)

        do {
            try await useCase.execute(itemID: item.id, usedAmount: 0)
            XCTFail("Expected invalidUsedAmount")
        } catch {
            XCTAssertEqual(error as? RecordIngredientUseError, .invalidUsedAmount)
        }
    }

    func test_recordUse_failsWhenTheItemIsGone() async {
        let (pantry, events) = makeRepositories()
        let useCase = RecordIngredientUseUseCase(pantryRepository: pantry, eventRepository: events)

        do {
            try await useCase.execute(itemID: UUID(), usedAmount: 1)
            XCTFail("Expected itemNotFound")
        } catch {
            XCTAssertEqual(error as? RecordIngredientUseError, .itemNotFound)
        }
    }

    // MARK: - UpdateInventoryItemDetailsUseCase

    func test_updateDetails_appliesEveryEditableField() async throws {
        let item = sampleItem(name: "Milk", openedState: .unopened)
        let (pantry, events) = makeRepositories(seedItems: [item])
        let useCase = UpdateInventoryItemDetailsUseCase(pantryRepository: pantry, eventRepository: events)
        let expiry = Calendar.current.date(byAdding: .day, value: 3, to: .now)!

        try await useCase.execute(UpdateInventoryItemDetailsRequest(
            itemID: item.id,
            name: "Whole Milk",
            category: .dairy,
            storageLocation: .freezer,
            quantity: .measure(2, unit: .liters),
            expiryDate: expiry,
            openedState: .unopened,
            lowStockThreshold: 0.5
        ))

        let stored = try await pantry.fetchAll().first
        XCTAssertEqual(stored?.name, "Whole Milk")
        XCTAssertEqual(stored?.storageLocation, .freezer)
        XCTAssertEqual(stored?.quantity, 2)
        XCTAssertEqual(stored?.unit, .liters)
        XCTAssertEqual(stored?.expiryDate, expiry)
        XCTAssertEqual(stored?.lowStockThreshold, 0.5)
    }

    func test_updateDetails_allowsZero_becauseRunningOutIsARealState() async throws {
        let item = sampleItem(quantity: 1, unit: .liters)
        let (pantry, events) = makeRepositories(seedItems: [item])
        let useCase = UpdateInventoryItemDetailsUseCase(pantryRepository: pantry, eventRepository: events)

        try await useCase.execute(UpdateInventoryItemDetailsRequest(
            itemID: item.id,
            name: "Milk",
            category: .dairy,
            storageLocation: .fridge,
            quantity: .measure(0, unit: .liters),
            expiryDate: nil,
            openedState: .notApplicable,
            lowStockThreshold: nil
        ))

        let actual6 = try await pantry.fetchAll().first?.quantity
        XCTAssertEqual(actual6, 0)
    }

    func test_updateDetails_rejectsABlankedName() async {
        let item = sampleItem()
        let (pantry, events) = makeRepositories(seedItems: [item])
        let useCase = UpdateInventoryItemDetailsUseCase(pantryRepository: pantry, eventRepository: events)

        do {
            try await useCase.execute(UpdateInventoryItemDetailsRequest(
                itemID: item.id,
                name: "  ",
                category: .dairy,
                storageLocation: .fridge,
                quantity: .count(1),
                expiryDate: nil,
                openedState: .notApplicable,
                lowStockThreshold: nil
            ))
            XCTFail("Expected missingIngredientName")
        } catch {
            XCTAssertEqual(error as? UpdateInventoryItemDetailsError, .missingIngredientName)
        }
    }

    func test_updateDetails_recordsAQuantityCorrectionAsAdjusted_notUsed() throws {
        // The distinction that keeps "I fixed a typo" out of the history as
        // "I ate this".
        let item = sampleItem(quantity: 6, unit: .pieces)
        let request = UpdateInventoryItemDetailsRequest(
            itemID: item.id,
            name: item.name,
            category: .dairy,
            storageLocation: .fridge,
            quantity: .count(4),
            expiryDate: nil,
            openedState: .notApplicable,
            lowStockThreshold: nil,
            quantityWasCorrected: true
        )

        let resolved = try UpdateInventoryItemDetailsUseCase.apply(request, to: item)

        XCTAssertEqual(resolved.kind, .quantityAdjusted)
    }

    func test_updateDetails_recordsFirstOpeningAsOpened() throws {
        let item = sampleItem(openedState: .unopened)
        let request = UpdateInventoryItemDetailsRequest(
            itemID: item.id,
            name: item.name,
            category: .dairy,
            storageLocation: .fridge,
            quantity: item.inventoryQuantity,
            expiryDate: nil,
            openedState: .opened,
            lowStockThreshold: nil
        )

        let resolved = try UpdateInventoryItemDetailsUseCase.apply(request, to: item)

        XCTAssertEqual(resolved.kind, .opened)
    }

    func test_updateDetails_recordsAnythingElseAsEdited() throws {
        let item = sampleItem(name: "Milk")
        let request = UpdateInventoryItemDetailsRequest(
            itemID: item.id,
            name: "Oat Milk",
            category: .dairy,
            storageLocation: .fridge,
            quantity: item.inventoryQuantity,
            expiryDate: nil,
            openedState: .notApplicable,
            lowStockThreshold: nil
        )

        let resolved = try UpdateInventoryItemDetailsUseCase.apply(request, to: item)

        XCTAssertEqual(resolved.kind, .edited)
    }

    // MARK: - RecordFoodOutcomeUseCase

    func test_finishing_removesTheItemFromThePantry() async throws {
        // Removed rather than flagged, so recipe feasibility and
        // substitutions - which read fetchAll() and know nothing about a
        // status - cannot count food that is gone.
        let item = sampleItem(name: "Milk")
        let (pantry, events) = makeRepositories(seedItems: [item])
        let useCase = RecordFoodOutcomeUseCase(pantryRepository: pantry, eventRepository: events)

        try await useCase.execute(itemID: item.id, outcome: .finished)

        let actual7 = try await pantry.fetchAll().isEmpty
        XCTAssertTrue(actual7)
    }

    func test_finishing_keepsTheHistoryAfterTheItemIsGone() async throws {
        let item = sampleItem(name: "Milk")
        let (pantry, events) = makeRepositories(seedItems: [item])
        let useCase = RecordFoodOutcomeUseCase(pantryRepository: pantry, eventRepository: events)

        try await useCase.execute(itemID: item.id, outcome: .finished)

        let log = try await events.fetchAll(limit: 100)
        XCTAssertEqual(log.first?.kind, .finished)
        XCTAssertEqual(log.first?.itemName, "Milk")
        XCTAssertEqual(log.first?.pantryItemID, item.id)
    }

    func test_discarding_isRecordedDistinctlyFromFinishing() async throws {
        // Waste and consumption must not collapse into one bucket.
        let item = sampleItem(name: "Spinach")
        let (pantry, events) = makeRepositories(seedItems: [item])
        let useCase = RecordFoodOutcomeUseCase(pantryRepository: pantry, eventRepository: events)

        try await useCase.execute(itemID: item.id, outcome: .discarded)

        let actual8 = try await events.fetchAll(limit: 100).first?.kind
        XCTAssertEqual(actual8, .discarded)
    }

    func test_deletingARecord_isNotAFoodOutcome() async throws {
        // "This row was wrong" says nothing about the food, so it is never
        // counted as waste.
        let item = sampleItem(name: "Typo")
        let (pantry, events) = makeRepositories(seedItems: [item])
        let useCase = RecordFoodOutcomeUseCase(pantryRepository: pantry, eventRepository: events)

        try await useCase.deleteRecord(itemID: item.id)

        let actual9 = try await pantry.fetchAll().isEmpty
        XCTAssertTrue(actual9)
        let actual10 = try await events.fetchAll(limit: 100).first?.kind
        XCTAssertEqual(actual10, .deleted)
    }

    func test_outcome_failsWhenTheItemIsAlreadyGone() async {
        let (pantry, events) = makeRepositories()
        let useCase = RecordFoodOutcomeUseCase(pantryRepository: pantry, eventRepository: events)

        do {
            try await useCase.execute(itemID: UUID(), outcome: .finished)
            XCTFail("Expected itemNotFound")
        } catch {
            XCTAssertEqual(error as? RecordFoodOutcomeError, .itemNotFound)
        }
    }
}
