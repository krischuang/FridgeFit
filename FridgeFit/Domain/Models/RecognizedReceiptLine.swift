//
//  RecognizedReceiptLine.swift
//  FridgeFit
//

import Foundation

/// One line of text read off a receipt photo, before any interpretation.
///
/// This is the boundary type between Vision and the rest of the app: it
/// carries what was read and where it sat on the page, and nothing about
/// what the text *means*. Deciding that a line is a product, or food, or an
/// ingredient, happens further down the pipeline.
///
/// `confidence` is Vision's own OCR score - a real measurement of how sure
/// the text recogniser is about the characters, not a judgement about the
/// product. It is used to drop unreadable lines, never shown to the user as
/// a confidence in an ingredient.
struct RecognizedReceiptLine: Equatable {
    /// The text exactly as Vision read it, untrimmed of meaning.
    let text: String
    /// Vision's OCR confidence for this line, `nil` if unavailable.
    let confidence: Float?
    /// Reading order down the page, starting at 0. Receipts are read
    /// top-to-bottom, and quantity/price lines often refer to the line
    /// above, so order is information worth keeping.
    let order: Int

    init(text: String, confidence: Float? = nil, order: Int) {
        self.text = text
        self.confidence = confidence
        self.order = order
    }
}

/// Everything OCR could read from one receipt photo.
struct RecognizedReceiptText: Equatable {
    /// Lines in reading order, top of the receipt first.
    let lines: [RecognizedReceiptLine]

    init(lines: [RecognizedReceiptLine]) {
        self.lines = lines
    }

    var isEmpty: Bool { lines.isEmpty }

    static let empty = RecognizedReceiptText(lines: [])
}
