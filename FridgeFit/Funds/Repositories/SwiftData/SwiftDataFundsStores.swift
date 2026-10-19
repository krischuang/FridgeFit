//
//  SwiftDataFundsStores.swift
//  FridgeFit
//

import Foundation
import OSLog
import SwiftData

// on-device versions of BudgetStore / ItemPriceStore, for when the app runs on
// SwiftData (the default). they share the app's one ModelContext with the
// pantry, and scope everything by ownerID exactly like SwiftDataPantryRepository.
//
// the store protocols are sync and don't throw (that's how the FridgeFunds use
// cases were written), and SwiftData fetches are sync too, so no cache needed.
// if nobody's signed in, reads come back empty and writes are skipped - same
// "never fall back to an unscoped place" idea as the pantry's notAuthenticated.

private let logger = Logger(subsystem: "com.fridgefit.app", category: "FridgeFunds")

@MainActor
final class SwiftDataBudgetStore: BudgetStore {
    private let context: ModelContext
    private let ownerIDProvider: () -> String?

    init(context: ModelContext, ownerIDProvider: @escaping () -> String?) {
        self.context = context
        self.ownerIDProvider = ownerIDProvider
    }

    private var ownerID: String? {
        guard let id = ownerIDProvider(), !id.isEmpty else { return nil }
        return id
    }

    func activeBudget() -> FoodBudget? {
        guard let ownerID else { return nil }
        return budgetEntity(ownerID).flatMap(FundsEntityMapper.toDomain)
    }

    func saveBudget(_ budget: FoodBudget) {
        guard let ownerID else { return logger.notice("No signed-in user, budget not saved") }
        if let existing = budgetEntity(ownerID) {
            existing.budgetID = budget.id
            existing.limitAmount = FundsEntityMapper.string(budget.limit)
            existing.currency = budget.currency.rawValue
            existing.cadence = budget.cadence.rawValue
            existing.startDate = budget.startDate
        } else {
            context.insert(FundsBudgetEntity(ownerID: ownerID, budgetID: budget.id,
                                             limitAmount: FundsEntityMapper.string(budget.limit),
                                             currency: budget.currency.rawValue,
                                             cadence: budget.cadence.rawValue,
                                             startDate: budget.startDate))
        }
        save("budget")
    }

    func allSpends() -> [GrocerySpend] {
        guard let ownerID else { return [] }
        let descriptor = FetchDescriptor<GrocerySpendEntity>(
            predicate: #Predicate { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.spentOn)]
        )
        return fetch(descriptor).compactMap(FundsEntityMapper.toDomain)
    }

    func addSpend(_ spend: GrocerySpend) {
        guard let ownerID else { return logger.notice("No signed-in user, spend not saved") }
        context.insert(GrocerySpendEntity(id: spend.id, ownerID: ownerID,
                                          amount: FundsEntityMapper.string(spend.amount),
                                          currency: spend.amount.currency.rawValue,
                                          spentOn: spend.spentOn, store: spend.store,
                                          purchasedItemIDs: spend.purchasedItemIDs.map(\.rawValue),
                                          note: spend.note))
        save("spend")
    }

    func allWasteCosts() -> [WastedFoodCost] {
        guard let ownerID else { return [] }
        let descriptor = FetchDescriptor<WastedFoodCostEntity>(
            predicate: #Predicate { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.discardedOn)]
        )
        return fetch(descriptor).compactMap(FundsEntityMapper.toDomain)
    }

    func addWasteCost(_ cost: WastedFoodCost) {
        guard let ownerID else { return logger.notice("No signed-in user, waste not saved") }
        context.insert(WastedFoodCostEntity(id: cost.id, ownerID: ownerID,
                                            pantryItemID: cost.pantryItemID.rawValue,
                                            quantityDiscarded: cost.quantityDiscarded,
                                            lostAmount: FundsEntityMapper.string(cost.lostAmount),
                                            currency: cost.lostAmount.currency.rawValue,
                                            discardedOn: cost.discardedOn,
                                            reason: cost.reason.rawValue))
        save("waste")
    }

    func wasteAlreadyRecorded(for itemID: PantryItemID, on day: Date) -> Bool {
        allWasteCosts().contains {
            $0.pantryItemID == itemID && Calendar.current.isDate($0.discardedOn, inSameDayAs: day)
        }
    }

    // one active budget per account
    private func budgetEntity(_ ownerID: String) -> FundsBudgetEntity? {
        var descriptor = FetchDescriptor<FundsBudgetEntity>(predicate: #Predicate { $0.ownerID == ownerID })
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("FridgeFunds fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func save(_ what: String) {
        do {
            try context.save()
        } catch {
            logger.error("Saving \(what, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

@MainActor
final class SwiftDataItemPriceStore: ItemPriceStore {
    private let context: ModelContext
    private let ownerIDProvider: () -> String?

    init(context: ModelContext, ownerIDProvider: @escaping () -> String?) {
        self.context = context
        self.ownerIDProvider = ownerIDProvider
    }

    private var ownerID: String? {
        guard let id = ownerIDProvider(), !id.isEmpty else { return nil }
        return id
    }

    func info(for itemID: PantryItemID) -> ItemPriceInfo? {
        guard let ownerID else { return nil }
        return entity(ownerID, itemID.rawValue).map(FundsEntityMapper.toDomain)
    }

    func save(_ info: ItemPriceInfo) {
        guard let ownerID else { return logger.notice("No signed-in user, item price not saved") }
        let unitCost = info.unitCost.map(FundsEntityMapper.string)
        let currency = info.unitCost?.currency.rawValue
        // one row per pantry item - update it if it's there
        if let existing = entity(ownerID, info.pantryItemID.rawValue) {
            existing.unitCost = unitCost
            existing.currency = currency
            existing.expiryDate = info.expiryDate
        } else {
            context.insert(ItemPriceEntity(ownerID: ownerID, pantryItemID: info.pantryItemID.rawValue,
                                           unitCost: unitCost, currency: currency, expiryDate: info.expiryDate))
        }
        do {
            try context.save()
        } catch {
            logger.error("Saving item price failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func entity(_ ownerID: String, _ itemID: String) -> ItemPriceEntity? {
        var descriptor = FetchDescriptor<ItemPriceEntity>(
            predicate: #Predicate { $0.ownerID == ownerID && $0.pantryItemID == itemID }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}

@MainActor
final class SwiftDataPriceBookStore: PriceBookStore {
    private let context: ModelContext
    private let ownerIDProvider: () -> String?

    init(context: ModelContext, ownerIDProvider: @escaping () -> String?) {
        self.context = context
        self.ownerIDProvider = ownerIDProvider
    }

    private var ownerID: String? {
        guard let id = ownerIDProvider(), !id.isEmpty else { return nil }
        return id
    }

    func entry(forIngredientNamed name: String) -> PriceBookEntry? {
        guard let ownerID else { return nil }
        return entity(ownerID, PriceBookEntry.key(for: name)).flatMap(FundsEntityMapper.toDomain)
    }

    func record(_ entry: PriceBookEntry) {
        guard let ownerID else { return logger.notice("No signed-in user, price book not updated") }
        let cost = FundsEntityMapper.string(entry.unitCost)
        if let existing = entity(ownerID, entry.key) {
            existing.displayName = entry.displayName
            existing.unitCost = cost
            existing.currency = entry.unitCost.currency.rawValue
            existing.unit = entry.unit
            existing.recordedOn = entry.recordedOn
        } else {
            context.insert(PriceBookEntity(ownerID: ownerID, key: entry.key, displayName: entry.displayName,
                                           unitCost: cost, currency: entry.unitCost.currency.rawValue,
                                           unit: entry.unit, recordedOn: entry.recordedOn))
        }
        do {
            try context.save()
        } catch {
            logger.error("Saving price book failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func entity(_ ownerID: String, _ key: String) -> PriceBookEntity? {
        var descriptor = FetchDescriptor<PriceBookEntity>(
            predicate: #Predicate { $0.ownerID == ownerID && $0.key == key }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
