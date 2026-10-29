//
//  SwiftDataAccountDataDeleter.swift
//  FridgeFit
//

import Foundation
import OSLog
import SwiftData

/// Deletes one account's rows from the on-device store.
///
/// ## Why every fetch is predicated on `ownerID`
///
/// A local database has no equivalent of Firestore's `users/{uid}` path, so
/// the scoping that security rules give for free in the cloud is a column
/// here (see `PantryItemEntity.ownerID`). That makes the predicate the entire
/// safety boundary for this operation: a `delete(model:)` without one would
/// wipe the pantry of every account that has ever signed in on the device,
/// including the one still signed in on another profile. Deleting account A
/// must leave account B's food exactly where it was, which
/// `SwiftDataAccountDataDeleterTests` checks directly rather than trusting
/// the predicate by inspection.
///
/// ## Why saved-recipe ingredient lines are not deleted explicitly
///
/// `SavedRecipeEntity.ingredients` is declared `.cascade`, so SwiftData
/// removes the lines with their recipe. `InventoryEventEntity` is the
/// opposite case and is deleted explicitly: it is `.nullify` against the
/// pantry item on purpose, because an event has to outlive the food it
/// describes, which means nothing deletes it on the pantry's behalf.
@MainActor
final class SwiftDataAccountDataDeleter: AccountDataDeleting {
    private let context: ModelContext
    /// Saved recipes live in their own context (see
    /// `SwiftDataSavedRecipeStore`), so they are deleted through theirs
    /// rather than this one.
    private let savedRecipeContext: ModelContext
    private let logger = Logger(subsystem: "com.fridgefit.app", category: "AccountDeletion")

    init(context: ModelContext, savedRecipeContext: ModelContext) {
        self.context = context
        self.savedRecipeContext = savedRecipeContext
    }

    func deleteAllData(ownedBy uid: String) async throws {
        guard !uid.isEmpty else {
            throw DeleteAccountError.localDataDeletionFailed("no account id")
        }

        do {
            // Events before items. Either order works - the relationship is
            // `.nullify`, not `.cascade` - but doing the log first means a
            // failure part-way cannot leave events pointing at items that
            // are gone.
            try delete(
                FetchDescriptor<InventoryEventEntity>(predicate: #Predicate { $0.ownerID == uid }),
                from: context
            )
            try delete(
                FetchDescriptor<PantryItemEntity>(predicate: #Predicate { $0.ownerID == uid }),
                from: context
            )

            // FridgeFunds. These live in the same container and context as
            // the pantry (see `AppDependencies`), so they are deleted here
            // rather than needing a stage of their own. Omitting them is a
            // mistake that only shows up as "I deleted my account and my
            // budget came back", which is why
            // `SwiftDataAccountDataDeleterTests` asserts on all five.
            try delete(
                FetchDescriptor<FoodBudgetEntity>(predicate: #Predicate { $0.ownerID == uid }),
                from: context
            )
            try delete(
                FetchDescriptor<GrocerySpendEntity>(predicate: #Predicate { $0.ownerID == uid }),
                from: context
            )
            try delete(
                FetchDescriptor<WastedFoodCostEntity>(predicate: #Predicate { $0.ownerID == uid }),
                from: context
            )
            try delete(
                FetchDescriptor<ItemPriceEntity>(predicate: #Predicate { $0.ownerID == uid }),
                from: context
            )
            try delete(
                FetchDescriptor<PriceBookEntryEntity>(predicate: #Predicate { $0.ownerID == uid }),
                from: context
            )

            try context.save()

            try delete(
                FetchDescriptor<SavedRecipeEntity>(predicate: #Predicate { $0.ownerID == uid }),
                from: savedRecipeContext
            )
            try savedRecipeContext.save()
        } catch {
            logger.error("Local store deletion failed: \(error.localizedDescription, privacy: .public)")
            // Leave the contexts as they were rather than half-applied, so a
            // retry starts from a clean slate instead of an unsaved partial
            // delete.
            context.rollback()
            savedRecipeContext.rollback()
            throw DeleteAccountError.localDataDeletionFailed(error.localizedDescription)
        }
    }

    /// Deletes everything one descriptor matches.
    ///
    /// Written as a fetch-then-delete loop rather than
    /// `context.delete(model:where:)` because the bulk form bypasses the
    /// in-memory graph: objects already loaded by `InventoryStore` would stay
    /// live, and cascade rules would not run - which matters for
    /// `SavedRecipeEntity`'s ingredient lines.
    ///
    /// The predicate is supplied by the caller, and every caller supplies an
    /// `ownerID` one. Deliberately not defaulted: a missing predicate here
    /// would silently become "delete every account's rows", so there is no
    /// code path that can omit it.
    private func delete<T: PersistentModel>(
        _ descriptor: FetchDescriptor<T>,
        from context: ModelContext
    ) throws {
        for object in try context.fetch(descriptor) {
            context.delete(object)
        }
    }
}
