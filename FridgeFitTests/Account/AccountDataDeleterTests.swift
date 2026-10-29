//
//  AccountDataDeleterTests.swift
//  FridgeFitTests
//
//  The stores' side of account deletion.
//
//  The scoping cases here are the important ones. A local database has no
//  `users/{uid}` path, so the `ownerID` predicate is the *entire* safety
//  boundary - a `delete(model:)` without one compiles, passes a
//  "did it delete the data?" test, and quietly wipes every account that has
//  ever signed in on the device. So each one is checked by asserting on the
//  *other* account's rows, not just on the deleted one's.
//

import SwiftData
import XCTest
@testable import FridgeFit

@MainActor
final class SwiftDataAccountDataDeleterTests: XCTestCase {

    private var container: PersistenceContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try PersistenceContainer(storage: .inMemory)
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    private func makeDeleter() -> SwiftDataAccountDataDeleter {
        SwiftDataAccountDataDeleter(
            context: container.mainContext,
            savedRecipeContext: ModelContext(container.modelContainer)
        )
    }

    private func pantryRepository(owner: String) -> SwiftDataPantryRepository {
        SwiftDataPantryRepository(context: container.mainContext, ownerIDProvider: { owner })
    }

    private func eventRepository(owner: String) -> SwiftDataInventoryEventRepository {
        SwiftDataInventoryEventRepository(context: container.mainContext, ownerIDProvider: { owner })
    }

    private func item(_ name: String) -> PantryItem {
        PantryItem(ingredient: Ingredient(name: name, category: .other), quantity: 1, unit: .pieces)
    }

    // MARK: - It deletes what it should

    func test_deleteAllData_removesThatAccountsPantryAndEvents() async throws {
        let pantry = pantryRepository(owner: "alice")
        let events = eventRepository(owner: "alice")
        let milk = item("Milk")
        try await pantry.add(milk)
        try await events.append(
            InventoryEvent(pantryItemID: milk.id, itemName: "Milk", kind: .added)
        )

        try await makeDeleter().deleteAllData(ownedBy: "alice")

        let remainingItems = try await pantry.fetchAll()
        let remainingEvents = try await events.fetchAll(limit: 100)
        XCTAssertTrue(remainingItems.isEmpty)
        XCTAssertTrue(remainingEvents.isEmpty)
    }

    func test_deleteAllData_removesThatAccountsFundsData() async throws {
        let budgets = SwiftDataBudgetStore(context: container.mainContext, ownerIDProvider: { "alice" })
        let prices = SwiftDataItemPriceStore(context: container.mainContext, ownerIDProvider: { "alice" })
        let book = SwiftDataPriceBookStore(context: container.mainContext, ownerIDProvider: { "alice" })

        try await budgets.saveBudget(FoodBudget(limit: aud(100), cadence: .weekly, startDate: TestDates.anchor))
        try await budgets.addSpend(GrocerySpend(amount: aud(10), spentOn: TestDates.anchor))
        try await budgets.addWasteCost(
            WastedFoodCost(
                pantryItemID: PantryItemID("i"),
                quantityDiscarded: 1,
                lostAmount: aud(1),
                discardedOn: TestDates.anchor,
                reason: .expired
            )
        )
        try await prices.save(ItemPriceInfo(pantryItemID: PantryItemID("i"), unitCost: aud(3)))
        try await book.record(
            PriceBookEntry(displayName: "Milk", unitCost: aud(2), unit: "L", recordedOn: TestDates.anchor)
        )

        try await makeDeleter().deleteAllData(ownedBy: "alice")

        let reread = SwiftDataBudgetStore(context: container.mainContext, ownerIDProvider: { "alice" })
        let rereadPrices = SwiftDataItemPriceStore(context: container.mainContext, ownerIDProvider: { "alice" })
        let rereadBook = SwiftDataPriceBookStore(context: container.mainContext, ownerIDProvider: { "alice" })
        try await reread.load()
        try await rereadPrices.load()
        try await rereadBook.load()

        XCTAssertNil(reread.activeBudget())
        XCTAssertTrue(reread.allSpends().isEmpty)
        XCTAssertTrue(reread.allWasteCosts().isEmpty)
        XCTAssertNil(rereadPrices.info(for: PantryItemID("i")))
        XCTAssertNil(rereadBook.entry(forIngredientNamed: "Milk"))
    }

    /// Saved recipes cascade to their ingredient lines, so deleting the
    /// recipes must leave no orphaned rows behind.
    func test_deleteAllData_removesSavedRecipesAndTheirIngredientLines() async throws {
        let store = SwiftDataSavedRecipeStore(
            container: container.modelContainer,
            ownerIDProvider: { "alice" }
        )
        let repository = SwiftDataSavedRecipeRepository(store: store)
        let recipe = Recipe(
            title: "Tomato Soup",
            summary: "Warm",
            ingredients: [
                RecipeIngredient(
                    ingredient: Ingredient(name: "Tomato", category: .produce),
                    quantity: 4,
                    unit: .pieces,
                    role: .essential
                ),
                RecipeIngredient(
                    ingredient: Ingredient(name: "Salt", category: .spice),
                    quantity: 1,
                    unit: .teaspoons,
                    role: .optional
                ),
            ],
            instructions: ["Simmer."]
        )
        try await repository.save(recipe, sourceRecipeID: 42)

        try await makeDeleter().deleteAllData(ownedBy: "alice")

        let remainingRecipes = try await repository.fetchAll()
        XCTAssertTrue(remainingRecipes.isEmpty)

        let orphanedLines = try container.mainContext.fetch(FetchDescriptor<SavedRecipeIngredientEntity>())
        XCTAssertTrue(orphanedLines.isEmpty, "Ingredient lines must cascade with their recipe")
    }

    // MARK: - It must not delete anybody else's

    /// The one that matters. Two accounts on one device: deleting Alice must
    /// leave Bob's kitchen exactly as it was.
    func test_deleteAllData_leavesAnotherAccountsPantryUntouched() async throws {
        let alice = pantryRepository(owner: "alice")
        let bob = pantryRepository(owner: "bob")
        try await alice.add(item("Alice Milk"))
        try await bob.add(item("Bob Eggs"))
        try await bob.add(item("Bob Rice"))

        try await makeDeleter().deleteAllData(ownedBy: "alice")

        let alicesItems = try await alice.fetchAll()
        XCTAssertTrue(alicesItems.isEmpty)
        let bobsItems = try await bob.fetchAll().map(\.name).sorted()
        XCTAssertEqual(bobsItems, ["Bob Eggs", "Bob Rice"], "Bob's pantry must survive Alice's deletion")
    }

    func test_deleteAllData_leavesAnotherAccountsEventsUntouched() async throws {
        let aliceEvents = eventRepository(owner: "alice")
        let bobEvents = eventRepository(owner: "bob")
        try await aliceEvents.append(InventoryEvent(pantryItemID: UUID(), itemName: "Alice Milk", kind: .finished))
        try await bobEvents.append(InventoryEvent(pantryItemID: UUID(), itemName: "Bob Eggs", kind: .finished))

        try await makeDeleter().deleteAllData(ownedBy: "alice")

        let alicesEvents = try await aliceEvents.fetchAll(limit: 100)
        let bobsEvents = try await bobEvents.fetchAll(limit: 100)
        XCTAssertTrue(alicesEvents.isEmpty)
        XCTAssertEqual(bobsEvents.map(\.itemName), ["Bob Eggs"])
    }

    func test_deleteAllData_leavesAnotherAccountsMoneyUntouched() async throws {
        let aliceBudgets = SwiftDataBudgetStore(context: container.mainContext, ownerIDProvider: { "alice" })
        let bobBudgets = SwiftDataBudgetStore(context: container.mainContext, ownerIDProvider: { "bob" })
        try await aliceBudgets.saveBudget(FoodBudget(limit: aud(320), cadence: .weekly, startDate: TestDates.anchor))
        try await bobBudgets.saveBudget(FoodBudget(limit: aud(90), cadence: .weekly, startDate: TestDates.anchor))

        try await makeDeleter().deleteAllData(ownedBy: "alice")

        let bob = SwiftDataBudgetStore(context: container.mainContext, ownerIDProvider: { "bob" })
        try await bob.load()
        XCTAssertEqual(bob.activeBudget()?.limit, aud(90), "Bob's budget must survive")

        let alice = SwiftDataBudgetStore(context: container.mainContext, ownerIDProvider: { "alice" })
        try await alice.load()
        XCTAssertNil(alice.activeBudget())
    }

    func test_deleteAllData_leavesAnotherAccountsSavedRecipesUntouched() async throws {
        func repository(owner: String) -> SwiftDataSavedRecipeRepository {
            SwiftDataSavedRecipeRepository(
                store: SwiftDataSavedRecipeStore(
                    container: container.modelContainer,
                    ownerIDProvider: { owner }
                )
            )
        }
        let recipe = Recipe(title: "Shared Soup", summary: "", ingredients: [], instructions: [])
        try await repository(owner: "alice").save(recipe, sourceRecipeID: 7)
        try await repository(owner: "bob").save(recipe, sourceRecipeID: 7)

        try await makeDeleter().deleteAllData(ownedBy: "alice")

        let alicesRecipes = try await repository(owner: "alice").fetchAll()
        let bobsRecipes = try await repository(owner: "bob").fetchAll()
        XCTAssertTrue(alicesRecipes.isEmpty)
        XCTAssertEqual(
            bobsRecipes.map(\.title),
            ["Shared Soup"],
            "Both accounts saved the same recipe; only Alice's copy may go"
        )
    }

    // MARK: - Idempotence and scope guards

    /// Retry-after-partial-failure depends on this: deleting data that is
    /// already gone must succeed.
    func test_deleteAllData_runTwice_succeedsBothTimes() async throws {
        let pantry = pantryRepository(owner: "alice")
        try await pantry.add(item("Milk"))

        let deleter = makeDeleter()
        try await deleter.deleteAllData(ownedBy: "alice")
        try await deleter.deleteAllData(ownedBy: "alice")

        let remaining = try await pantry.fetchAll()
        XCTAssertTrue(remaining.isEmpty)
    }

    func test_deleteAllData_forAnAccountWithNothingStored_succeeds() async throws {
        try await makeDeleter().deleteAllData(ownedBy: "nobody-has-data")
    }

    /// An empty uid must not be treated as an owner - a predicate matching
    /// `ownerID == ""` would be harmless, but accepting the call at all
    /// invites a caller to pass an unresolved uid and believe it worked.
    func test_deleteAllData_withAnEmptyUID_throws() async {
        await assertThrowsAsync(try await makeDeleter().deleteAllData(ownedBy: "")) { error in
            XCTAssertEqual(error as? DeleteAccountError, .localDataDeletionFailed("no account id"))
        }
    }
}

// MARK: - On-device preferences and caches

@MainActor
final class LocalStateAccountDataDeleterTests: XCTestCase {

    private var defaults: UserDefaults!
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // A private suite, so the test never touches the real app's settings.
        defaults = UserDefaults(suiteName: "LocalStateAccountDataDeleterTests-\(UUID().uuidString)")
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fridgefit-caches-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for key in LocalStateAccountDataDeleter.preferenceKeys {
            defaults.removeObject(forKey: key)
        }
        try? FileManager.default.removeItem(at: directory)
        defaults = nil
        directory = nil
        try super.tearDownWithError()
    }

    private func makeDeleter() -> LocalStateAccountDataDeleter {
        LocalStateAccountDataDeleter(defaults: defaults, cacheDirectory: directory)
    }

    func test_deleteAllData_clearsTheAppsPreferenceKeys() async throws {
        for key in LocalStateAccountDataDeleter.preferenceKeys {
            defaults.set("something", forKey: key)
        }

        try await makeDeleter().deleteAllData(ownedBy: "alice")

        for key in LocalStateAccountDataDeleter.preferenceKeys {
            XCTAssertNil(defaults.object(forKey: key), "\(key) was left behind")
        }
    }

    /// These caches hold the user's pantry contents in plain text - the
    /// substitution cache is keyed on a pantry fingerprint, the receipt cache
    /// stores interpreted receipts. Leaving them is leaving a readable record
    /// of the fridge on a device with no account.
    func test_deleteAllData_removesTheDerivedCacheFiles() async throws {
        for name in LocalStateAccountDataDeleter.cacheFileNames {
            try Data("{}".utf8).write(to: directory.appendingPathComponent(name))
        }

        try await makeDeleter().deleteAllData(ownedBy: "alice")

        for name in LocalStateAccountDataDeleter.cacheFileNames {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path),
                "\(name) was left behind"
            )
        }
    }

    /// Idempotent by contract: absent files are success, not failure, which
    /// is what makes a retry safe.
    func test_deleteAllData_withNothingToDelete_succeeds() async throws {
        try await makeDeleter().deleteAllData(ownedBy: "alice")
        try await makeDeleter().deleteAllData(ownedBy: "alice")
    }

    func test_deleteAllData_leavesUnrelatedFilesAlone() async throws {
        let keep = directory.appendingPathComponent("default.store")
        try Data("db".utf8).write(to: keep)

        try await makeDeleter().deleteAllData(ownedBy: "alice")

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: keep.path),
            "Only the named cache files may be removed, not the directory"
        )
    }

    /// `DeviceIdentity`'s keys identify the install, not a user, and the
    /// account's cloud device entry is removed separately. Minting a new
    /// device id would make one install look like two.
    func test_deleteAllData_doesNotClearTheDeviceIdentity() async throws {
        XCTAssertFalse(
            LocalStateAccountDataDeleter.preferenceKeys.contains { $0.lowercased().contains("device") },
            "Device identity keys must not be in the deletion list"
        )
    }

    func test_deleteAllData_withAnEmptyUID_throws() async {
        await assertThrowsAsync(try await makeDeleter().deleteAllData(ownedBy: "")) { error in
            XCTAssertEqual(error as? DeleteAccountError, .localDataDeletionFailed("no account id"))
        }
    }
}

// MARK: - The remote collection list

final class FirestoreAccountDataDeleterCoverageTests: XCTestCase {

    /// The deleter names collections, because Firestore offers no recursive
    /// delete on the client and `users/{uid}` is not even a real document in
    /// this app. A collection the app writes but this list omits would
    /// survive "delete my account" silently, so the list is checked against
    /// `firestore.rules` - the authoritative statement of what paths exist.
    func test_everyUserCollectionInTheRules_isCoveredByTheDeleter() throws {
        let rules = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("firestore.rules"),
            encoding: .utf8
        )

        // Collection names appearing as `users/{uid}/<name>/` in a match path.
        let pattern = #"match /users/\{uid\}/([A-Za-z]+)/"#
        let regex = try NSRegularExpression(pattern: pattern)
        var declared: Set<String> = []
        for match in regex.matches(in: rules, range: NSRange(rules.startIndex..., in: rules)) {
            guard let range = Range(match.range(at: 1), in: rules) else { continue }
            declared.insert(String(rules[range]))
        }

        XCTAssertFalse(declared.isEmpty, "The rules file parse found nothing - the pattern needs updating")

        let covered = Set(FirestoreAccountDataDeleter.flatCollections)
            .union([FirestoreAccountDataDeleter.sessionCollection])

        // `fundsCollection` is the rules' wildcard variable for the five
        // FridgeFunds collections, which are listed explicitly in the
        // deleter, so it is not a real collection name.
        let wildcards: Set<String> = ["fundsCollection", "candidateCollection"]
        let missing = declared.subtracting(covered).subtracting(wildcards)

        XCTAssertTrue(
            missing.isEmpty,
            "These collections are in firestore.rules but would survive account deletion: \(missing.sorted())"
        )
    }

    /// Deleting a Firestore document does not delete its subcollections, so
    /// the two candidate collections have to be handled explicitly or every
    /// ICE candidate the user's devices exchanged is orphaned at a path whose
    /// parent is gone.
    func test_webrtcCandidateSubcollections_areCovered() {
        XCTAssertEqual(
            Set(FirestoreAccountDataDeleter.candidateCollections),
            [SignalingRole.caller.candidateCollectionName, SignalingRole.callee.candidateCollectionName],
            "The deleter must cover exactly the subcollections the signalling code writes"
        )
        XCTAssertFalse(
            FirestoreAccountDataDeleter.flatCollections.contains(FirestoreAccountDataDeleter.sessionCollection),
            "webrtcSessions must be handled by the recursive path, not the flat one"
        )
    }

    /// Walks up from this test file to the repository root, so the rules file
    /// is found regardless of where the test bundle is built.
    private static var repositoryRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        // .../FridgeFitTests/Account/AccountDataDeleterTests.swift
        for _ in 0 ..< 3 { url.deleteLastPathComponent() }
        return url
    }
}
