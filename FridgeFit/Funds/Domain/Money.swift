//
//  Money.swift
//  FridgeFit
//

import Foundation

// A currency a food budget can be tracked in. Kept explicit on every amount rather
// than assuming one locale, since international students often think in more than
// one currency.
nonisolated enum Currency: String, Codable, CaseIterable, Sendable {
    case aud = "AUD"
    case usd = "USD"
    case cny = "CNY"
    case gbp = "GBP"
    case eur = "EUR"

    // The symbol shown next to amounts in this currency.
    var symbol: String {
        switch self {
        case .aud, .usd: return "$"
        case .cny: return "¥"
        case .gbp: return "£"
        case .eur: return "€"
        }
    }
}

// An amount of money tagged with the currency it's in.
nonisolated struct Money: Hashable, Codable, Sendable {
    let amount: Decimal
    let currency: Currency

    init(_ amount: Decimal, _ currency: Currency) {
        self.amount = amount
        self.currency = currency
    }

    // Zero money in the given currency.
    static func zero(in currency: Currency) -> Money {
        Money(0, currency)
    }

    // Whether this amount is strictly greater than zero.
    var isPositive: Bool { amount > 0 }
}


nonisolated extension Money {
    // Adds two amounts. Both must be in the same currency.
    static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency,
                     "Cannot add \(rhs.currency) to \(lhs.currency)")
        return Money(lhs.amount + rhs.amount, lhs.currency)
    }

    // Subtracts `rhs` from `lhs`. Both must be in the same currency. Can return a
    // negative amount — that's how an overspent budget is represented.
    static func - (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency,
                     "Cannot subtract \(rhs.currency) from \(lhs.currency)")
        return Money(lhs.amount - rhs.amount, lhs.currency)
    }

    // Splits an amount evenly across a number of days, e.g. a weekly budget into a
    // daily allowance.
    func dividedEvenly(by divisor: Int) -> Money {
        precondition(divisor > 0, "divisor must be positive")
        return Money(amount / Decimal(divisor), currency)
    }

    // Scales an amount by a factor, e.g. unit cost times quantity on hand.
    func scaled(by factor: Decimal) -> Money {
        Money(amount * factor, currency)
    }
}


nonisolated extension Money: Comparable {
    static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currency == rhs.currency,
                     "Cannot compare \(lhs.currency) with \(rhs.currency)")
        return lhs.amount < rhs.amount
    }
}


nonisolated extension Money {
    // Formats the amount with its currency symbol, e.g. `"$12.50"` or `"-$3.00"`.
    func formatted() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let magnitude = NSDecimalNumber(decimal: abs(amount))
        let digits = formatter.string(from: magnitude) ?? "\(abs(amount))"
        let sign = amount < 0 ? "-" : ""
        return "\(sign)\(currency.symbol)\(digits)"
    }
}
