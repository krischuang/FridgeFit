//
//  FridgeImageAnalyzer.swift
//  FridgeFit
//

import CoreGraphics
import ImageIO

/// One thing the image analyser saw, with how sure Vision was about it.
///
/// `confidence` here *is* a real model score (unlike
/// `ModelStatedConfidence`), but it describes a visual label such as
/// "bottle" or "citrus fruit", not an ingredient - which is exactly why it
/// still goes through the language model before FridgeFit calls anything an
/// ingredient.
struct ObservedVisualLabel: Equatable {
    let identifier: String
    let confidence: Float

    init(identifier: String, confidence: Float) {
        self.identifier = identifier
        self.confidence = confidence
    }
}

/// What on-device image analysis could see in a fridge photo, before any
/// language model reasoning.
struct FridgeImageEvidence: Equatable {
    /// Visual classifications, highest confidence first.
    let labels: [ObservedVisualLabel]
    /// Text read off packaging and labels - brand names, "semi-skimmed",
    /// and so on.
    let recognizedText: [String]

    init(labels: [ObservedVisualLabel], recognizedText: [String]) {
        self.labels = labels
        self.recognizedText = recognizedText
    }

    var isEmpty: Bool { labels.isEmpty && recognizedText.isEmpty }

    static let empty = FridgeImageEvidence(labels: [], recognizedText: [])
}

/// Abstraction over on-device image analysis, so
/// `AppleIngredientRecognitionService` can be reasoned about (and stubbed)
/// without running Vision.
protocol FridgeImageAnalyzer {
    /// Extracts visual evidence from a photo. Runs entirely on-device.
    func analyze(
        image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> FridgeImageEvidence
}
