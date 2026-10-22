//
//  SavedRecipeContextIsolationTests.swift
//  FridgeFitTests
//
//  A failed saved-recipe write must undo its own work and nothing else.
//
//  `SwiftDataSavedRecipeStore` recovers from a failure with
//  `ModelContext.rollback()`, which is context-wide. These tests pin down the
//  reason it opens its own context on the shared container instead of using
//  `PersistenceContainer.mainContext`: on the shared context that rollback
//  would also throw away unsaved pantry and inventory-event edits, and the
//  `save()` would commit them.
//

import SwiftData
import XCTest
@testable import FridgeFit

@MainActor
final class SavedRecipeContextIsolationTests: XCTestCase {

    /// Thrown from the store's `willSave` hook. A real SwiftData store cannot
    /// be asked to fail on demand, so the failure is injected at the one point
    /// where a commit can realistically go wrong.
    private struct InjectedStoreFailure: Error {}

    private var container: PersistenceContainer!
    private var owner: String? = "owner-a"
    /// Flipped mid-test so the same store can succeed first and fail later.
    private var shouldFailNextSave = false

    override func setUp() async throws {
        try await super.setUp()
        container = try PersistenceContainer(storage: .inMemory)
        // The pantry's context autosaves in the app. Off here so "still
        // pending" is an assertion the test controls rather than a race: with
        // autosave on, a discarded change could be mistaken for a saved one.
        container.mainContext.autosaveEnabled = false
        shouldFailNextSave = false
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func makeStore() -> SwiftDataSavedRecipeStore {
        SwiftDataSavedRecipeStore(
            container: container.modelContainer,
            ownerIDProvider: { [unowned self] in self.owner },
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            willSave: { [unowned self] in
                if self.shouldFailNextSave { throw InjectedStoreFailure() }
            }
        )
    }

    private func recipe(
        id: Int = 716429,
        title: String = "Garlic Pasta",
        ingredientNames: [String] = ["Pasta", "Garlic", "Parsley"]
    ) -> Recipe {
        Recipe(
            id: SaveOnlineRecipeUseCase.savedRecipeID(forOnlineRecipeID: id),
            title: title,
            summary: "Quick weeknight pasta.",
            servings: 2,
            ingredients: ingredientNames.map {
                RecipeIngredient(ingredient: Ingredient(name: $0), quantity: 100, unit: .grams, role: .essential)
            },
            instructions: ["Boil.", "Fry.", "Toss."]
        )
    }

    /// An unsaved pantry row on the *shared* context - the bystander whose
    /// work a context-wide rollback used to destroy.
    @discardableResult
    private func insertPendingPantryItem(name: String = "Greek Yogurt") -> PantryItemEntity {
        let entity = PantryItemEntity(
            id: UUID(),
            ownerID: "owner-a",
            ingredientName: name,
            ingredientCategory: IngredientCategory.dairy.rawValue,
            quantity: 0.5,
            unit: MeasurementUnit.kilograms.rawValue
        )
        container.mainContext.insert(entity)
        return entity
    }

    @discardableResult
    private func insertPendingInventoryEvent(itemName: String = "Greek Yogurt") -> InventoryEventEntity {
        let entity = InventoryEventEntity(
            id: UUID(),
            ownerID: "owner-a",
            pantryItemID: UUID(),
            itemName: itemName,
            kind: "added",
            date: Date(timeIntervalSince1970: 1_800_000_000)
        )
        container.mainContext.insert(entity)
        return entity
    }

    /// Reads the store file itself, through a context with no cached rows, so
    /// an assertion cannot be satisfied by some other context's memory.
    private func inStore<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try ModelContext(container.modelContainer).fetch(FetchDescriptor<T>())
    }

    // MARK: - A: a failed save keeps pending pantry work

    func test_failedSave_keepsPendingPantryChanges_andTheyStillPersist() async throws {
        let pantryItem = insertPendingPantryItem()
        XCTAssertTrue(container.mainContext.hasChanges, "Precondition: the pantry edit is pending")

        shouldFailNextSave = true
        do {
            try await SwiftDataSavedRecipeRepository(store: makeStore()).save(recipe(), sourceRecipeID: 716429)
            XCTFail("Expected saveFailed")
        } catch {
            XCTAssertEqual(error as? SaveOnlineRecipeError, .saveFailed)
        }

        // The pantry edit is untouched: still pending, still the same row.
        XCTAssertTrue(container.mainContext.hasChanges, "A recipe failure must not discard the pantry edit")
        XCTAssertEqual(pantryItem.ingredientName, "Greek Yogurt")
        XCTAssertFalse(pantryItem.isDeleted)

        // And it can still be committed, which a rollback would have made
        // impossible - there would be nothing left to save.
        try container.mainContext.save()
        XCTAssertEqual(try inStore(PantryItemEntity.self).map(\.ingredientName), ["Greek Yogurt"])
    }

    /// The other half of the shared-context problem: saving a recipe must not
    /// commit someone else's unsaved row as a side effect.
    func test_successfulSave_doesNotCommitPendingPantryChanges() async throws {
        insertPendingPantryItem()

        try await SwiftDataSavedRecipeRepository(store: makeStore()).save(recipe(), sourceRecipeID: 716429)

        XCTAssertEqual(try inStore(SavedRecipeEntity.self).count, 1, "The recipe is committed")
        XCTAssertTrue(try inStore(PantryItemEntity.self).isEmpty, "The pantry edit is still the pantry's to commit")
        XCTAssertTrue(container.mainContext.hasChanges)
    }

    func test_failedSave_leavesNoPartialRecipeInTheStore() async throws {
        shouldFailNextSave = true
        try? await SwiftDataSavedRecipeRepository(store: makeStore()).save(recipe(), sourceRecipeID: 716429)

        XCTAssertTrue(try inStore(SavedRecipeEntity.self).isEmpty, "No half-inserted recipe")
        XCTAssertTrue(try inStore(SavedRecipeIngredientEntity.self).isEmpty, "No orphaned ingredient lines")
    }

    /// A failure must not poison the store object either: the next attempt on
    /// the *same* store has to succeed cleanly.
    func test_storeRecoversAfterAFailure() async throws {
        let repository = SwiftDataSavedRecipeRepository(store: makeStore())

        shouldFailNextSave = true
        try? await repository.save(recipe(), sourceRecipeID: 716429)
        shouldFailNextSave = false
        try await repository.save(recipe(), sourceRecipeID: 716429)

        let titles = try await repository.fetchAll().map(\.title)
        XCTAssertEqual(titles, ["Garlic Pasta"])
        XCTAssertEqual(try inStore(SavedRecipeIngredientEntity.self).count, 3)
    }

    // MARK: - B: a failed removal keeps unrelated work, and keeps the recipe

    func test_failedRemoval_keepsTheRecipe_andUnrelatedPendingChanges() async throws {
        let repository = SwiftDataSavedRecipeRepository(store: makeStore())
        let saved = recipe()
        try await repository.save(saved, sourceRecipeID: 716429)

        let pantryItem = insertPendingPantryItem(name: "Cheddar")
        let event = insertPendingInventoryEvent(itemName: "Cheddar")

        shouldFailNextSave = true
        do {
            try await repository.remove(id: saved.id)
            XCTFail("Expected removeFailed")
        } catch {
            XCTAssertEqual(error as? SaveOnlineRecipeError, .removeFailed)
        }

        // Unrelated pending work survived.
        XCTAssertTrue(container.mainContext.hasChanges)
        XCTAssertFalse(pantryItem.isDeleted)
        XCTAssertFalse(event.isDeleted)
        try container.mainContext.save()
        XCTAssertEqual(try inStore(PantryItemEntity.self).map(\.ingredientName), ["Cheddar"])
        XCTAssertEqual(try inStore(InventoryEventEntity.self).map(\.itemName), ["Cheddar"])

        // And the recipe the user still has was not dropped - neither in the
        // store nor by a pending delete waiting for the next commit.
        shouldFailNextSave = false
        let stillThere = try await repository.fetchAll().map(\.id)
        XCTAssertEqual(stillThere, [saved.id])
        XCTAssertEqual(try inStore(SavedRecipeEntity.self).count, 1)
        XCTAssertEqual(try inStore(SavedRecipeIngredientEntity.self).count, 3)
    }

    /// The recipe must still be removable afterwards - the rolled-back delete
    /// cannot leave the row in a state the store refuses to touch again.
    func test_removalSucceedsAfterAFailedAttempt() async throws {
        let repository = SwiftDataSavedRecipeRepository(store: makeStore())
        let saved = recipe()
        try await repository.save(saved, sourceRecipeID: 716429)

        shouldFailNextSave = true
        try? await repository.remove(id: saved.id)
        shouldFailNextSave = false
        try await repository.remove(id: saved.id)

        let remaining = try await repository.fetchAll()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(try inStore(SavedRecipeEntity.self).isEmpty)
        XCTAssertTrue(try inStore(SavedRecipeIngredientEntity.self).isEmpty, "Cascade delete still applies")
    }

    // MARK: - C: a failed update leaves the saved recipe exactly as it was

    func test_failedUpdate_leavesTheExistingRecipeAndItsLinesIntact() async throws {
        let repository = SwiftDataSavedRecipeRepository(store: makeStore())
        try await repository.save(recipe(), sourceRecipeID: 716429)

        // An update replaces every field and rebuilds the ingredient lines -
        // the case where "just delete what you inserted" cannot restore the
        // previous state.
        shouldFailNextSave = true
        do {
            try await repository.save(
                recipe(title: "Garlic Pasta v2", ingredientNames: ["Pasta", "Chilli"]),
                sourceRecipeID: 716429
            )
            XCTFail("Expected saveFailed")
        } catch {
            XCTAssertEqual(error as? SaveOnlineRecipeError, .saveFailed)
        }
        shouldFailNextSave = false

        let loaded = try await repository.fetchAll()
        XCTAssertEqual(loaded.count, 1, "Still exactly one row")
        XCTAssertEqual(loaded.first?.title, "Garlic Pasta", "The old title is not half-replaced")
        XCTAssertEqual(
            loaded.first?.ingredients.map(\.ingredient.name),
            ["Pasta", "Garlic", "Parsley"],
            "The original lines are intact, in order"
        )
        XCTAssertEqual(try inStore(SavedRecipeIngredientEntity.self).count, 3, "No lines dropped, none added")
    }

    func test_failedUpdate_keepsTheStoredPhoto() async throws {
        let repository = SwiftDataSavedRecipeRepository(store: makeStore())
        try await repository.save(recipe(), sourceRecipeID: 716429, imageData: Data([1, 2, 3]))

        shouldFailNextSave = true
        try? await repository.save(recipe(title: "v2"), sourceRecipeID: 716429, imageData: Data([9]))
        shouldFailNextSave = false

        let keptPhoto = try await repository.imageData(forRecipeID: recipe().id)
        XCTAssertEqual(keptPhoto, Data([1, 2, 3]))
    }

    // MARK: - D: the successful paths are unchanged

    /// The own-context store still satisfies the behaviour the feature is
    /// built on: round trip, upsert, remove, owner scoping, and data that
    /// outlives the store object that wrote it.
    func test_successfulOperations_behaveAsBefore() async throws {
        let repository = SwiftDataSavedRecipeRepository(store: makeStore())

        try await repository.save(recipe(), sourceRecipeID: 716429, imageData: Data([4]))
        let afterSave = try await repository.fetchAll().map(\.title)
        XCTAssertEqual(afterSave, ["Garlic Pasta"])

        // Upsert, not duplicate.
        try await repository.save(recipe(title: "v2", ingredientNames: ["Pasta"]), sourceRecipeID: 716429)
        let afterUpdate = try await repository.fetchAll()
        XCTAssertEqual(afterUpdate.count, 1)
        XCTAssertEqual(afterUpdate.first?.title, "v2")
        XCTAssertEqual(try inStore(SavedRecipeIngredientEntity.self).count, 1)
        let photo = try await repository.imageData(forRecipeID: recipe().id)
        XCTAssertEqual(photo, Data([4]), "Re-save kept the photo")

        // Owner scoping.
        owner = "owner-b"
        let otherOwner = try await repository.fetchAll()
        XCTAssertTrue(otherOwner.isEmpty)
        owner = "owner-a"

        // A brand-new store over the same container reads what this one wrote.
        let reopened = SwiftDataSavedRecipeRepository(store: makeStore())
        let fromReopened = try await reopened.fetchAll().map(\.title)
        XCTAssertEqual(fromReopened, ["v2"])

        try await repository.remove(id: recipe().id)
        let afterRemove = try await reopened.fetchAll()
        XCTAssertTrue(afterRemove.isEmpty)
        XCTAssertTrue(try inStore(SavedRecipeEntity.self).isEmpty)
    }

    /// Both features writing at once, through their separate contexts, land in
    /// one store without stepping on each other.
    func test_pantryAndSavedRecipes_shareTheStoreWithoutInterference() async throws {
        let pantry = SwiftDataPantryRepository(context: container.mainContext, ownerIDProvider: { "owner-a" })
        let repository = SwiftDataSavedRecipeRepository(store: makeStore())

        try await pantry.add(PantryItem(ingredient: Ingredient(name: "Rice", category: .grain), quantity: 1, unit: .kilograms))
        try await repository.save(recipe(), sourceRecipeID: 716429)

        let pantryNames = try await pantry.fetchAll().map(\.ingredient.name)
        let recipeTitles = try await repository.fetchAll().map(\.title)
        XCTAssertEqual(pantryNames, ["Rice"])
        XCTAssertEqual(recipeTitles, ["Garlic Pasta"])
        XCTAssertEqual(try inStore(PantryItemEntity.self).count, 1)
        XCTAssertEqual(try inStore(SavedRecipeEntity.self).count, 1)
    }

    func test_notAuthenticated_writesNothingAndLeavesNoPendingWork() async throws {
        owner = nil
        let repository = SwiftDataSavedRecipeRepository(store: makeStore())

        do {
            try await repository.save(recipe(), sourceRecipeID: 716429)
            XCTFail("Expected notAuthenticated")
        } catch {
            XCTAssertEqual(error as? SaveOnlineRecipeError, .notAuthenticated)
        }

        XCTAssertTrue(try inStore(SavedRecipeEntity.self).isEmpty)
    }
}
