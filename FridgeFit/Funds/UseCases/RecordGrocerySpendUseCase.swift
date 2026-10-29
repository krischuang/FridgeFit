//
//  RecordGrocerySpendUseCase.swift
//  FridgeFit
//

import Foundation

// Logs a grocery purchase against the active budget. Deliberately does not block a
// spend that pushes the user over budget: going over is surfaced later as a
// supportive warning (see ``EvaluateBudgetStatusUseCase``), never as a failure
// here — the user stays in control of their own money.
struct RecordGrocerySpendUseCase {
    let budgetStore: BudgetStore

    // Failures that stop a spend from being recorded at all.
    enum Failure: LocalizedError, Equatable {
        // The entered amount was zero or negative.
        case amountNotPositive
        // No budget has been set, so there is nothing to record the spend against.
        case noActiveBudgetPeriod
        // The purchase date is later than today.
        case purchaseDatedInFuture
        // The spend's currency differs from the budget's currency.
        case currencyMismatch(expected: Currency, got: Currency)

        var errorDescription: String? {
            switch self {
            case .amountNotPositive:
                return "Enter a spend amount greater than zero."
            case .noActiveBudgetPeriod:
                return "Set a food budget first so we can track this spend."
            case .purchaseDatedInFuture:
                return "This purchase is dated in the future. Check the date and try again."
            case .currencyMismatch(let expected, let got):
                return "This spend is in \(got.rawValue) but your budget is in \(expected.rawValue). Log it in \(expected.rawValue)."
            }
        }
    }

    // What happened to a recorded spend: the spend itself, and whether the
    // store has it confirmed or queued.
    nonisolated struct Recorded: Equatable {
        let spend: GrocerySpend
        let outcome: FundsWriteOutcome
    }

    // Validates and records a grocery spend.
    // - Returns: the ``GrocerySpend`` and the write's real outcome. `async`
    //   because the write is: this used to return the moment the store had
    //   updated its in-memory copy, which for Firestore was before the write
    //   had been accepted - so a rejected spend still counted against the
    //   budget on screen.
    // - Throws: ``Failure`` when the spend is invalid, or the store's own
    //   error when it could not be written at all.
    @discardableResult
    func execute(amount: Money,
                 spentOn: Date = Date(),
                 store storeName: String? = nil,
                 purchasedItemIDs: [PantryItemID] = [],
                 note: String? = nil,
                 now: Date = Date()) async throws -> Recorded {
        guard amount.isPositive else { throw Failure.amountNotPositive }
        guard let budget = budgetStore.activeBudget() else { throw Failure.noActiveBudgetPeriod }
        guard amount.currency == budget.currency else {
            throw Failure.currencyMismatch(expected: budget.currency, got: amount.currency)
        }
        let calendar = Calendar.current
        if calendar.startOfDay(for: spentOn) > calendar.startOfDay(for: now) {
            throw Failure.purchaseDatedInFuture
        }

        let spend = GrocerySpend(amount: amount,
                                 spentOn: spentOn,
                                 store: storeName,
                                 purchasedItemIDs: purchasedItemIDs,
                                 note: note)
        let outcome = try await budgetStore.addSpend(spend)
        return Recorded(spend: spend, outcome: outcome)
    }
}
