//
//  ReceiptLineItem.swift
//  FridgeFit
//

import Foundation

/// A receipt line that survived cleanup and looks like it could be a
/// purchased product.
///
/// "Could be" is the important part. `ReceiptLineParser` only removes what
/// is unambiguously *not* a product - totals, payment lines, store
/// metadata - and strips the trailing price so the description reads
/// cleanly. It deliberately does not try to decide whether the product is
/// food; that judgement needs language understanding and belongs to
/// `ReceiptIngredientInterpreter`.
///
/// `originalText` is never thrown away. The interpreter sees it, the review
/// screen can show it so the user can check a detection against their actual
/// receipt, and it is the key the interpreter's answers are matched back on.
struct ReceiptLineItem: Equatable {
    /// The line exactly as OCR read it, including any price.
    let originalText: String
    /// `originalText` with the trailing price and line noise removed, which
    /// is what a human would call the product description.
    let productDescription: String
    /// The trailing price, when one was parsed. Not used to decide anything
    /// today - kept because it is strong evidence a line really is a
    /// purchased product.
    let price: Double?
    /// Reading order down the page, preserved from OCR.
    let order: Int

    init(originalText: String, productDescription: String, price: Double? = nil, order: Int) {
        self.originalText = originalText
        self.productDescription = productDescription
        self.price = price
        self.order = order
    }
}
