//
//  ReceiptTextRecognizer.swift
//  FridgeFit
//

import CoreGraphics
import ImageIO

/// Reads the text off a receipt photo.
///
/// Abstracted so `ScanReceiptUseCase` can be driven from a unit test with a
/// fixed block of receipt text, with no Vision, no camera and no device.
/// That is most of what makes this feature testable: everything after OCR is
/// text in, text out.
///
/// Implementations do OCR and nothing else. They must not try to classify,
/// filter or interpret what they read - a recogniser that decided "TOTAL" is
/// not a product would be making a judgement that belongs to
/// `ReceiptLineParser`, where it can be tested in isolation.
protocol ReceiptTextRecognizer {
    /// Reads text from a receipt photo, in top-to-bottom reading order.
    ///
    /// - Parameters:
    ///   - image: The photo to read.
    ///   - orientation: How `image` should be rotated before reading -
    ///     camera captures are rarely upright, and sideways text costs
    ///     nearly every line.
    /// - Throws: `ReceiptScanError`, never a framework-specific error type.
    func recognizeText(
        in image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> RecognizedReceiptText
}
