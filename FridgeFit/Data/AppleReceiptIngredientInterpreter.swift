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
///
/// ## Why there are two deadlines
///
/// Neither bound existed before, and a receipt scan was the longest-running
/// model call in the app with nothing at all to stop it. `respond` does not
/// time out on its own, and on a device that reports a model it has no assets
/// for it never returns - so the scan spinner had no exit.
///
/// A single per-request bound is not enough here, because one scan is up to
/// `maximumLineCount / batchSize` requests. A 20s bound on each would let a
/// slow device sit at 140s and still be "within timeout". So each batch is
/// bounded by `batchTimeout`, and the whole receipt is bounded by
/// `overallTimeout`; whichever is tighter at that moment applies.
nonisolated struct AppleReceiptIngredientInterpreter: ReceiptIngredientInterpreter {
    /// Lines per model request. Small enough that the model reliably
    /// returns one entry per line in order.
    private static let batchSize = 12
    /// Upper bound on lines interpreted from a single receipt, so an
    /// unusually long receipt can't run for minutes.
    private static let maximumLineCount = 84
    /// How long one batch of lines may take.
    static let batchTimeout: Duration = .seconds(20)
    /// How long the whole receipt may take, across every batch.
    static let overallTimeout: Duration = .seconds(45)

    /// One batch of lines, interpreted.
    ///
    /// A function rather than a hard call to `LanguageModelSession` so the
    /// batching, deadline and part-finished-receipt rules below can be
    /// exercised without an Apple Intelligence device - including the case
    /// that matters most and is impossible to stage with the real SDK, a
    /// generation that never returns and ignores cancellation. The default
    /// is the real on-device call, so production behaviour is unchanged.
    typealias BatchInterpreting = @Sendable (_ prompt: String) async throws -> [RawInterpretedReceiptItem]

    private let model: SystemLanguageModel
    private let promptBuilder: ReceiptInterpretationPromptBuilder
    private let batchTimeout: Duration
    private let overallTimeout: Duration
    private let interpretPrompt: BatchInterpreting
    private let logger = Logger(subsystem: "com.fridgefit.app", category: "AppleReceiptIngredientInterpreter")

    init(
        model: SystemLanguageModel = .default,
        promptBuilder: ReceiptInterpretationPromptBuilder = ReceiptInterpretationPromptBuilder(),
        batchTimeout: Duration = Self.batchTimeout,
        overallTimeout: Duration = Self.overallTimeout,
        interpretPrompt: BatchInterpreting? = nil
    ) {
        self.model = model
        self.promptBuilder = promptBuilder
        self.batchTimeout = batchTimeout
        self.overallTimeout = overallTimeout
        self.interpretPrompt = interpretPrompt ?? Self.onDeviceGeneration(model: model)
    }

    /// The real thing: one guided generation per prompt, on-device.
    private static func onDeviceGeneration(model: SystemLanguageModel) -> BatchInterpreting {
        { prompt in
            // The session is built here rather than captured:
            // `LanguageModelSession` isn't `Sendable`, while
            // `SystemLanguageModel` and the prompt string are. Same reasoning
            // as `AppleSubstitutionService`.
            let session = LanguageModelSession(model: model) {
                ReceiptInterpretationPromptBuilder.instructions
            }

            let response = try await session.respond(
                to: Prompt(prompt),
                generating: GeneratedReceiptInterpretation.self,
                // Low temperature: this is an extraction task, and
                // creativity here means invented groceries.
                options: GenerationOptions(temperature: 0.1)
            )
            return response.content.rawItems
        }
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
        return try await interpretBatches(of: lineItems)
    }

    /// Everything `interpret` does except the availability gate.
    ///
    /// Split out so the batching and deadline rules can be tested on a
    /// machine whose `availability` answer is not under the test's control -
    /// the simulator reports `.available` without having any model assets,
    /// so a test that went through `interpret` would be asserting on the
    /// host's Apple Intelligence state as much as on this code.
    func interpretBatches(of lineItems: [ReceiptLineItem]) async throws -> ReceiptInterpretationResult {
        let considered = Array(lineItems.prefix(Self.maximumLineCount))
        guard !considered.isEmpty else { return .empty }

        let deadline = ContinuousClock.now + overallTimeout
        var items: [RawInterpretedReceiptItem] = []

        for batch in considered.chunked(into: Self.batchSize) {
            try Task.checkCancellation()

            let remaining = deadline - ContinuousClock.now
            // The whole-receipt budget is spent. Treated exactly like a
            // batch that timed out, so there is one rule below for "we ran
            // out of time" rather than two.
            let allowance = remaining > .zero ? min(batchTimeout, remaining) : .zero

            guard allowance > .zero else {
                return try partialResult(items, droppedAfter: items.count, reason: "overall budget exhausted")
            }

            do {
                items.append(contentsOf: try await interpretBatch(batch, timeout: allowance))
            } catch ReceiptScanError.timeout {
                return try partialResult(items, droppedAfter: items.count, reason: "batch timed out")
            }
        }

        return ReceiptInterpretationResult(items: items)
    }

    /// What to do when time ran out partway through a receipt.
    ///
    /// Anything already interpreted is kept and returned. That is not a
    /// silent truncation: the next thing that happens to this result is the
    /// review screen, where the user sees the exact list of items and
    /// confirms it before a single one reaches the pantry, so a short list is
    /// visible as a short list and the rest can be typed in. Throwing the
    /// whole scan away instead would discard good work the user can see and
    /// use.
    ///
    /// With nothing interpreted at all there is nothing to show, so the
    /// timeout surfaces as an error with a retry.
    private func partialResult(
        _ items: [RawInterpretedReceiptItem],
        droppedAfter interpreted: Int,
        reason: String
    ) throws -> ReceiptInterpretationResult {
        guard !items.isEmpty else {
            logger.error("Receipt interpretation timed out with nothing interpreted (\(reason, privacy: .public))")
            throw ReceiptScanError.timeout
        }
        logger.warning(
            """
            Receipt interpretation stopped early (\(reason, privacy: .public)) after \
            \(interpreted, privacy: .public) item(s); later lines were not interpreted.
            """
        )
        return ReceiptInterpretationResult(items: items)
    }

    private func interpretBatch(
        _ batch: [ReceiptLineItem],
        timeout: Duration
    ) async throws -> [RawInterpretedReceiptItem] {
        guard let prompt = promptBuilder.makePrompt(for: batch) else { return [] }

        let interpretPrompt = self.interpretPrompt
        let logger = self.logger

        do {
            return try await BoundedWork.run(
                timeout: timeout,
                timeoutError: { ReceiptScanError.timeout }
            ) {
                try await interpretPrompt(prompt)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ReceiptScanError {
            // Already mapped - the timeout, or a nested throw.
            throw error
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
    nonisolated func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
