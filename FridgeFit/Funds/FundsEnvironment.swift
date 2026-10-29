//
//  FundsEnvironment.swift
//  FridgeFit
//

import Foundation
// For the `ModelContext` the on-device factory takes. This type still names
// no store type in its own stored properties; the factories at the bottom
// do, which is the same arrangement `AppDependencies` has with the pantry.
import SwiftData

/// Composition root for the money side of FridgeFit (FridgeFunds).
///
/// Holds whichever `BudgetStore` / `PantryReading` / `ItemPriceStore` /
/// `PriceBookStore` this build is running on and builds the use cases from
/// them. Views and view models only ever depend on this object, so the
/// in-memory and Firestore setups below are interchangeable.
///
/// ## Why this exists rather than Firestore in the view
///
/// `ProfileImpactView` must not construct `FirestoreBudgetStore` itself -
/// that would hard-wire one backend into a screen and make the screen
/// untestable. `ContentView` builds this once, beside the pantry repository
/// it already owns, and hands it down through `\.fundsEnvironment`. It is
/// the same shape as `\.pantryRepository`.
///
/// ## Which factory the app uses
///
/// `AppDependencies.fundsEnvironment` picks one, from the same
/// `PersistenceBackend` it uses to pick the pantry repository:
/// `.swiftData(...)` in the shipping configuration, `.firestore(...)` in
/// Firebase mode. `ContentView` is handed the result and constructs nothing.
///
/// It used to call `.firestore(...)` itself, unconditionally, which both put
/// a backend decision inside a `View` and - because the compiled default is
/// `.swiftData` - put the money side of a local app in the cloud.
final class FundsEnvironment {
    let budgetStore: BudgetStore
    let pantry: PantryReading
    let priceStore: ItemPriceStore
    /// Last price paid per ingredient name, kept after the item is used up.
    let priceBook: PriceBookStore
    private let reloadData: () async throws -> Void

    /// What went wrong on the last `reload()`, or `nil` if it worked. The
    /// Impact screen shows this instead of pretending the numbers are
    /// current.
    private(set) var lastLoadError: String?

    init(
        budgetStore: BudgetStore,
        pantry: PantryReading,
        priceStore: ItemPriceStore = InMemoryItemPriceStore(),
        priceBook: PriceBookStore = InMemoryPriceBookStore(),
        reload: @escaping () async throws -> Void = {}
    ) {
        self.budgetStore = budgetStore
        self.pantry = pantry
        self.priceStore = priceStore
        self.priceBook = priceBook
        self.reloadData = reload
    }

    /// Pulls fresh pantry/budget data. Screens call this before reading,
    /// since the stores answer synchronous reads from whatever was loaded
    /// last.
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

    /// The currency every figure on the Impact screen is totalled in.
    ///
    /// The active budget's currency when there is one. With no budget there
    /// is nothing to anchor a currency to, so this falls back to the user's
    /// locale and - failing that - AUD, matching the source branch.
    var displayCurrency: Currency {
        if let budget = budgetStore.activeBudget() { return budget.currency }
        if let code = Locale.current.currency?.identifier,
           let matched = Currency(rawValue: code.uppercased()) {
            return matched
        }
        return .aud
    }

    /// Every time a price is recorded, the price book remembers it under the
    /// ingredient's name too.
    ///
    /// `async throws` because the write is: this used to be a fire-and-forget
    /// call whose failure nothing could observe, so a price could be shown as
    /// remembered when the write had been refused.
    @discardableResult
    func rememberPrice(
        of name: String,
        unit: String,
        unitCost: Money,
        on date: Date = Date()
    ) async throws -> FundsWriteOutcome {
        try await priceBook.record(
            PriceBookEntry(displayName: name, unitCost: unitCost, unit: unit, recordedOn: date)
        )
    }
}

extension FundsEnvironment {
    /// The shipping configuration: budget, spends, waste and prices in the
    /// *same on-device store* as the pantry they value.
    ///
    /// This is what `ContentView` used to get wrong. It called
    /// `.firestore(pantryRepository:)` unconditionally, so a build whose
    /// pantry was a local SwiftData database kept the prices of that pantry's
    /// contents in Firestore - and `AppDependencies`, the one object allowed
    /// to pick a backend, was not consulted at all.
    ///
    /// - Parameters:
    ///   - context: the app's shared `ModelContext`, so a budget and the
    ///     pantry it values are in one store file and one transaction
    ///     boundary.
    ///   - ownerIDProvider: the same uid source the pantry repository uses,
    ///     so an account's money and an account's food agree on whose they
    ///     are.
    @MainActor
    static func swiftData(
        pantryRepository: PantryRepository,
        context: ModelContext,
        ownerIDProvider: @escaping () -> String?
    ) -> FundsEnvironment {
        let budgetStore = SwiftDataBudgetStore(context: context, ownerIDProvider: ownerIDProvider)
        let priceStore = SwiftDataItemPriceStore(context: context, ownerIDProvider: ownerIDProvider)
        let priceBook = SwiftDataPriceBookStore(context: context, ownerIDProvider: ownerIDProvider)
        let pantry = FridgeFitPantryReading(repository: pantryRepository, priceStore: priceStore)
        return FundsEnvironment(
            budgetStore: budgetStore,
            pantry: pantry,
            priceStore: priceStore,
            priceBook: priceBook
        ) {
            try await budgetStore.load()
            try await priceStore.load()
            try await priceBook.load()
            try await pantry.refresh()
        }
    }

    /// Firebase mode: budget, spends, waste and prices saved per user in
    /// Firestore under the same `users/{uid}` root the pantry uses.
    static func firestore(pantryRepository: PantryRepository) -> FundsEnvironment {
        let budgetStore = FirestoreBudgetStore()
        let priceStore = FirestoreItemPriceStore()
        let priceBook = FirestorePriceBookStore()
        let pantry = FridgeFitPantryReading(repository: pantryRepository, priceStore: priceStore)
        return FundsEnvironment(budgetStore: budgetStore, pantry: pantry, priceStore: priceStore, priceBook: priceBook) {
            try await budgetStore.load()
            try await priceStore.load()
            try await priceBook.load()
            try await pantry.refresh()
        }
    }

    /// Nothing saved anywhere, but still reads whichever pantry it is given.
    /// Used by tests and by previews that want a real empty state.
    static func inMemory(pantryRepository: PantryRepository) -> FundsEnvironment {
        let priceStore = InMemoryItemPriceStore()
        let pantry = FridgeFitPantryReading(repository: pantryRepository, priceStore: priceStore)
        return FundsEnvironment(budgetStore: InMemoryBudgetStore(), pantry: pantry, priceStore: priceStore) {
            try await pantry.refresh()
        }
    }

    /// Seeded stores and a sample fridge, **for SwiftUI previews only**.
    ///
    /// Kept separate from every production factory on purpose: nothing in the
    /// shipping app can reach these figures, so a preview number can never be
    /// mistaken for the user's own.
    static func sample(now: Date = Date()) -> FundsEnvironment {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -2, to: now) ?? now

        let budget = FoodBudget(limit: Money(120, .aud), cadence: .weekly, startDate: start)
        let seededSpends = [
            GrocerySpend(amount: Money(35, .aud), spentOn: start, store: "Woolworths"),
            GrocerySpend(
                amount: Money(18, .aud),
                spentOn: calendar.date(byAdding: .day, value: 1, to: start) ?? start,
                store: "Coles"
            )
        ]

        let budgetStore = InMemoryBudgetStore(budget: budget, spends: seededSpends)
        let pantry = InMemoryPantryReading.sample(currency: .aud, now: now)
        return FundsEnvironment(budgetStore: budgetStore, pantry: pantry)
    }
}
