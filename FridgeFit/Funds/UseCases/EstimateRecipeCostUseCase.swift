//
//  EstimateRecipeCostUseCase.swift
//  FridgeFit
//

import Foundation

// works out roughly what a recipe costs, from prices the user actually recorded:
//
// - in the pantry with a price: the bit you'd use is costed at that price, and
//   if there isn't enough, the shortfall is costed at the same price
// - in the pantry without a price, or not there at all: falls back to the
//   price book (last price paid for that ingredient name)
// - nothing anywhere: listed as "no price yet" instead of guessed
//
// units are converted the same safe way feasibility does it (g/kg, ml/L); a
// pair that doesn't convert is left unpriced rather than made up. it's an
// estimate and the UI says so - but every number comes from something the
// user paid, never a made-up average.
struct EstimateRecipeCostUseCase {
    let pantry: PantryReading
    let priceBook: PriceBookStore
    let budgetStore: BudgetStore

    func execute(recipe: Recipe, now: Date = Date()) -> RecipeCostEstimate {
        let currency = budgetStore.activeBudget()?.currency ?? .aud
        let pantryItems = pantry.allItems()
        let lines = recipe.ingredients.map { line(for: $0, pantryItems: pantryItems, currency: currency) }

        let essential = lines.filter { $0.role == .essential }
        let fromPantry = essential.reduce(Money.zero(in: currency)) { $0 + $1.fromPantry }
        let toBuy = essential.reduce(Money.zero(in: currency)) { $0 + $1.toBuy }

        var perServing: Money?
        if let servings = recipe.servings, servings > 0 {
            perServing = Self.roundedToCents((fromPantry + toBuy).dividedEvenly(by: servings))
        }

        // only compare against a budget that's actually set
        let status = try? EvaluateBudgetStatusUseCase(budgetStore: budgetStore).execute(now: now)

        return RecipeCostEstimate(
            lines: lines,
            fromPantry: fromPantry,
            toBuy: toBuy,
            perServing: perServing,
            unpricedNames: essential.filter { !$0.isPriced }.map(\.name),
            remainingBudget: status?.remaining,
            budgetCadence: status?.budget.cadence
        )
    }

    // a price for some number of `unit`
    private typealias Price = (cost: Money, unit: MeasurementUnit)

    private func line(for ingredient: RecipeIngredient, pantryItems: [PantryItemSnapshot], currency: Currency) -> RecipeCostLine {
        let name = ingredient.ingredient.name
        let zero = Money.zero(in: currency)
        let bookPrice = priceBookPrice(for: name, currency: currency)

        func make(fromPantry: Money?, toBuy: Money?, reason: String?) -> RecipeCostLine {
            RecipeCostLine(id: ingredient.id, name: name, role: ingredient.role,
                           fromPantry: fromPantry ?? zero, toBuy: toBuy ?? zero, unpricedReason: reason)
        }

        guard let item = pantryItems.first(where: { PriceBookEntry.key(for: $0.name) == PriceBookEntry.key(for: name) }) else {
            // not in the pantry - the whole amount has to be bought
            guard let bookPrice, let cost = Self.cost(of: ingredient.quantity, in: ingredient.unit, at: bookPrice) else {
                return make(fromPantry: nil, toBuy: nil, reason: bookPrice == nil ? "No price yet" : "Can't compare units")
            }
            return make(fromPantry: nil, toBuy: cost, reason: nil)
        }

        guard
            let pantryUnit = MeasurementUnit(rawValue: item.unit),
            let needed = MeasurementUnit.convert(quantity: ingredient.quantity, from: ingredient.unit, to: pantryUnit)
        else {
            return make(fromPantry: nil, toBuy: nil, reason: "Can't compare units")
        }

        let used = min(needed, item.quantity)
        let short = max(needed - item.quantity, 0)
        // your own price for this item beats the price book
        let pantryPrice: Price? = item.unitCost.flatMap { $0.currency == currency ? (cost: $0, unit: pantryUnit) : nil }
        let price = pantryPrice ?? bookPrice

        let fromPantry = used > 0 ? price.flatMap { Self.cost(of: used, in: pantryUnit, at: $0) } : zero
        let toBuy = short > 0 ? price.flatMap { Self.cost(of: short, in: pantryUnit, at: $0) } : zero

        if fromPantry == nil || toBuy == nil {
            return make(fromPantry: fromPantry, toBuy: toBuy, reason: price == nil ? "No price yet" : "Can't compare units")
        }
        return make(fromPantry: fromPantry, toBuy: toBuy, reason: nil)
    }

    private func priceBookPrice(for name: String, currency: Currency) -> Price? {
        guard
            let entry = priceBook.entry(forIngredientNamed: name),
            entry.unitCost.currency == currency,
            let unit = MeasurementUnit(rawValue: entry.unit)
        else { return nil }
        return (cost: entry.unitCost, unit: unit)
    }

    // `quantity` of `unit` at `price`, or nil if the units don't convert
    private static func cost(of quantity: Double, in unit: MeasurementUnit, at price: Price) -> Money? {
        guard let converted = MeasurementUnit.convert(quantity: quantity, from: unit, to: price.unit) else { return nil }
        // through a string so 0.03 stays 0.03 instead of 0.0299999...
        let factor = Decimal(string: "\(converted)", locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(converted)
        return roundedToCents(price.cost.scaled(by: factor))
    }

    static func roundedToCents(_ money: Money) -> Money {
        var value = money.amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return Money(rounded, money.currency)
    }
}
