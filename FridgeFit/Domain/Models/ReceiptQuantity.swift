//
//  ReceiptQuantity.swift
//  FridgeFit
//

import Foundation

/// A quantity that was actually written on the receipt.
///
/// Exists as its own type so "unknown" can be `nil` rather than a magic
/// default. A receipt line like `MUSHROOM CUP` carries no quantity at all,
/// and the honest representation of that is the absence of a value - not
/// `1 pcs`, which is a number the user never saw and would have to notice
/// and correct.
struct ReceiptQuantity: Equatable {
    let value: Double
    let unit: MeasurementUnit

    init(value: Double, unit: MeasurementUnit) {
        self.value = value
        self.unit = unit
    }

    var formatted: String { unit.formatted(value) }
}
