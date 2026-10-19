//
//  RecipeCostEstimate.swift
//  FridgeFit
//

import Foundation

// what one recipe ingredient costs, split into the part you already have and
// the part you'd still need to buy
struct RecipeCostLine: Identifiable, Hashable {
    let id: UUID
    let name: String
    let role: IngredientRole
    // value of what you'd use up from the pantry
    let fromPantry: Money
    // estimated cost of what you'd still have to buy
    let toBuy: Money
    // set when some or all of this ingredient couldn't be priced
    let unpricedReason: String?

    var isPriced: Bool { unpricedReason == nil }
}

// the whole recipe. totals only count essential ingredients - optional ones are
// in `lines` so you can see them, but garnish shouldn't move the number.
struct RecipeCostEstimate: Hashable {
    let lines: [RecipeCostLine]
    let fromPantry: Money
    let toBuy: Money
    // nil when the recipe doesn't say how many it serves
    let perServing: Money?
    // essential ingredients we couldn't put a price on
    let unpricedNames: [String]
    // what's left in the current budget period, nil if no budget is set
    let remainingBudget: Money?
    let budgetCadence: BudgetCadence?

    var total: Money { fromPantry + toBuy }
    // only a partial number while something's unpriced
    var isComplete: Bool { unpricedNames.isEmpty }

    // nil when there's no budget to compare against
    var fitsRemainingBudget: Bool? {
        remainingBudget.map { toBuy <= $0 }
    }
}
