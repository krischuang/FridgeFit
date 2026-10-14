import Foundation
import Testing
@testable import SmartFridgeApp

private enum TestPersistenceError: Error {
    case loadFailed
    case saveFailed
}

private final class FailingInventoryPersistence: InventoryPersisting, @unchecked Sendable {
    var snapshot: InventorySnapshot?
    var loadError: Error?
    var saveError: Error?
    var saveErrorOnAttempt: Int?
    private(set) var saveAttempts = 0
    private(set) var savedSnapshots: [InventorySnapshot] = []

    init(snapshot: InventorySnapshot? = nil, loadError: Error? = nil, saveError: Error? = nil, saveErrorOnAttempt: Int? = nil) {
        self.snapshot = snapshot
        self.loadError = loadError
        self.saveError = saveError
        self.saveErrorOnAttempt = saveErrorOnAttempt
    }

    func load() throws -> InventorySnapshot? {
        if let loadError {
            throw loadError
        }
        return snapshot
    }

    func save(_ snapshot: InventorySnapshot) throws {
        saveAttempts += 1
        if saveErrorOnAttempt == saveAttempts {
            throw TestPersistenceError.saveFailed
        }
        if let saveError {
            throw saveError
        }
        self.snapshot = snapshot
        savedSnapshots.append(snapshot)
    }
}

private final class CorruptedFileLoadFailurePersistence: InventoryPersisting, @unchecked Sendable {
    let fileURL: URL
    private(set) var saveAttempts = 0

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() throws -> InventorySnapshot? {
        _ = try Data(contentsOf: fileURL)
        throw TestPersistenceError.loadFailed
    }

    func save(_ snapshot: InventorySnapshot) throws {
        saveAttempts += 1
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }
}

@MainActor
@Test func useSoonSortsByExpiryUrgency() {
    let now = Date(timeIntervalSince1970: 1_775_548_800)
    let service = InventoryService(persistence: nil, seedIfEmpty: true, now: now)

    let soon = service.useSoonIngredients()

    #expect(soon.map(\.name).prefix(3) == ["Spinach", "Milk", "Chicken Breast"])
}

@MainActor
@Test func myKitchenViewModelPresentsUseFirstThroughUseCase() {
    let now = Date(timeIntervalSince1970: 1_775_548_800)
    let service = InventoryService(persistence: nil, seedIfEmpty: true, now: now)
    let viewModel = MyKitchenViewModel(inventory: service)

    let useFirst = viewModel.useFirstIngredients

    #expect(useFirst.map(\.name).prefix(3) == ["Spinach", "Milk", "Chicken Breast"])
}

@MainActor
@Test func filteringSearchesNameAndCategory() {
    let service = InventoryService(persistence: nil, seedIfEmpty: true)

    let dairy = service.filteredIngredients(searchText: "dairy", filter: .fridge)

    #expect(dairy.map(\.name).contains("Milk"))
    #expect(dairy.allSatisfy { $0.storageLocation == .fridge })
}

@Test func foodCategoryDecodesLegacyPersistedLabels() throws {
    let decoder = JSONDecoder()

    let vegetables = try decoder.decode(FoodCategory.self, from: Data(#""Vegetables""#.utf8))
    let meat = try decoder.decode(FoodCategory.self, from: Data(#""Meat""#.utf8))
    let grains = try decoder.decode(FoodCategory.self, from: Data(#""Grains""#.utf8))

    #expect(vegetables == .vegetables)
    #expect(meat == .meatAndFish)
    #expect(grains == .pantry)
}

@MainActor
@Test func missingPersistenceFileSeedsAndCanReloadPersistedState() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("SmartFridge-Missing-\(UUID().uuidString).json")
    let persistence = JSONInventoryPersistence(fileURL: fileURL)

    let service = InventoryService(persistence: persistence, seedIfEmpty: true)

    #expect(service.ingredients.isEmpty == false)
    #expect(service.events.isEmpty == false)
    #expect(service.loadErrorMessage == nil)

    let reloaded = InventoryService(persistence: persistence, seedIfEmpty: false)
    #expect(reloaded.ingredients.map(\.name) == service.ingredients.map(\.name))
    #expect(reloaded.events.map(\.kind) == service.events.map(\.kind))
}

@MainActor
@Test func corruptedJSONDoesNotSeedOrOverwriteSavedBytes() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("SmartFridge-Corrupt-\(UUID().uuidString).json")
    let corruptedBytes = Data("not valid json".utf8)
    try corruptedBytes.write(to: fileURL)
    let persistence = JSONInventoryPersistence(fileURL: fileURL)

    let service = InventoryService(persistence: persistence, seedIfEmpty: true)

    #expect(service.ingredients.isEmpty)
    #expect(service.events.isEmpty)
    #expect(service.loadErrorMessage == InventoryServiceError.persistenceLoadFailed.errorDescription)
    #expect(try Data(contentsOf: fileURL) == corruptedBytes)
}

@MainActor
@Test func writeAttemptAfterLoadFailure_isBlockedAndDoesNotOverwritePersistence() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("SmartFridge-Blocked-\(UUID().uuidString).json")
    let corruptedBytes = Data("still not valid json".utf8)
    try corruptedBytes.write(to: fileURL)
    let persistence = CorruptedFileLoadFailurePersistence(fileURL: fileURL)
    let service = InventoryService(persistence: persistence, seedIfEmpty: true)
    let useCase = AddInventoryItemUseCase(repository: service)

    #expect(throws: InventoryServiceError.persistenceLoadFailed) {
        try useCase.execute(AddInventoryItemRequest(
            name: "Carrots",
            category: .vegetables,
            storageLocation: .fridge,
            quantity: .measure(250, unit: .grams)
        ))
    }
    #expect(persistence.saveAttempts == 0)
    #expect(try Data(contentsOf: fileURL) == corruptedBytes)
    #expect(service.ingredients.isEmpty)
    #expect(service.events.isEmpty)
    #expect(service.lastMessage == nil)
}

@MainActor
@Test func seedSaveFailure_doesNotPublishSeededInventory() {
    let persistence = FailingInventoryPersistence(saveError: TestPersistenceError.saveFailed)

    let service = InventoryService(persistence: persistence, seedIfEmpty: true)

    #expect(persistence.saveAttempts == 1)
    #expect(service.ingredients.isEmpty)
    #expect(service.events.isEmpty)
    #expect(service.loadErrorMessage == InventoryServiceError.persistenceSaveFailed.errorDescription)
    #expect(service.lastMessage == nil)
}

@MainActor
@Test func batchDeductionsAdjustExactQuantities() throws {
    let service = InventoryService(persistence: nil, seedIfEmpty: false)
    let chicken = Ingredient(
        name: "Chicken Breast",
        category: "Meat",
        storageLocation: .fridge,
        quantity: .measure(500, unit: .grams)
    )
    try service.upsert(chicken, event: .added)

    try service.applyDeductions([
        IngredientConsumption(ingredientID: chicken.id, amount: 200)
    ])

    let updated = try #require(service.ingredients.first { $0.id == chicken.id })
    #expect(updated.quantity == .measure(300, unit: .grams))
}

@MainActor
@Test func addInventoryItemDoesNotCommit_whenPersistenceSaveFails() throws {
    let persistence = FailingInventoryPersistence(saveError: TestPersistenceError.saveFailed)
    let service = InventoryService(persistence: persistence, seedIfEmpty: false)
    let useCase = AddInventoryItemUseCase(repository: service)

    #expect(throws: InventoryServiceError.persistenceSaveFailed) {
        try useCase.execute(AddInventoryItemRequest(
            name: "Carrots",
            category: .vegetables,
            storageLocation: .fridge,
            quantity: .measure(250, unit: .grams)
        ))
    }
    #expect(service.ingredients.isEmpty)
    #expect(service.events.isEmpty)
    #expect(service.lastMessage == nil)
}

@MainActor
@Test func recordUsageDoesNotCommit_whenPersistenceSaveFails() throws {
    let spinach = Ingredient(name: "Spinach", category: .vegetables, storageLocation: .fridge, quantity: .measure(150, unit: .grams))
    let persistence = FailingInventoryPersistence(
        snapshot: InventorySnapshot(ingredients: [spinach], events: []),
        saveError: TestPersistenceError.saveFailed
    )
    let service = InventoryService(persistence: persistence, seedIfEmpty: false)
    let useCase = RecordIngredientUseUseCase(repository: service)

    #expect(throws: InventoryServiceError.persistenceSaveFailed) {
        try useCase.execute(itemID: spinach.id, usedAmount: 50)
    }
    #expect(service.ingredients == [spinach])
    #expect(service.events.isEmpty)
    #expect(service.lastMessage == nil)
}

@MainActor
@Test func updateDetailsDoesNotCommit_whenPersistenceSaveFails() throws {
    let milk = Ingredient(name: "Milk", category: .dairy, storageLocation: .fridge, quantity: .measure(1, unit: .litres))
    let persistence = FailingInventoryPersistence(
        snapshot: InventorySnapshot(ingredients: [milk], events: []),
        saveError: TestPersistenceError.saveFailed
    )
    let service = InventoryService(persistence: persistence, seedIfEmpty: false)
    let useCase = UpdateInventoryItemDetailsUseCase(repository: service)

    #expect(throws: InventoryServiceError.persistenceSaveFailed) {
        try useCase.execute(UpdateInventoryItemDetailsRequest(
            itemID: milk.id,
            name: "Oat Milk",
            category: .dairy,
            storageLocation: .fridge,
            quantity: .measure(750, unit: .millilitres),
            expiryDate: nil,
            openState: .notApplicable,
            lowStockThreshold: nil
        ))
    }
    #expect(service.ingredients == [milk])
    #expect(service.events.isEmpty)
    #expect(service.lastMessage == nil)
}

@MainActor
@Test func foodOutcomeDoesNotCommit_whenPersistenceSaveFails() throws {
    let cheese = Ingredient(name: "Cheese", category: .dairy, storageLocation: .fridge, quantity: .package(count: 1, unit: .block, level: .half))
    let persistence = FailingInventoryPersistence(
        snapshot: InventorySnapshot(ingredients: [cheese], events: []),
        saveError: TestPersistenceError.saveFailed
    )
    let service = InventoryService(persistence: persistence, seedIfEmpty: false)
    let useCase = RecordFoodOutcomeUseCase(repository: service)

    #expect(throws: InventoryServiceError.persistenceSaveFailed) {
        try useCase.execute(itemID: cheese.id, outcome: .finished)
    }
    #expect(service.ingredients == [cheese])
    #expect(service.activeIngredients == [cheese])
    #expect(service.events.isEmpty)
    #expect(service.lastMessage == nil)
}

@MainActor
@Test func combinedDetailAndUsageSave_isAtomic_whenPersistenceFails() throws {
    let spinach = Ingredient(name: "Spinach", category: .vegetables, storageLocation: .fridge, quantity: .measure(150, unit: .grams))
    let persistence = FailingInventoryPersistence(
        snapshot: InventorySnapshot(ingredients: [spinach], events: []),
        saveErrorOnAttempt: 1
    )
    let service = InventoryService(persistence: persistence, seedIfEmpty: false)
    let viewModel = IngredientDrawerViewModel(itemID: spinach.id, repository: service)
    viewModel.load()

    viewModel.updateDraft { $0.name = "Baby Spinach" }
    viewModel.usedAmountText = "50"
    viewModel.applyTypedUsedAmount(updateText: false)
    let result = viewModel.save()

    #expect(result == .unchanged)
    #expect(persistence.saveAttempts == 1)
    #expect(service.ingredients == [spinach])
    #expect(service.events.isEmpty)
    #expect(service.lastMessage == nil)
}

@MainActor
@Test func combinedDetailAndUsageSave_persistsWithSingleWrite() throws {
    let spinach = Ingredient(name: "Spinach", category: .vegetables, storageLocation: .fridge, quantity: .measure(150, unit: .grams))
    let persistence = FailingInventoryPersistence(snapshot: InventorySnapshot(ingredients: [spinach], events: []))
    let service = InventoryService(persistence: persistence, seedIfEmpty: false)
    let viewModel = IngredientDrawerViewModel(itemID: spinach.id, repository: service)
    viewModel.load()

    viewModel.updateDraft { $0.name = "Baby Spinach" }
    viewModel.usedAmountText = "50"
    viewModel.applyTypedUsedAmount(updateText: false)
    let result = viewModel.save()

    let updated = try #require(service.ingredients.first { $0.id == spinach.id })
    #expect(result == .saved)
    #expect(persistence.saveAttempts == 1)
    #expect(updated.name == "Baby Spinach")
    #expect(updated.quantity == .measure(100, unit: .grams))
    #expect(service.events.map(\.kind) == [.edited, .used])
    #expect(service.events.filter { $0.kind == .used }.count == 1)
}

@MainActor
@Test func test_combinedDetailAndUsageSave_undoRestoresOriginalItemAndRemovesAllActivities() throws {
    let spinach = Ingredient(name: "Spinach", category: .vegetables, storageLocation: .fridge, quantity: .measure(150, unit: .grams))
    let service = InventoryService(
        persistence: FailingInventoryPersistence(snapshot: InventorySnapshot(ingredients: [spinach], events: [])),
        seedIfEmpty: false
    )
    let viewModel = IngredientDrawerViewModel(itemID: spinach.id, repository: service)
    viewModel.load()

    viewModel.updateDraft { $0.name = "Baby Spinach" }
    viewModel.usedAmountText = "50"
    viewModel.applyTypedUsedAmount(updateText: false)
    let saveResult = viewModel.save()

    #expect(saveResult == .saved)
    #expect(service.events.map(\.kind) == [.edited, .used])
    #expect(service.events.filter { $0.kind == .used }.count == 1)

    try service.undoLastAction()

    #expect(service.ingredients == [spinach])
    #expect(service.events.isEmpty)
    #expect(service.canUndoLastAction == false)
}

@MainActor
@Test func drawerSaveCommitsFinalUsedAmountOnce() throws {
    let service = InventoryService(persistence: nil, seedIfEmpty: false)
    let spinach = Ingredient(
        name: "Spinach",
        category: "Vegetables",
        storageLocation: .fridge,
        quantity: .measure(100, unit: .grams)
    )
    try service.upsert(spinach, event: .added)

    var final = spinach
    final.quantity = .measure(50, unit: .grams)
    try service.saveIngredient(final, event: .used, note: "Used 50 g", message: "Used 50 g")

    let updated = try #require(service.ingredients.first { $0.id == spinach.id })
    let usedEvents = service.history(for: spinach.id).filter { $0.kind == .used }
    #expect(updated.quantity == .measure(50, unit: .grams))
    #expect(usedEvents.count == 1)
    #expect(usedEvents.first?.note == "Used 50 g")
}

@MainActor
@Test func drawerSavedChangePersistsAfterReload() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("SmartFridge-\(UUID().uuidString).json")
    let persistence = JSONInventoryPersistence(fileURL: fileURL)
    let service = InventoryService(persistence: persistence, seedIfEmpty: false)
    let spinach = Ingredient(
        name: "Spinach",
        category: "Vegetables",
        storageLocation: .fridge,
        quantity: .measure(100, unit: .grams)
    )
    try service.upsert(spinach, event: .added)

    var final = spinach
    final.quantity = .measure(50, unit: .grams)
    try service.saveIngredient(final, event: .used, note: "Used 50 g", message: "Used 50 g")

    let reloaded = InventoryService(persistence: persistence, seedIfEmpty: false)
    let updated = try #require(reloaded.ingredients.first { $0.id == spinach.id })
    let usedEvents = reloaded.history(for: spinach.id).filter { $0.kind == .used }
    #expect(updated.quantity == .measure(50, unit: .grams))
    #expect(usedEvents.count == 1)
}

@MainActor
@Test func finishedItemsLeaveActiveInventoryButRemainInHistory() throws {
    let service = InventoryService(persistence: nil, seedIfEmpty: false)
    let milk = Ingredient(
        name: "Milk",
        category: "Dairy",
        storageLocation: .fridge,
        quantity: .package(count: 1, unit: .bottle, level: .half)
    )
    try service.upsert(milk, event: .added)

    try service.markFinished(milk.id)

    #expect(service.activeIngredients.isEmpty)
    #expect(service.history(for: milk.id).contains { $0.kind == .finished })
}

@MainActor
@Test func drawerFinishedSaveCreatesOnlyFinishedEvent() throws {
    let service = InventoryService(persistence: nil, seedIfEmpty: false)
    let milk = Ingredient(
        name: "Milk",
        category: "Dairy",
        storageLocation: .fridge,
        quantity: .package(count: 1, unit: .bottle, level: .full)
    )
    try service.upsert(milk, event: .added)

    var final = milk
    final.quantity = .package(count: 0, unit: .bottle, level: .almostEmpty)
    final.status = .finished
    try service.finishIngredient(final)

    let events = service.history(for: milk.id)
    #expect(service.activeIngredients.isEmpty)
    #expect(events.filter { $0.kind == .finished }.count == 1)
    #expect(events.contains { $0.kind == .used } == false)
}

@MainActor
@Test func undoPersistenceFailure_doesNotChangeMemoryOrUndoState() throws {
    let milk = Ingredient(name: "Milk", category: .dairy, storageLocation: .fridge, quantity: .measure(1, unit: .litres))
    let persistence = FailingInventoryPersistence(snapshot: InventorySnapshot(ingredients: [milk], events: []))
    let service = InventoryService(persistence: persistence, seedIfEmpty: false)
    try service.markFinished(milk.id)
    let finishedIngredients = service.ingredients
    let finishedEvents = service.events
    persistence.saveError = TestPersistenceError.saveFailed

    #expect(throws: InventoryServiceError.persistenceSaveFailed) {
        try service.undoLastAction()
    }
    #expect(service.ingredients == finishedIngredients)
    #expect(service.events == finishedEvents)
    #expect(service.canUndoLastAction)
    #expect(service.lastMessage == "Milk finished")
}
