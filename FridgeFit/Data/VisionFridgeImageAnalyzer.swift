//
//  VisionFridgeImageAnalyzer.swift
//  FridgeFit
//

import CoreGraphics
import Foundation
import ImageIO
import OSLog
import Vision

/// `FridgeImageAnalyzer` backed by Apple's Vision framework.
///
/// Runs two on-device requests over the photo and returns what they saw
/// without interpreting it:
///
/// - `ClassifyImageRequest` for visual labels ("bottle", "citrus fruit").
/// - `RecognizeTextRequest` for text on packaging, which is often the only
///   way to tell semi-skimmed milk from orange juice in a carton.
///
/// Vision alone isn't enough to fill a pantry: its taxonomy is generic
/// scene/object labels, not FridgeFit ingredients. Turning this evidence
/// into normalized ingredient names is
/// `AppleIngredientRecognitionService`'s job. Nothing here leaves the
/// device.
struct VisionFridgeImageAnalyzer: FridgeImageAnalyzer {
    /// Labels below this score are dropped - the tail of a Vision
    /// classification is mostly noise, and feeding it to a language model
    /// invites hallucination.
    private let minimumLabelConfidence: Float
    /// Caps how much evidence is forwarded, both to keep the prompt inside
    /// the model's context window and to stay on the confident labels.
    private let maximumLabelCount: Int
    private let maximumTextCount: Int
    private let logger = Logger(subsystem: "com.fridgefit.app", category: "VisionFridgeImageAnalyzer")

    init(
        minimumLabelConfidence: Float = 0.08,
        maximumLabelCount: Int = 30,
        maximumTextCount: Int = 25
    ) {
        self.minimumLabelConfidence = minimumLabelConfidence
        self.maximumLabelCount = maximumLabelCount
        self.maximumTextCount = maximumTextCount
    }

    func analyze(
        image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> FridgeImageEvidence {
        // Independent requests over the same pixels, so run them together
        // and let the slower one set the pace.
        async let classifications = classify(image: image, orientation: orientation)
        async let recognizedText = recognizeText(in: image, orientation: orientation)
        return FridgeImageEvidence(labels: try await classifications, recognizedText: try await recognizedText)
    }

    private func classify(
        image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> [ObservedVisualLabel] {
        var request = ClassifyImageRequest()
        // A fridge shelf fills the frame, so classify the whole photo
        // rather than a centre crop.
        request.cropAndScaleAction = .scaleToFill

        do {
            let observations = try await request.perform(on: image, orientation: orientation)
            return observations
                .filter { $0.confidence >= minimumLabelConfidence }
                .sorted { $0.confidence > $1.confidence }
                .prefix(maximumLabelCount)
                .map { ObservedVisualLabel(identifier: $0.identifier, confidence: $0.confidence) }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.error("Image classification failed: \(error.localizedDescription, privacy: .public)")
            throw IngredientRecognitionError.invalidImage
        }
    }

    /// OCR is a bonus signal, not a requirement - a fridge photo with no
    /// legible packaging is perfectly normal, so a failure here degrades to
    /// "no text" instead of failing the whole scan.
    private func recognizeText(
        in image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        do {
            let observations = try await request.perform(on: image, orientation: orientation)
            let strings = observations
                .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 2 }
            return Array(deduplicatingCaseInsensitively(strings).prefix(maximumTextCount))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.notice("Text recognition failed, continuing without OCR: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func deduplicatingCaseInsensitively(_ strings: [String]) -> [String] {
        var seen: Set<String> = []
        return strings.filter { seen.insert($0.lowercased()).inserted }
    }
}
