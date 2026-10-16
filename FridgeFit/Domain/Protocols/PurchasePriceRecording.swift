//
//  PurchasePriceRecording.swift
//  FridgeFit
//

import Foundation

// Somewhere to send "this item cost this much" when a scanned receipt item goes
// into the pantry. The scanner doesn't know or care who keeps prices - right now
// it's FridgeFunds (the Budget tab), which turns it into money-in-your-fridge.
protocol PurchasePriceRecording: AnyObject {
    // `total` is what the receipt line said, for the whole quantity in `item`.
    func recordPurchasePrice(_ total: Decimal, for item: PantryItem)
}
