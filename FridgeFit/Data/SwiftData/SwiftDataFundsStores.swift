//
//  SwiftDataFundsStores.swift
//  FridgeFit
//

import Foundation
import OSLog
import SwiftData

/// FridgeFunds, stored on the device.
///
/// ## Why these exist
///
/// `PersistenceConfiguration.compiledDefault` is `.swiftData`, so the
/// shipping build keeps the pantry, the activity log and saved recipes in a
/// local database. The money side had no local implementation at all, and
/// `ContentView` built `FundsEnvironment.firestore(...)` unconditionally - so
/// the running app put the pantry on the device and the *prices of the things
/// in that pantry* in the cloud. Two stores, two lifetimes, two different
/// answers to "is this user's data local", and a Settings screen that could
/// not truthfully describe either.
///
/// These close that gap. In SwiftData mode every FridgeFunds figure now lives
/// beside the pantry it values, in the same container and the same store
/// file, under the same `ownerID` scoping.
///
/// ## Why a loaded snapshot, like the Firestore stores
///
/// The `BudgetStore` / `ItemPriceStore` / `PriceBookStore` reads are
/// synchronous, because `EvaluateBudgetStatusUseCase` and
/// `ValueFridgeUseCase` compute a whole summary without suspending. These
/// keep the same shape as their Firestore counterparts - `load()` fills an
/// in-memory copy and reads answer from it - rather than fetching per read.
/// That is not only for protocol conformance: it keeps one definition of
/// "the figures this screen is showing", so a summary cannot be computed
/// half from one state of the database and half from another.
///
/// Writes go to the database *first* and only update the snapshot once the
/// save succeeded, which is the opposite of what the Firestore stores used to
/// do and the reason a failed write can no longer leave a figure on screen
/// that was never stored.

@MainActor
final class SwiftDataBudgetStore: BudgetStore {
    private let context: ModelContext
    private let ownerIDProvider: () -> String?
    private let logger = Logger(subsystem: "com.fridgefit.app", category: "FridgeFunds")

    private var budget: FoodBudget?
    private var spends: [GrocerySpend] = []
    private var wasteCosts: [WastedFoodCost] = []

    init(context: ModelContext, ownerIDProvider: @escaping () -> String?) {
        self.context = context
        self.ownerIDProvider = ownerIDProvider
    }

    private func requireOwner() throws -> String {
        guard let owner = ownerIDProvider(), !owner.isEmpty else {
            throw PantryRepositoryError.notAuthenticated
        }
        return owner
    }

    func load() async throws {
        let owner = try requireOwner()

        let budgets = try context.fetch(
            FetchDescriptor<FoodBudgetEntity>(predicate: #Predicate { $0.ownerID == owner })
        )
        budget = budgets.first.flatMap(Self.budget(from:))

        spends = try context.fetch(
            FetchDescriptor<GrocerySpendEntity>(
                predicate: #Predicate { $0.ownerID == owner },
                sortBy: [SortDescriptor(\.spentOn)]
            )
        ).compactMap(Self.spend(from:))

        wasteCosts = try context.fetch(
            FetchDescriptor<WastedFoodCostEntity>(
                predicate: #Predicate { $0.ownerID == owner },
                sortBy: [SortDescriptor(\.discardedOn)]
            )
        ).compactMap(Self.waste(from:))
    }

    // MARK: Budget

    func activeBudget() -> FoodBudget? { budget }

    /// Replaces this owner's budget. One budget per account, so an existing
    /// row is updated in place rather than a second one inserted - otherwise
    /// `load()` would have to pick between two and "which budget am I on"
    /// would depend on fetch order.
    @discardableResult
    func saveBudget(_ budget: FoodBudget) async throws -> FundsWriteOutcome {
        let owner = try requireOwner()

        do {
            let existing = try context.fetch(
                FetchDescriptor<FoodBudgetEntity>(predicate: #Predicate { $0.ownerID == owner })
            )
            for row in existing {
                context.delete(row)
            }
            context.insert(
                FoodBudgetEntity(
                    id: budget.id,
                    ownerID: owner,
                    limitAmount: FundsDecimal.text(budget.limit.amount),
                    currency: budget.currency.rawValue,
                    cadence: budget.cadence.rawValue,
                    startDate: budget.startDate
                )
            )
            try context.save()
        } catch {
            context.rollback()
            logger.error("Saving budget failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        // Snapshot updated only now that the row is committed.
        self.budget = budget
        return .committed
    }

    // MARK: Spends

    func allSpends() -> [GrocerySpend] { spends }

    @discardableResult
    func addSpend(_ spend: GrocerySpend) async throws -> FundsWriteOutcome {
        let owner = try requireOwner()
        let id = spend.id

        do {
            // Keyed by the spend's own id, so retrying a failed save updates
            // one row instead of logging the purchase twice.
            let existing = try context.fetch(
                FetchDescriptor<GrocerySpendEntity>(predicate: #Predicate { $0.id == id })
            )
            for row in existing {
                context.delete(row)
            }
            context.insert(
                GrocerySpendEntity(
                    id: spend.id,
                    ownerID: owner,
                    amount: FundsDecimal.text(spend.amount.amount),
                    currency: spend.amount.currency.rawValue,
                    spentOn: spend.spentOn,
                    store: spend.store,
                    note: spend.note,
                    purchasedItemIDs: spend.purchasedItemIDs.map(\.rawValue)
                )
            )
            try context.save()
        } catch {
            context.rollback()
            logger.error("Saving spend failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        spends.removeAll { $0.id == spend.id }
        spends.append(spend)
        return .committed
    }

    // MARK: Waste

    func allWasteCosts() -> [WastedFoodCost] { wasteCosts }

    @discardableResult
    func addWasteCost(_ cost: WastedFoodCost) async throws -> FundsWriteOutcome {
        let owner = try requireOwner()
        let id = cost.id

        do {
            let existing = try context.fetch(
                FetchDescriptor<WastedFoodCostEntity>(predicate: #Predicate { $0.id == id })
            )
            for row in existing {
                context.delete(row)
            }
            context.insert(
                WastedFoodCostEntity(
                    id: cost.id,
                    ownerID: owner,
                    pantryItemID: cost.pantryItemID.rawValue,
                    quantityDiscarded: cost.quantityDiscarded,
                    lostAmount: FundsDecimal.text(cost.lostAmount.amount),
                    currency: cost.lostAmount.currency.rawValue,
                    discardedOn: cost.discardedOn,
                    reason: cost.reason.rawValue
                )
            )
            try context.save()
        } catch {
            context.rollback()
            logger.error("Saving waste cost failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        wasteCosts.removeAll { $0.id == cost.id }
        wasteCosts.append(cost)
        return .committed
    }

    func wasteAlreadyRecorded(for itemID: PantryItemID, on day: Date) -> Bool {
        wasteCosts.contains {
            $0.pantryItemID == itemID && Calendar.current.isDate($0.discardedOn, inSameDayAs: day)
        }
    }

    // MARK: Mapping

    /// Rows whose stored money cannot be parsed decode to `nil` and are
    /// dropped rather than defaulted to zero. A budget silently reading as
    /// $0.00 would tell the user they had overspent everything; an absent
    /// budget tells them to set one.
    private static func budget(from entity: FoodBudgetEntity) -> FoodBudget? {
        guard
            let limit = FundsDecimal.money(entity.limitAmount, entity.currency),
            let cadence = BudgetCadence(rawValue: entity.cadence)
        else { return nil }
        return FoodBudget(id: entity.id, limit: limit, cadence: cadence, startDate: entity.startDate)
    }

    private static func spend(from entity: GrocerySpendEntity) -> GrocerySpend? {
        guard let amount = FundsDecimal.money(entity.amount, entity.currency) else { return nil }
        return GrocerySpend(
            id: entity.id,
            amount: amount,
            spentOn: entity.spentOn,
            store: entity.store,
            purchasedItemIDs: entity.purchasedItemIDs.map(PantryItemID.init),
            note: entity.note
        )
    }

    private static func waste(from entity: WastedFoodCostEntity) -> WastedFoodCost? {
        guard
            let lost = FundsDecimal.money(entity.lostAmount, entity.currency),
            let reason = DiscardReason(rawValue: entity.reason)
        else { return nil }
        return WastedFoodCost(
            id: entity.id,
            pantryItemID: PantryItemID(entity.pantryItemID),
            quantityDiscarded: entity.quantityDiscarded,
            lostAmount: lost,
            discardedOn: entity.discardedOn,
            reason: reason
        )
    }
}

@MainActor
final class SwiftDataItemPriceStore: ItemPriceStore {
    private let context: ModelContext
    private let ownerIDProvider: () -> String?
    private let logger = Logger(subsystem: "com.fridgefit.app", category: "FridgeFunds")
    private var byID: [PantryItemID: ItemPriceInfo] = [:]

    init(context: ModelContext, ownerIDProvider: @escaping () -> String?) {
        self.context = context
        self.ownerIDProvider = ownerIDProvider
    }

    private func requireOwner() throws -> String {
        guard let owner = ownerIDProvider(), !owner.isEmpty else {
            throw PantryRepositoryError.notAuthenticated
        }
        return owner
    }

    func load() async throws {
        let owner = try requireOwner()
        let rows = try context.fetch(
            FetchDescriptor<ItemPriceEntity>(predicate: #Predicate { $0.ownerID == owner })
        )
        byID = Dictionary(
            rows.map { row in
                let id = PantryItemID(row.pantryItemID)
                return (
                    id,
                    ItemPriceInfo(
                        pantryItemID: id,
                        unitCost: FundsDecimal.money(row.unitCost, row.currency),
                        expiryDate: row.expiryDate
                    )
                )
            },
            uniquingKeysWith: { _, last in last }
        )
    }

    func info(for itemID: PantryItemID) -> ItemPriceInfo? { byID[itemID] }

    @discardableResult
    func save(_ info: ItemPriceInfo) async throws -> FundsWriteOutcome {
        let owner = try requireOwner()
        let itemID = info.pantryItemID.rawValue

        do {
            // Identity is (ownerID, pantryItemID), so the predicate carries
            // both. Matching on the item alone would overwrite another
            // account's price for the same item id.
            let existing = try context.fetch(
                FetchDescriptor<ItemPriceEntity>(
                    predicate: #Predicate { $0.ownerID == owner && $0.pantryItemID == itemID }
                )
            )
            for row in existing {
                context.delete(row)
            }
            context.insert(
                ItemPriceEntity(
                    ownerID: owner,
                    pantryItemID: itemID,
                    unitCost: info.unitCost.map { FundsDecimal.text($0.amount) },
                    currency: info.unitCost?.currency.rawValue,
                    expiryDate: info.expiryDate
                )
            )
            try context.save()
        } catch {
            context.rollback()
            logger.error("Saving item price failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        byID[info.pantryItemID] = info
        return .committed
    }
}

@MainActor
final class SwiftDataPriceBookStore: PriceBookStore {
    private let context: ModelContext
    private let ownerIDProvider: () -> String?
    private let logger = Logger(subsystem: "com.fridgefit.app", category: "FridgeFunds")
    private var byKey: [String: PriceBookEntry] = [:]

    init(context: ModelContext, ownerIDProvider: @escaping () -> String?) {
        self.context = context
        self.ownerIDProvider = ownerIDProvider
    }

    private func requireOwner() throws -> String {
        guard let owner = ownerIDProvider(), !owner.isEmpty else {
            throw PantryRepositoryError.notAuthenticated
        }
        return owner
    }

    func load() async throws {
        let owner = try requireOwner()
        let rows = try context.fetch(
            FetchDescriptor<PriceBookEntryEntity>(predicate: #Predicate { $0.ownerID == owner })
        )
        byKey = Dictionary(
            rows.compactMap { row -> (String, PriceBookEntry)? in
                guard let cost = FundsDecimal.money(row.unitCost, row.currency) else { return nil }
                return (
                    row.key,
                    PriceBookEntry(
                        displayName: row.displayName,
                        unitCost: cost,
                        unit: row.unit,
                        recordedOn: row.recordedOn
                    )
                )
            },
            uniquingKeysWith: { _, last in last }
        )
    }

    func entry(forIngredientNamed name: String) -> PriceBookEntry? {
        byKey[PriceBookEntry.key(for: name)]
    }

    @discardableResult
    func record(_ entry: PriceBookEntry) async throws -> FundsWriteOutcome {
        let owner = try requireOwner()
        let key = entry.key

        do {
            let existing = try context.fetch(
                FetchDescriptor<PriceBookEntryEntity>(
                    predicate: #Predicate { $0.ownerID == owner && $0.key == key }
                )
            )
            for row in existing {
                context.delete(row)
            }
            context.insert(
                PriceBookEntryEntity(
                    ownerID: owner,
                    key: entry.key,
                    displayName: entry.displayName,
                    unitCost: FundsDecimal.text(entry.unitCost.amount),
                    currency: entry.unitCost.currency.rawValue,
                    unit: entry.unit,
                    recordedOn: entry.recordedOn
                )
            )
            try context.save()
        } catch {
            context.rollback()
            logger.error("Saving price book entry failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        byKey[entry.key] = entry
        return .committed
    }
}
