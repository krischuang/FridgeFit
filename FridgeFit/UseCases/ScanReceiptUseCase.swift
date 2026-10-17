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

    init(
        textRecognizer: ReceiptTextRecognizer,
        interpreter: ReceiptIngredientInterpreter,
        pantryRepository: PantryRepository,
        parser: ReceiptLineParser = ReceiptLineParser(),
        normalizer: ReceiptItemNormalizer = ReceiptItemNormalizer()
    ) {
        self.textRecognizer = textRecognizer
        self.interpreter = interpreter
        self.pantryRepository = pantryRepository
        self.parser = parser
        self.normalizer = normalizer
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

    /// Flags candidates the user already has. A pantry read failure isn't
    /// worth losing a whole scan over - the candidates are still shown, and
    /// `AddPantryItemUseCase` will still catch any duplicate on insert.
    private func markingPantryMembership(of outcome: ReceiptScanOutcome) async throws -> ReceiptScanOutcome {
        guard let pantryItems = try? await pantryRepository.fetchAll() else {
            return outcome
        }
        try Task.checkCancellation()

        let marked = outcome.pantryCandidates.map { candidate in
            let isAlreadyInPantry = pantryItems.contains { $0.ingredient.matches(name: candidate.displayName) }
            return candidate.markingAlreadyInPantry(isAlreadyInPantry)
        }

        return ReceiptScanOutcome(pantryCandidates: marked, excluded: outcome.excluded)
    }
}
