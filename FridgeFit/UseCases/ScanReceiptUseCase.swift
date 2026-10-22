//
//  ScanReceiptUseCase.swift
//  FridgeFit
//

import CoreGraphics
import Foundation
import ImageIO

/// Runs a receipt scan end to end, up to (but not including) the pantry.
///
/// Orchestrates the stages that have to happen in order, so the view model
/// doesn't: check the interpreter can run, read the text, clean it,
/// interpret it, validate the interpretation, then reconcile the survivors
/// against the real pantry.
///
/// Each stage is a protocol or a value type that can be tested on its own;
/// this type's own job is sequencing and the three "nothing found"
/// outcomes, which are distinguished deliberately because they need
/// completely different advice from the user's point of view.
///
/// The pantry check is the important one - `isAlreadyInPantry` is decided
/// here by reading `PantryRepository`, using the same
/// `Ingredient.matches(name:)` rule `AddPantryItemUseCase` uses, so the
/// confirmation screen agrees with what the pantry will accept. The model
/// is never asked, and never told, what's already in the pantry.
nonisolated struct ScanReceiptUseCase {
    private let textRecognizer: ReceiptTextRecognizer
    private let interpreter: ReceiptIngredientInterpreter
    private let pantryRepository: PantryRepository
    private let parser: ReceiptLineParser
    private let normalizer: ReceiptItemNormalizer
    /// Optional, and `nil` by default, so every existing construction of
    /// this type behaves exactly as it did before the cache existed.
    private let recognitionCache: ReceiptRecognitionCacheStoring?
    private let metrics: ReceiptScanMetricsRecording?

    init(
        textRecognizer: ReceiptTextRecognizer,
        interpreter: ReceiptIngredientInterpreter,
        pantryRepository: PantryRepository,
        parser: ReceiptLineParser = ReceiptLineParser(),
        normalizer: ReceiptItemNormalizer = ReceiptItemNormalizer(),
        recognitionCache: ReceiptRecognitionCacheStoring? = nil,
        metrics: ReceiptScanMetricsRecording? = nil
    ) {
        self.textRecognizer = textRecognizer
        self.interpreter = interpreter
        self.pantryRepository = pantryRepository
        self.parser = parser
        self.normalizer = normalizer
        self.recognitionCache = recognitionCache
        self.metrics = metrics
    }

    /// Whether a scan can be started right now.
    var availability: AppleIntelligenceAvailability {
        interpreter.availability
    }

    /// Scans a receipt photo.
    ///
    /// - Throws: `ReceiptScanError` if scanning is unavailable, the photo
    ///   yields nothing usable, or interpretation fails; `CancellationError`
    ///   if the caller cancelled.
    func execute(
        image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> ReceiptScanOutcome {
        let started = ContinuousClock.now
        var fingerprinting: Duration?
        var cacheLookup: Duration?

        // The cache is consulted first, and only ever answers for a picture
        // that has already been through the pipeline below and had its
        // result verified. A miss - including an unreadable store, an entry
        // from an older pipeline, or an image that cannot be fingerprinted
        // at all - falls straight through to the full scan.
        if let replayed = try await replayedOutcome(
            for: image,
            orientation: orientation,
            fingerprinting: &fingerprinting,
            cacheLookup: &cacheLookup
        ) {
            metrics?.record(ReceiptScanMetrics(
                source: replayed.source,
                fingerprinting: fingerprinting,
                cacheLookup: cacheLookup,
                total: ContinuousClock.now - started
            ))
            return replayed
        }

        // Everything below is the original pipeline, untouched.
        defer {
            metrics?.record(ReceiptScanMetrics(
                source: .appleIntelligence,
                fingerprinting: fingerprinting,
                cacheLookup: cacheLookup,
                total: ContinuousClock.now - started
            ))
        }

        let availability = interpreter.availability
        guard availability.canScan else {
            throw ReceiptScanError.scanUnavailable(availability)
        }

        ReceiptScanDiagnostics.engine("Vision text recognition (OCR) + Apple Foundation Models (text interpretation). On-device, no image sent to the model.")

        let recognized = try await textRecognizer.recognizeText(in: image, orientation: orientation)
        try Task.checkCancellation()
        ReceiptScanDiagnostics.recognizedText(recognized)
        guard !recognized.isEmpty else { throw ReceiptScanError.noTextRecognized }

        let lineItems = parser.parse(recognized)
        ReceiptScanDiagnostics.parsedLines(lineItems)
        guard !lineItems.isEmpty else { throw ReceiptScanError.noProductLinesFound }

        let interpretation = try await interpreter.interpret(lineItems: lineItems)
        try Task.checkCancellation()
        ReceiptScanDiagnostics.interpretation(interpretation)

        let outcome = normalizer.normalize(interpretation, against: lineItems)
        ReceiptScanDiagnostics.outcome(outcome)
        guard !outcome.isEmpty else { throw ReceiptScanError.noFoodItemsFound }

        return try await markingPantryMembership(of: outcome)
    }

    /// Serves a previously verified result for this exact picture, if there
    /// is one.
    ///
    /// Returns `nil` for every kind of miss, so the caller's next step is an
    /// ordinary scan. In particular this never throws on the cache's
    /// account: the one error it propagates is cancellation, because a
    /// cancelled scan must not produce a result either way.
    ///
    /// Note what still happens on a hit. The replayed candidates go through
    /// `markingPantryMembership` against the **live** pantry, exactly as a
    /// fresh scan's would, because what the user already owns has very
    /// likely changed since the result was recorded. That is also what keeps
    /// a replay from offering to add something the pantry already holds.
    private func replayedOutcome(
        for image: CGImage,
        orientation: CGImagePropertyOrientation,
        fingerprinting: inout Duration?,
        cacheLookup: inout Duration?
    ) async throws -> ReceiptScanOutcome? {
        guard let recognitionCache else { return nil }

        // Several megabytes of pixels. `ReceiptImageFingerprint.make` is
        // `nonisolated`, and this type is too, so it runs off the main actor
        // even though the view model started the task from it.
        let fingerprintStart = ContinuousClock.now
        let computed = ReceiptImageFingerprint.make(of: image, orientation: orientation)
        fingerprinting = ContinuousClock.now - fingerprintStart

        guard let fingerprint = computed else {
            ReceiptScanDiagnostics.cacheUnavailable("the image could not be fingerprinted")
            return nil
        }
        try Task.checkCancellation()

        let lookupStart = ContinuousClock.now
        let found = recognitionCache.entry(for: fingerprint)
        cacheLookup = ContinuousClock.now - lookupStart

        guard let entry = found else {
            ReceiptScanDiagnostics.cacheMiss(fingerprint)
            return nil
        }

        ReceiptScanDiagnostics.engine("Verified cache replay. No model invocation: this result was produced by an earlier Apple Intelligence run over a pixel-identical photo.")
        ReceiptScanDiagnostics.cacheHit(entry)

        let outcome = entry.outcome.outcome
        try Task.checkCancellation()
        return try await markingPantryMembership(of: outcome)
    }

    /// Flags candidates the user already has. A pantry read failure isn't
    /// worth losing a whole scan over - the candidates are still shown, and
    /// `AddPantryItemUseCase` will still catch any duplicate on insert.
    private func markingPantryMembership(of outcome: ReceiptScanOutcome) async throws -> ReceiptScanOutcome {
        guard let pantryItems = try? await pantryRepository.fetchAll() else {
            return outcome
        }
        try Task.checkCancellation()

        // `markingPantryMembership(_:)` carries `source` across, so a
        // replayed result stays labelled as a replay.
        return outcome.markingPantryMembership { candidate in
            pantryItems.contains { $0.ingredient.matches(name: candidate.displayName) }
        }
    }
}
