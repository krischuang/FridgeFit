import Foundation
import Testing
@testable import SmartFridgeApp

@MainActor
private final class InMemoryHouseholdInventoryRepository: HouseholdInventoryRepository {
    var items: [InventoryItem]
    var activities: [InventoryActivity]

    init(items: [InventoryItem] = [], activities: [InventoryActivity] = []) {
        self.items = items
        self.activities = activities
    }

    var inventoryItems: [InventoryItem] { items }
    var inventoryActivities: [InventoryActivity] { activities }

    func activeInventoryItems() -> [InventoryItem] {
        items.filter(\.isActive)
    }

    func inventoryItem(id: UUID) -> InventoryItem? {
        items.first { $0.id == id }
    }

    func saveInventoryItem(_ item: InventoryItem, activity: InventoryEventKind, note: String?, message: String?) throws {
        try saveInventoryItem(item, activities: [InventoryActivityChange(kind: activity, note: note)], message: message)
    }

    func saveInventoryItem(_ item: InventoryItem, activities changes: [InventoryActivityChange], message: String?) throws {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        activities.append(contentsOf: changes.map {
            InventoryActivity(ingredientID: item.id, ingredientName: item.name, kind: $0.kind, note: $0.note)
        })
    }

    func removeFromActiveInventory(_ item: InventoryItem, outcome: FoodOutcome) throws {
        var updated = item
        updated.status = outcome.status
        try saveInventoryItem(updated, activity: outcome.eventKind, note: nil, message: nil)
    }

    func deleteInventoryRecord(id: UUID) throws {
        items.removeAll { $0.id == id }
    }

    func activities(for itemID: UUID) -> [InventoryActivity] {
        activities.filter { $0.ingredientID == itemID }
    }
}

@MainActor
@Test func test_addInventoryItem_succeeds_whenRequiredFoodInformationIsValid() throws {
    let repository = InMemoryHouseholdInventoryRepository()
    let useCase = AddInventoryItemUseCase(repository: repository)

    let item = try useCase.execute(AddInventoryItemRequest(
        name: "Carrots",
        category: "Vegetables",
        storageLocation: .fridge,
        quantity: .measure(250, unit: .grams),
        expiryDate: nil,
        openState: .notApplicable
    ))

    #expect(repository.items == [item])
    #expect(repository.activities.map(\.kind) == [.added])
}

@MainActor
@Test func test_addInventoryItem_fails_whenIngredientNameIsEmpty() throws {
    let repository = InMemoryHouseholdInventoryRepository()
    let useCase = AddInventoryItemUseCase(repository: repository)

    #expect(throws: AddInventoryItemError.missingIngredientName) {
        try useCase.execute(AddInventoryItemRequest(
            name: "   ",
            category: "Vegetables",
            storageLocation: .fridge,
            quantity: .count(1)
        ))
    }
    #expect(repository.items.isEmpty)
}

@MainActor
@Test func test_addInventoryItem_fails_whenQuantityIsZero() throws {
    let repository = InMemoryHouseholdInventoryRepository()
    let useCase = AddInventoryItemUseCase(repository: repository)

    #expect(throws: AddInventoryItemError.invalidQuantity) {
        try useCase.execute(AddInventoryItemRequest(
            name: "Eggs",
            category: "Dairy",
            storageLocation: .fridge,
            quantity: .count(0)
        ))
    }
    #expect(repository.items.isEmpty)
}

@MainActor
@Test func test_ingredientEditorSaveAction_keepsAddFailureAsFailure() throws {
    let repository = InMemoryHouseholdInventoryRepository()
    let action = IngredientEditorSaveAction(
        mode: .add(IngredientTemplate(name: "Custom", category: .other, storageLocation: .fridge, defaultQuantity: .count(1))),
        name: " ",
        category: .other,
        storageLocation: .fridge,
        quantity: .count(1),
        expiryDate: nil,
        openedState: .notApplicable,
        lowStockThreshold: nil
    )

    #expect(throws: AddInventoryItemError.missingIngredientName) {
        try action.execute(repository: repository)
    }
    #expect(repository.items.isEmpty)
    #expect(repository.activities.isEmpty)
}

@MainActor
@Test func test_recordIngredientUse_reducesRemainingQuantity_whenUsedAmountIsValid() throws {
    let spinach = InventoryItem(name: "Spinach", category: "Vegetables", storageLocation: .fridge, quantity: .measure(150, unit: .grams))
    let repository = InMemoryHouseholdInventoryRepository(items: [spinach])

    let updated = try RecordIngredientUseUseCase(repository: repository).execute(itemID: spinach.id, usedAmount: 50)

    #expect(updated.quantity == .measure(100, unit: .grams))
    #expect(repository.activities.map(\.kind) == [.used])
}

@MainActor
@Test func test_recordIngredientUse_allowsUsingExactlyTheRemainingQuantity() throws {
    let eggs = InventoryItem(name: "Eggs", category: "Dairy", storageLocation: .fridge, quantity: .count(3))
    let repository = InMemoryHouseholdInventoryRepository(items: [eggs])

    let updated = try RecordIngredientUseUseCase(repository: repository).execute(itemID: eggs.id, usedAmount: 3)

    #expect(updated.quantity == .count(0))
    #expect(repository.activities.count == 1)
}

@MainActor
@Test func test_recordIngredientUse_fails_whenUsedAmountExceedsAvailableQuantity() throws {
    let spinach = InventoryItem(name: "Spinach", category: "Vegetables", storageLocation: .fridge, quantity: .measure(150, unit: .grams))
    let repository = InMemoryHouseholdInventoryRepository(items: [spinach])

    #expect(throws: RecordIngredientUseError.amountExceedsAvailable(available: 150, unit: "g")) {
        try RecordIngredientUseUseCase(repository: repository).execute(itemID: spinach.id, usedAmount: 200)
    }
    #expect(repository.activities.isEmpty)
}

@MainActor
@Test func test_ingredientDrawerRejectsTypedUsedAmountAboveAvailableWithoutFinishing() throws {
    let spinach = InventoryItem(name: "Spinach", category: "Vegetables", storageLocation: .fridge, quantity: .measure(150, unit: .grams))
    let repository = InMemoryHouseholdInventoryRepository(items: [spinach])
    let viewModel = IngredientDrawerViewModel(itemID: spinach.id, repository: repository)
    viewModel.load()

    viewModel.usedAmountText = "200"
    viewModel.applyTypedUsedAmount(updateText: false)
    let result = viewModel.save()

    #expect(result == .unchanged)
    #expect(viewModel.usedAmountInputIsValid == false)
    #expect(viewModel.draft?.finished == false)
    #expect(viewModel.errorMessage == "Only 150 g of Spinach is available. Enter an amount up to 150 g.")
    #expect(repository.items == [spinach])
    #expect(repository.activities.isEmpty)
}

@MainActor
@Test func test_ingredientDrawerCanSaveAfterCorrectingRejectedUsedAmount() throws {
    let spinach = InventoryItem(name: "Spinach", category: "Vegetables", storageLocation: .fridge, quantity: .measure(150, unit: .grams))
    let repository = InMemoryHouseholdInventoryRepository(items: [spinach])
    let viewModel = IngredientDrawerViewModel(itemID: spinach.id, repository: repository)
    viewModel.load()

    viewModel.usedAmountText = "200"
    viewModel.applyTypedUsedAmount(updateText: false)
    _ = viewModel.save()

    viewModel.usedAmountText = "50"
    viewModel.applyTypedUsedAmount(updateText: false)
    let result = viewModel.save()

    let updated = try #require(repository.items.first { $0.id == spinach.id })
    #expect(result == .saved)
    #expect(viewModel.usedAmountInputIsValid)
    #expect(viewModel.errorMessage == nil)
    #expect(updated.quantity == .measure(100, unit: .grams))
    #expect(repository.activities.map(\.kind) == [.used])
}

@MainActor
@Test func test_ingredientDrawerRefusesSave_whenTypedAmountInvalidAfterValidDraftAmount() throws {
    let spinach = InventoryItem(name: "Spinach", category: "Vegetables", storageLocation: .fridge, quantity: .measure(150, unit: .grams))
    let repository = InMemoryHouseholdInventoryRepository(items: [spinach])
    let viewModel = IngredientDrawerViewModel(itemID: spinach.id, repository: repository)
    viewModel.load()

    viewModel.usedAmountText = "50"
    viewModel.applyTypedUsedAmount(updateText: false)
    viewModel.usedAmountText = "200"
    viewModel.applyTypedUsedAmount(updateText: false)
    let result = viewModel.save()

    #expect(result == .unchanged)
    #expect(viewModel.usedAmountInputIsValid == false)
    #expect(viewModel.errorMessage == "Only 150 g of Spinach is available. Enter an amount up to 150 g.")
    #expect(repository.items == [spinach])
    #expect(repository.activities.isEmpty)
}

@MainActor
@Test func test_ingredientDrawerDoesNotPersistDetailEdits_whenCombinedUsageIsIncompatible() throws {
    let rice = InventoryItem(name: "Rice", category: "Pantry", storageLocation: .pantry, quantity: .presence(.available))
    let repository = InMemoryHouseholdInventoryRepository(items: [rice])
    let viewModel = IngredientDrawerViewModel(itemID: rice.id, repository: repository)
    viewModel.load()

    viewModel.updateDraft { $0.name = "Brown Rice" }
    viewModel.usedAmountText = "0.5"
    viewModel.applyTypedUsedAmount(updateText: false)
    let result = viewModel.save()

    #expect(result == .unchanged)
    #expect(viewModel.errorMessage == RecordIngredientUseError.incompatibleUnit.errorDescription)
    #expect(repository.items == [rice])
    #expect(repository.activities.isEmpty)
}

@MainActor
@Test func test_ingredientDrawerRecordsUsedActivityWhenSavingUsedAmountWithDetailEdits() throws {
    let spinach = InventoryItem(name: "Spinach", category: "Vegetables", storageLocation: .fridge, quantity: .measure(150, unit: .grams))
    let repository = InMemoryHouseholdInventoryRepository(items: [spinach])
    let viewModel = IngredientDrawerViewModel(itemID: spinach.id, repository: repository)
    viewModel.load()

    viewModel.updateDraft { $0.name = "Baby Spinach" }
    viewModel.usedAmountText = "50"
    viewModel.applyTypedUsedAmount(updateText: false)
    let result = viewModel.save()

    let updated = try #require(repository.items.first { $0.id == spinach.id })
    #expect(result == .saved)
    #expect(updated.name == "Baby Spinach")
    #expect(updated.quantity == .measure(100, unit: .grams))
    #expect(repository.activities.map(\.kind) == [.edited, .used])
}

@MainActor
@Test func test_ingredientDrawerCombinedSaveKeepsCorrectRemainingQuantity() throws {
    let spinach = InventoryItem(name: "Spinach", category: "Vegetables", storageLocation: .fridge, quantity: .measure(150, unit: .grams))
    let repository = InMemoryHouseholdInventoryRepository(items: [spinach])
    let viewModel = IngredientDrawerViewModel(itemID: spinach.id, repository: repository)
    viewModel.load()

    viewModel.updateDraft { $0.storageLocation = .freezer }
    viewModel.usedAmountText = "50"
    viewModel.applyTypedUsedAmount(updateText: false)
    let result = viewModel.save()

    let updated = try #require(repository.items.first { $0.id == spinach.id })
    #expect(result == .saved)
    #expect(updated.storageLocation == .freezer)
    #expect(updated.quantity == .measure(100, unit: .grams))
}

@MainActor
@Test func test_ingredientDrawerCombinedSaveCreatesExactlyOneUsedActivity() throws {
    let spinach = InventoryItem(name: "Spinach", category: "Vegetables", storageLocation: .fridge, quantity: .measure(150, unit: .grams))
    let repository = InMemoryHouseholdInventoryRepository(items: [spinach])
    let viewModel = IngredientDrawerViewModel(itemID: spinach.id, repository: repository)
    viewModel.load()

    viewModel.updateDraft { $0.name = "Baby Spinach" }
    viewModel.usedAmountText = "50"
    viewModel.applyTypedUsedAmount(updateText: false)
    let result = viewModel.save()

    #expect(result == .saved)
    #expect(repository.activities.filter { $0.kind == .used }.count == 1)
    #expect(repository.activities.map(\.kind) == [.edited, .used])
}

@MainActor
@Test func test_recordIngredientUse_fails_whenUsedAmountIsZero() throws {
    let milk = InventoryItem(name: "Milk", category: "Dairy", storageLocation: .fridge, quantity: .measure(1, unit: .litres))
    let repository = InMemoryHouseholdInventoryRepository(items: [milk])

    #expect(throws: RecordIngredientUseError.invalidUsedAmount) {
        try RecordIngredientUseUseCase(repository: repository).execute(itemID: milk.id, usedAmount: 0)
    }
    #expect(repository.activities.isEmpty)
}

@MainActor
@Test func test_updateInventoryItemDetails_succeeds_whenDetailsAreValid() throws {
    let milk = InventoryItem(
        name: "Milk",
        category: "Dairy",
        storageLocation: .fridge,
        quantity: .measure(1, unit: .litres),
        openedState: .unopened
    )
    let repository = InMemoryHouseholdInventoryRepository(items: [milk])

    let updated = try UpdateInventoryItemDetailsUseCase(repository: repository).execute(
        UpdateInventoryItemDetailsRequest(
            itemID: milk.id,
            name: "Oat Milk",
            category: "Dairy Alternative",
            storageLocation: .fridge,
            quantity: .measure(750, unit: .millilitres),
            expiryDate: milk.expiryDate,
            openState: .opened,
            lowStockThreshold: milk.lowStockThreshold
        )
    )

    #expect(updated.name == "Oat Milk")
    #expect(updated.quantity == .measure(750, unit: .millilitres))
    #expect(repository.activities.map(\.kind) == [.opened])
}

@MainActor
@Test func test_updateInventoryItemDetails_fails_whenNameIsBlank() throws {
    let milk = InventoryItem(name: "Milk", category: "Dairy", storageLocation: .fridge, quantity: .measure(1, unit: .litres))
    let repository = InMemoryHouseholdInventoryRepository(items: [milk])

    #expect(throws: UpdateInventoryItemDetailsError.missingIngredientName) {
        try UpdateInventoryItemDetailsUseCase(repository: repository).execute(
            UpdateInventoryItemDetailsRequest(
                itemID: milk.id,
                name: " ",
                category: milk.category,
                storageLocation: milk.storageLocation,
                quantity: milk.quantity,
                expiryDate: milk.expiryDate,
                openState: milk.openedState,
                lowStockThreshold: milk.lowStockThreshold
            )
        )
    }
    #expect(repository.activities.isEmpty)
}

@MainActor
@Test func test_recordFoodOutcome_removesItemFromActiveInventory_whenFinished() throws {
    let cheese = InventoryItem(name: "Cheese", category: "Dairy", storageLocation: .fridge, quantity: .package(count: 1, unit: .block, level: .half))
    let repository = InMemoryHouseholdInventoryRepository(items: [cheese])

    try RecordFoodOutcomeUseCase(repository: repository).execute(itemID: cheese.id, outcome: .finished)

    #expect(repository.activeInventoryItems().isEmpty)
    #expect(repository.activities.map(\.kind) == [.finished])
}

@MainActor
@Test func test_recordFoodOutcome_recordsDiscardedActivity_whenFoodIsDiscarded() throws {
    let tomato = InventoryItem(name: "Tomato", category: "Vegetables", storageLocation: .fridge, quantity: .count(2))
    let repository = InMemoryHouseholdInventoryRepository(items: [tomato])

    try RecordFoodOutcomeUseCase(repository: repository).execute(itemID: tomato.id, outcome: .discarded)

    #expect(repository.activeInventoryItems().isEmpty)
    #expect(repository.activities.map(\.kind) == [.discarded])
}

@MainActor
@Test func test_recordFoodOutcome_fails_whenItemDoesNotExist() throws {
    let repository = InMemoryHouseholdInventoryRepository()

    #expect(throws: RecordFoodOutcomeError.itemNotFound) {
        try RecordFoodOutcomeUseCase(repository: repository).execute(itemID: UUID(), outcome: .finished)
    }
    #expect(repository.activities.isEmpty)
}

@MainActor
@Test func test_identifyExpiringInventory_includesFoodExpiringToday() throws {
    let now = Date(timeIntervalSince1970: 1_777_766_400)
    let item = InventoryItem(name: "Yoghurt", category: "Dairy", storageLocation: .fridge, quantity: .count(1), expiryDate: now)
    let repository = InMemoryHouseholdInventoryRepository(items: [item])

    let expiring = IdentifyExpiringInventoryUseCase(repository: repository, now: now).execute()

    #expect(expiring.map(\.id) == [item.id])
}

@MainActor
@Test func test_identifyExpiringInventory_includesFoodExpiringTomorrow() throws {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 1_777_766_400)
    let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))
    let item = InventoryItem(name: "Milk", category: "Dairy", storageLocation: .fridge, quantity: .measure(1, unit: .litres), expiryDate: tomorrow)
    let repository = InMemoryHouseholdInventoryRepository(items: [item])

    let expiring = IdentifyExpiringInventoryUseCase(repository: repository, now: now, calendar: calendar).execute()

    #expect(expiring.map(\.id) == [item.id])
}

@MainActor
@Test func test_identifyExpiringInventory_excludesFoodWithoutExpiryDate() throws {
    let rice = InventoryItem(name: "Rice", category: "Pantry", storageLocation: .pantry, quantity: .presence(.available), expiryDate: nil)
    let repository = InMemoryHouseholdInventoryRepository(items: [rice])

    let expiring = IdentifyExpiringInventoryUseCase(repository: repository).execute()

    #expect(expiring.isEmpty)
}

@MainActor
@Test func test_identifyExpiringInventory_excludesFoodBeyondUseFirstWindow() throws {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 1_777_766_400)
    let later = try #require(calendar.date(byAdding: .day, value: 4, to: now))
    let cheese = InventoryItem(name: "Cheese", category: "Dairy", storageLocation: .fridge, quantity: .count(1), expiryDate: later)
    let repository = InMemoryHouseholdInventoryRepository(items: [cheese])

    let expiring = IdentifyExpiringInventoryUseCase(repository: repository, now: now, calendar: calendar).execute()

    #expect(expiring.isEmpty)
}

@MainActor
@Test func test_identifyExpiringInventory_includesFoodOnUseFirstBoundary() throws {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 1_777_766_400)
    let boundary = try #require(calendar.date(byAdding: .day, value: 3, to: now))
    let chicken = InventoryItem(name: "Chicken", category: "Meat", storageLocation: .fridge, quantity: .measure(500, unit: .grams), expiryDate: boundary)
    let repository = InMemoryHouseholdInventoryRepository(items: [chicken])

    let expiring = IdentifyExpiringInventoryUseCase(repository: repository, now: now, calendar: calendar).execute()

    #expect(expiring.map(\.id) == [chicken.id])
}
