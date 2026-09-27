//
//  AppleIngredientRecognitionService.swift
//  FridgeFit
//

import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
import OSLog

/// `IngredientRecognitionService` backed by Apple Intelligence, running
/// entirely on-device.
///
/// ## Two stages, both local
///
/// 1. `FridgeImageAnalyzer` (Vision) extracts what can be *seen*: visual
///    labels plus any text on packaging.
/// 2. `SystemLanguageModel` turns that evidence into normalized FridgeFit
///    ingredient names via guided generation into
///    `GeneratedFridgeInventory`.
///
/// ## Why the image isn't sent to the language model
///
/// The `FoundationModels` framework in the iOS 26 SDK is text-only. Its
/// `Transcript.Segment` is `.text` or `.structure`, `Prompt` is built from
/// text, and there is no attachment or image input type anywhere in the
/// framework - so there is no supported way to hand `CGImage` to
/// `LanguageModelSession`. Vision does the seeing; the language model does
/// the naming.
///
/// The image never leaves the device, and is never base64-encoded into the
/// prompt - it isn't in the prompt at all, only Vision's findings about it.
/// If a future SDK adds real multimodal prompt input, this is the only type
/// that changes: `recognizeIngredients(from:orientation:)` would pass the
/// image itself instead of `evidence`, and everything above this service -
/// normalization, review, pantry insertion - stays as it is.
struct AppleIngredientRecognitionService: IngredientRecognitionService {
    private let model: SystemLanguageModel
    private let imageAnalyzer: FridgeImageAnalyzer
    private let promptBuilder: IngredientDetectionPromptBuilder
    private let logger = Logger(subsystem: "com.fridgefit.app", category: "AppleIngredientRecognitionService")

    init(
        model: SystemLanguageModel = .default,
        imageAnalyzer: FridgeImageAnalyzer = VisionFridgeImageAnalyzer(),
        promptBuilder: IngredientDetectionPromptBuilder = IngredientDetectionPromptBuilder()
    ) {
        self.model = model
        self.imageAnalyzer = imageAnalyzer
        self.promptBuilder = promptBuilder
    }

    /// Maps `SystemLanguageModel.Availability` onto FridgeFit's own states.
    ///
    /// Read fresh every time: the user can enable Apple Intelligence, or
    /// the model assets can finish downloading, while the app is running.
    var availability: IngredientRecognitionAvailability {
        switch model.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.deviceNotEligible):
            return .deviceNotSupported
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable(let reason):
            // A reason this build doesn't know about. Fail closed rather
            // than assuming a scan would work.
            logger.notice("Unrecognised model unavailability: \(String(describing: reason), privacy: .public)")
            return .unavailableForUnknownReason
        }
    }

    func recognizeIngredients(
        from image: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> IngredientDetectionResult {
        let availability = self.availability
        guard availability.canScan else {
            throw IngredientRecognitionError.recognitionUnavailable(availability)
        }

        let evidence = try await imageAnalyzer.analyze(image: image, orientation: orientation)
        try Task.checkCancellation()

        guard let prompt = promptBuilder.makePrompt(for: evidence) else {
            // Vision found nothing at all. Asking the model anyway would
            // only get us a guessed fridge.
            return .empty
        }

        let session = LanguageModelSession(model: model) {
            IngredientDetectionPromptBuilder.instructions
        }

        do {
            let response = try await session.respond(
                to: Prompt(prompt),
                generating: GeneratedFridgeInventory.self,
                // Low temperature: this is an extraction task, and
                // creativity here means invented food.
                options: GenerationOptions(temperature: 0.1)
            )
            return IngredientDetectionResult(ingredients: response.content.rawDetections)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapped(error, logger: logger)
        } catch {
            logger.error("Fridge scan failed: \(error.localizedDescription, privacy: .public)")
            throw IngredientRecognitionError.recognitionFailed
        }
    }

    /// Collapses the SDK's generation errors into the handful of outcomes a
    /// user can act on. Details go to the log, not the screen.
    private static func mapped(
        _ error: LanguageModelSession.GenerationError,
        logger: Logger
    ) -> IngredientRecognitionError {
        logger.error("Generation failed: \(String(describing: error), privacy: .public)")

        switch error {
        case .rateLimited, .concurrentRequests:
            return .modelBusy
        case .guardrailViolation, .refusal:
            return .requestNotAllowed
        case .assetsUnavailable:
            return .recognitionUnavailable(.modelNotReady)
        case .exceededContextWindowSize, .unsupportedGuide, .unsupportedLanguageOrLocale, .decodingFailure:
            return .recognitionFailed
        @unknown default:
            return .recognitionFailed
        }
    }
}
