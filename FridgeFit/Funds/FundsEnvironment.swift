//
//  FundsEnvironment.swift
//  FridgeFit
//

import Foundation
import SwiftData

// composition root for the FridgeFunds bits - holds whatever BudgetStore /
// PantryReading / ItemPriceStore it's running on and builds use cases from them.
// views/viewmodels only ever depend on this, so the in-memory and Firestore
// setups below are interchangeable.
final class FundsEnvironment {
    let budgetStore: BudgetStore
    let pantry: PantryReading
    let priceStore: ItemPriceStore
    private let reloadData: () async throws -> Void

    var lastLoadError: String?

    init(budgetStore: BudgetStore,
         pantry: PantryReading,
         priceStore: ItemPriceStore = InMemoryItemPriceStore(),
         reload: @escaping () async throws -> Void = {}) {
        self.budgetStore = budgetStore
        self.pantry = pantry
        self.priceStore = priceStore
        self.reloadData = reload
    }

    // pulls fresh pantry/budget data. screens call this before refreshing, since
    // the stores answer sync reads from whatever was loaded last.
    func reload() async {
        do {
            try await reloadData()
            lastLoadError = nil
        } catch {
            lastLoadError = error.localizedDescription
        }
    }

    var recordSpend: RecordGrocerySpendUseCase {
        RecordGrocerySpendUseCase(budgetStore: budgetStore)
    }
    var recordDiscardedCost: RecordDiscardedItemCostUseCase {
        RecordDiscardedItemCostUseCase(pantry: pantry, budgetStore: budgetStore)
    }
    var evaluateStatus: EvaluateBudgetStatusUseCase {
        EvaluateBudgetStatusUseCase(budgetStore: budgetStore)
    }
    var valueFridge: ValueFridgeUseCase {
        ValueFridgeUseCase(pantry: pantry)
    }
}

extension FundsEnvironment {
    // the real thing: FridgeFit's own pantry + everything saved per user in Firestore
    static func firestore(pantryRepository: PantryRepository) -> FundsEnvironment {
        let budgetStore = FirestoreBudgetStore()
        let priceStore = FirestoreItemPriceStore()
        let pantry = FridgeFitPantryReading(repository: pantryRepository, priceStore: priceStore)
        return FundsEnvironment(budgetStore: budgetStore, pantry: pantry, priceStore: priceStore) {
            try await budgetStore.load()
            try await priceStore.load()
            try await pantry.refresh()
        }
    }

    // on-device (the default backend): same SwiftData store and owner as the pantry
    static func swiftData(pantryRepository: PantryRepository,
                          context: ModelContext,
                          ownerIDProvider: @escaping () -> String?) -> FundsEnvironment {
        let budgetStore = SwiftDataBudgetStore(context: context, ownerIDProvider: ownerIDProvider)
        let priceStore = SwiftDataItemPriceStore(context: context, ownerIDProvider: ownerIDProvider)
        let pantry = FridgeFitPantryReading(repository: pantryRepository, priceStore: priceStore)
        // SwiftData reads are live, only the pantry snapshot needs refreshing
        return FundsEnvironment(budgetStore: budgetStore, pantry: pantry, priceStore: priceStore) {
            try await pantry.refresh()
        }
    }

    // FridgeFunds follows whichever backend the rest of the app is on
    static func matching(_ dependencies: AppDependencies) -> FundsEnvironment {
        switch dependencies.backend {
        case .swiftData:
            if let context = dependencies.modelContext {
                return .swiftData(pantryRepository: dependencies.pantryRepository,
                                  context: context,
                                  ownerIDProvider: dependencies.ownerIDProvider)
            }
            // only happens for the previews/tests init, which has no store
            return .inMemory(pantryRepository: dependencies.pantryRepository)
        case .firebase:
            return .firestore(pantryRepository: dependencies.pantryRepository)
        }
    }

    // nothing saved anywhere - for UI tests, still reads the (in-memory) FridgeFit pantry
    static func inMemory(pantryRepository: PantryRepository) -> FundsEnvironment {
        let priceStore = InMemoryItemPriceStore()
        let pantry = FridgeFitPantryReading(repository: pantryRepository, priceStore: priceStore)
        return FundsEnvironment(budgetStore: InMemoryBudgetStore(), pantry: pantry, priceStore: priceStore) {
            try await pantry.refresh()
        }
    }

    // seeded stores + a sample fridge, just for SwiftUI previews
    static func sample(now: Date = Date()) -> FundsEnvironment {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -2, to: now) ?? now

        let budget = FoodBudget(limit: Money(120, .aud), cadence: .weekly, startDate: start)
        let seededSpends = [
            GrocerySpend(amount: Money(35, .aud), spentOn: start, store: "Woolworths"),
            GrocerySpend(amount: Money(18, .aud),
                         spentOn: calendar.date(byAdding: .day, value: 1, to: start) ?? start,
                         store: "Coles")
        ]

        let budgetStore = InMemoryBudgetStore(budget: budget, spends: seededSpends)
        let pantry = InMemoryPantryReading.sample(currency: .aud, now: now)
        return FundsEnvironment(budgetStore: budgetStore, pantry: pantry)
    }
}
