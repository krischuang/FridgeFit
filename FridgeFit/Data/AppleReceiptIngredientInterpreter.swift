//
//  AppleReceiptIngredientInterpreter.swift
//  FridgeFit
//

import Foundation
import FoundationModels
import OSLog

/// `ReceiptIngredientInterpreter` backed by Apple Intelligence, running
/// entirely on-device.
///
/// ## Text in, text out
///
/// This type never sees the receipt photo. It receives
/// `ReceiptLineItem`s - strings that `VisionReceiptTextRecognizer` read and
/// `ReceiptLineParser` cleaned - and asks `SystemLanguageModel` what each
/// one is, via guided generation into `GeneratedReceiptInterpretation`.
///
/// That is not a workaround, it is the right shape for the problem. The
/// `FoundationModels` framework in the iOS 26 SDK is text-only
/// (`Transcript.Segment` is `.text` or `.structure`, and every `respond`
/// overload takes a `Prompt` or a `String`), and reading
/// `CHKN BREAST 500G` is a language task anyway. Vision does the reading;
/// the language model does the understanding.
///
/// ## Why the work is chunked
///
/// Lines are sent in small batches rather than as one long receipt. A
/// shorter prompt keeps the model anchored to the lines in front of it -
/// faithfully echoing forty lines in order is exactly the kind of task
/// where a model starts paraphrasing, skipping and merging - and it keeps
/// a long receipt from crowding the context window. Each batch gets a
/// fresh session, so one batch's answers cannot bleed into the next.
///
/// Nothing leaves the device.
struct AppleReceiptIngredientInterpreter: ReceiptIngredientInterpreter {
    /// Lines per model request. Small enough that the model reliably
    /// returns one entry per line in order.
    private static let batchSize = 12
    /// Upper bound on lines interpreted from a single receipt, so an
    /// unusually long receipt can't run for minutes.
    private static let maximumLineCount = 84

    private let model: SystemLanguageModel
    private let promptBuilder: ReceiptInterpretationPromptBuilder
    private let logger = Logger(subsystem: "com.fridgefit.app", category: "AppleReceiptIngredientInterpreter")

    init(
        model: SystemLanguageModel = .default,
        promptBuilder: ReceiptInterpretationPromptBuilder = ReceiptInterpretationPromptBuilder()
    ) {
        self.model = model
        self.promptBuilder = promptBuilder
    }

    /// Maps `SystemLanguageModel.Availability` onto FridgeFit's own states.
    ///
    /// Read fresh every time: the user can enable Apple Intelligence, or
    /// the model assets can finish downloading, while the app is running.
    var availability: AppleIntelligenceAvailability {
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

    func interpret(lineItems: [ReceiptLineItem]) async throws -> ReceiptInterpretationResult {
        let availability = self.availability
        guard availability.canScan else {
            throw ReceiptScanError.scanUnavailable(availability)
        }

        let considered = Array(lineItems.prefix(Self.maximumLineCount))
        guard !considered.isEmpty else { return .empty }

        var items: [RawInterpretedReceiptItem] = []
        for batch in considered.chunked(into: Self.batchSize) {
            try Task.checkCancellation()
            items.append(contentsOf: try await interpretBatch(batch))
        }

        return ReceiptInterpretationResult(items: items)
    }

    private func interpretBatch(_ batch: [ReceiptLineItem]) async throws -> [RawInterpretedReceiptItem] {
        guard let prompt = promptBuilder.makePrompt(for: batch) else { return [] }

        let session = LanguageModelSession(model: model) {
            ReceiptInterpretationPromptBuilder.instructions
        }

        do {
            let response = try await session.respond(
                to: Prompt(prompt),
                generating: GeneratedReceiptInterpretation.self,
                // Low temperature: this is an extraction task, and
                // creativity here means invented groceries.
                options: GenerationOptions(temperature: 0.1)
            )
            return response.content.rawItems
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.mapped(error, logger: logger)
        } catch {
            logger.error("Receipt interpretation failed: \(error.localizedDescription, privacy: .public)")
            throw ReceiptScanError.interpretationFailed
        }
    }

    /// Collapses the SDK's generation errors into the handful of outcomes a
    /// user can act on. Details go to the log, not the screen.
    private static func mapped(
        _ error: LanguageModelSession.GenerationError,
        logger: Logger
    ) -> ReceiptScanError {
        logger.error("Generation failed: \(String(describing: error), privacy: .public)")

        switch error {
        case .rateLimited, .concurrentRequests:
            return .modelBusy
        case .guardrailViolation, .refusal:
            return .requestNotAllowed
        case .assetsUnavailable:
            return .scanUnavailable(.modelNotReady)
        case .exceededContextWindowSize, .unsupportedGuide, .unsupportedLanguageOrLocale, .decodingFailure:
            return .interpretationFailed
        @unknown default:
            return .interpretationFailed
        }
    }
}

extension Array {
    /// Splits into consecutive batches of at most `size`, keeping order.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
