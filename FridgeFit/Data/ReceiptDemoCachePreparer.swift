//
//  ReceiptDemoCachePreparer.swift
//  FridgeFit
//

#if DEBUG

import CoreGraphics
import Foundation
import ImageIO

/// Prepares a verified recognition cache entry before a demonstration.
///
/// ## Why this exists rather than caching every scan
///
/// `ScanReceiptUseCase` never writes to the cache. If it did, the first scan
/// of any receipt would be persisted unreviewed, and a misread would become
/// permanent and fast. Writing is confined here, to a deliberate operation
/// someone runs and inspects, so the only results that can ever be replayed
/// are ones a human looked at and accepted.
///
/// ## What it does and does not do
///
/// It runs the **real** pipeline - Vision OCR, then Apple's on-device
/// language model, through the same `ScanReceiptUseCase` the app uses - with
/// no cache attached, so it always does the full ten-second scan. It then
/// compares what came back against a written description of the demo receipt
/// and reports the differences.
///
/// Those expectations are a **checklist for the operator**, never a source of
/// data. Nothing from `ColesDemoReceiptExpectation` is ever written to the
/// cache; the entry holds exactly what the model produced. A mismatch is
/// shown and the operator decides, which is the point - silently substituting
/// the expected values would make the whole exercise a fake.
///
/// The entire file is `#if DEBUG`, so no part of it ships.
nonisolated struct ReceiptDemoCachePreparer {

    /// A single thing worth the operator's attention in a prepared result.
    struct Discrepancy: Identifiable, Equatable {
        enum Severity: Equatable {
            /// The result is not fit to cache at all.
            case blocking
            /// Worth reading before accepting, but a legitimate answer.
            case review
        }

        let id = UUID()
        let severity: Severity
        let message: String

        static func == (lhs: Discrepancy, rhs: Discrepancy) -> Bool {
            lhs.severity == rhs.severity && lhs.message == rhs.message
        }
    }

    /// The outcome of one preparation run, before anything is persisted.
    struct Report {
        let fingerprint: ReceiptImageFingerprint
        let pixelWidth: Int
        let pixelHeight: Int
        /// Exactly what the pipeline returned. Never edited.
        let outcome: ReceiptScanOutcome
        let discrepancies: [Discrepancy]
        /// How long the real pipeline took, which is the number the fast
        /// path is being compared against.
        let recognitionDuration: Duration

        var blockingDiscrepancies: [Discrepancy] {
            discrepancies.filter { $0.severity == .blocking }
        }

        /// Whether this result may be persisted at all.
        var isPersistable: Bool {
            !outcome.pantryCandidates.isEmpty && blockingDiscrepancies.isEmpty
        }
    }

    enum PreparationError: LocalizedError, Equatable {
        case notPersistable(reasons: [String])

        var errorDescription: String? {
            switch self {
            case .notPersistable(let reasons):
                return "This result was not cached: \(reasons.joined(separator: "; "))"
            }
        }
    }

    private let scanReceiptUseCase: ScanReceiptUseCase
    private let cache: ReceiptRecognitionCacheStoring
    private let expectation: ColesDemoReceiptExpectation

    /// - Parameter pantryRepository: only used to mark membership, which is
    ///   deliberately *not* persisted - `StoredReceiptScanOutcome` drops it
    ///   and `ScanReceiptUseCase` recomputes it on every hit. An empty
    ///   in-memory pantry is therefore the honest default here.
    init(
        textRecognizer: ReceiptTextRecognizer,
        interpreter: ReceiptIngredientInterpreter,
        cache: ReceiptRecognitionCacheStoring,
        pantryRepository: PantryRepository = InMemoryPantryRepository(),
        expectation: ColesDemoReceiptExpectation = .coles
    ) {
        // No `recognitionCache:` argument. Preparation must always run the
        // model, or it would just replay whatever it wrote last time.
        self.scanReceiptUseCase = ScanReceiptUseCase(
            textRecognizer: textRecognizer,
            interpreter: interpreter,
            pantryRepository: pantryRepository
        )
        self.cache = cache
        self.expectation = expectation
    }

    var availability: AppleIntelligenceAvailability { scanReceiptUseCase.availability }

    // MARK: - Steps

    /// Fingerprints an image without running anything. Fast, so the
    /// preparation screen can show the key the moment a photo is picked.
    func fingerprint(
        of image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) -> ReceiptImageFingerprint? {
        ReceiptImageFingerprint.make(of: image, orientation: orientation)
    }

    /// Runs the genuine recognition pipeline and reports what it found.
    /// Persists nothing - see `persist(_:)`.
    func analyze(
        image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> Report {
        guard let fingerprint = fingerprint(of: image, orientation: orientation) else {
            throw ReceiptScanError.invalidImage
        }

        let start = ContinuousClock.now
        let outcome = try await scanReceiptUseCase.execute(image: image, orientation: orientation)
        let duration = ContinuousClock.now - start

        // An outcome that came from the cache would mean this preparer was
        // built wrongly; it is constructed without one precisely so that
        // cannot happen. Assert the invariant rather than trust it.
        let discrepancies = validate(
            outcome: outcome,
            imageWidth: image.width,
            imageHeight: image.height
        )

        return Report(
            fingerprint: fingerprint,
            pixelWidth: image.width,
            pixelHeight: image.height,
            outcome: outcome,
            discrepancies: discrepancies,
            recognitionDuration: duration
        )
    }

    /// Writes a reviewed result to the persistent cache.
    func persist(_ report: Report, now: Date = Date()) throws {
        guard report.isPersistable else {
            let reasons = report.outcome.pantryCandidates.isEmpty
                ? ["the scan produced no pantry candidates"]
                : report.blockingDiscrepancies.map(\.message)
            throw PreparationError.notPersistable(reasons: reasons)
        }
        guard report.outcome.source == .appleIntelligence else {
            throw PreparationError.notPersistable(
                reasons: ["the result did not come from a live model run"]
            )
        }

        try cache.save(ReceiptRecognitionCacheEntry(
            fingerprint: report.fingerprint,
            outcome: report.outcome,
            preparedAt: now
        ))
    }

    /// Whether the cache can answer for this picture right now. Re-reads the
    /// file every time, so calling it after a relaunch genuinely proves the
    /// entry survived.
    func preparedEntry(for fingerprint: ReceiptImageFingerprint) -> ReceiptRecognitionCacheEntry? {
        cache.entry(for: fingerprint)
    }

    func allPreparedEntries() -> [ReceiptRecognitionCacheEntry] { cache.allEntries() }

    func clear() { cache.removeAll() }

    // MARK: - Validation

    /// Compares a real result against the written description of the demo
    /// receipt. Produces advice, not corrections.
    private func validate(
        outcome: ReceiptScanOutcome,
        imageWidth: Int,
        imageHeight: Int
    ) -> [Discrepancy] {
        var discrepancies: [Discrepancy] = []

        guard !outcome.pantryCandidates.isEmpty else {
            return [Discrepancy(
                severity: .blocking,
                message: "The scan produced no pantry candidates, so there is nothing worth caching."
            )]
        }

        if imageWidth != expectation.pixelWidth || imageHeight != expectation.pixelHeight {
            discrepancies.append(Discrepancy(
                severity: .review,
                message: "Image is \(imageWidth)×\(imageHeight); the demo receipt is \(expectation.pixelWidth)×\(expectation.pixelHeight). This may be a different photo."
            ))
        }

        for item in expectation.items {
            guard let candidate = outcome.pantryCandidates.first(where: { item.matches($0) }) else {
                discrepancies.append(Discrepancy(
                    severity: .review,
                    message: "“\(item.receiptText)” was not offered as a pantry item. Check the excluded list for how it was classified."
                ))
                continue
            }
            discrepancies.append(contentsOf: item.quantityDiscrepancies(for: candidate))
        }

        let expectedCount = expectation.items.count
        if outcome.pantryCandidates.count > expectedCount {
            let extras = outcome.pantryCandidates
                .filter { candidate in !expectation.items.contains { $0.matches(candidate) } }
                .map(\.displayName)
            if !extras.isEmpty {
                discrepancies.append(Discrepancy(
                    severity: .review,
                    message: "Extra items not on the reference receipt: \(extras.joined(separator: ", "))."
                ))
            }
        }

        return discrepancies
    }
}

/// A written description of the demonstration receipt, used only to check a
/// real recognition result.
///
/// ## The distinctions this encodes
///
/// A receipt line carries several different numbers and they are not
/// interchangeable. `COLS TOMATOES 1KG    3.60` states a **package size** of
/// 1 kg and a **line total** of $3.60. It does not state a unit price, and it
/// does not state how much the user now has in their kitchen - a pantry
/// quantity is something the user confirms on the review screen, and
/// `ReceiptItemDraft` deliberately leaves it blank when the receipt did not
/// say.
///
/// So the checks below look for the specific ways that can go wrong: a price
/// read as a quantity, or a package size read as a currency amount.
nonisolated struct ColesDemoReceiptExpectation {
    struct Item {
        /// The product line as printed.
        let receiptText: String
        /// Words that identify this product in a recognised candidate.
        let keywords: [String]
        /// The pack size printed on the line, if any. Not a pantry quantity.
        let packageSize: ReceiptQuantity?
        /// The money column for this line. Never a quantity.
        let lineTotal: Double

        func matches(_ candidate: ReceiptIngredientCandidate) -> Bool {
            let haystack = (candidate.sourceText + " " + candidate.displayName + " " + candidate.canonicalName).uppercased()
            return keywords.contains { haystack.contains($0.uppercased()) }
        }

        /// Flags the two confusions that matter.
        func quantityDiscrepancies(for candidate: ReceiptIngredientCandidate) -> [ReceiptDemoCachePreparer.Discrepancy] {
            guard let quantity = candidate.quantity else {
                // Not an error. A receipt that states no pack size should
                // produce no quantity, and the review screen asks the user.
                return packageSize == nil ? [] : [.init(
                    severity: .review,
                    message: "“\(receiptText)” states \(packageSize!.formatted) but no quantity was detected. The user will be asked for one."
                )]
            }

            var found: [ReceiptDemoCachePreparer.Discrepancy] = []

            // The dangerous one: $3.60 becoming "3.6 of something".
            if abs(quantity.value - lineTotal) < 0.001 {
                found.append(.init(
                    severity: .blocking,
                    message: "“\(receiptText)”: the detected quantity \(quantity.formatted) equals the line total $\(String(format: "%.2f", lineTotal)). A price has been read as a quantity."
                ))
            }

            if let packageSize, quantity != packageSize {
                found.append(.init(
                    severity: .review,
                    message: "“\(receiptText)”: detected \(quantity.formatted), the line states \(packageSize.formatted)."
                ))
            }

            return found
        }
    }

    let merchant: String
    let store: String
    let purchasedOn: String
    let currencyCode: String
    let items: [Item]
    /// The money totals, recorded so the operator can check the receipt in
    /// their hand. FridgeFit's pipeline does not extract these - it reads
    /// products, not accounting - so they are reference only.
    let total: Double
    let gst: Double
    let payment: String
    let pixelWidth: Int
    let pixelHeight: Int

    /// The Coles receipt used for the demonstration.
    ///
    /// SHA-256 of the source PNG as supplied:
    /// `5edbb57bdd219f692feea6f133f3c8ae8fe7afdc41457e811cfb280214e23de8`
    /// That hash identifies the *file on disk* and is not the cache key -
    /// see `ReceiptImageFingerprint` for why a file hash cannot be.
    static let coles = ColesDemoReceiptExpectation(
        merchant: "Coles Supermarkets Australia Pty Ltd",
        store: "7702, CS HUNTLEE",
        purchasedOn: "23/05/2025 11:23",
        currencyCode: "AUD",
        items: [
            Item(
                receiptText: "COLS TOMATOES 1KG",
                keywords: ["TOMATO"],
                packageSize: ReceiptQuantity(value: 1, unit: .kilograms),
                lineTotal: 3.60
            ),
            Item(
                receiptText: "FREE RANGE EGGS 12PK",
                keywords: ["EGG"],
                packageSize: ReceiptQuantity(value: 12, unit: .pieces),
                lineTotal: 5.20
            ),
            Item(
                receiptText: "FULL CREAM MILK 2L",
                keywords: ["MILK"],
                packageSize: ReceiptQuantity(value: 2, unit: .liters),
                lineTotal: 3.00
            )
        ],
        total: 11.80,
        gst: 0.00,
        payment: "EFT $11.80",
        pixelWidth: 971,
        pixelHeight: 1619
    )
}

#endif
