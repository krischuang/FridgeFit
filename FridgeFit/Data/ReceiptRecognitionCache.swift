//
//  ReceiptRecognitionCache.swift
//  FridgeFit
//

import Foundation

/// Identifies the recognition pipeline that produced a cached result.
///
/// A cached outcome is only meaningful for the pipeline that made it. If the
/// prompt, the parser, the normaliser or the canonicaliser changes, yesterday's
/// answer may no longer be the answer today's code would give, and replaying it
/// would quietly ship a stale interpretation. Bumping this string retires every
/// existing entry at once.
nonisolated enum ReceiptRecognitionPipeline {
    /// Change this whenever OCR, parsing, the model prompt, normalisation or
    /// canonicalisation changes in a way that could alter a result.
    static let version = "receipt-pipeline-2026-10-22"

    /// Layout version of the stored file itself, independent of the pipeline.
    static let schemaVersion = 1
}

// MARK: - Stored representation

/// A `ReceiptScanOutcome` flattened into something `Codable`.
///
/// The domain models stay free of `Codable`: persistence is a storage
/// concern, and `ReceiptIngredientCandidate` is a value the use case
/// produces, not a record. This mirrors how `GeneratedReceiptInterpretation`
/// keeps the model's wire shape out of the domain.
///
/// ## What is deliberately not stored
///
/// `isAlreadyInPantry` is absent. It is not a property of the receipt, it is
/// a property of the pantry *at the moment of the scan*, and the pantry
/// changes. Persisting it would mean a replayed scan could tick an item the
/// user has since used up, or untick one they have since bought.
/// `ScanReceiptUseCase` re-reads the real pantry on every cache hit, so this
/// is recomputed rather than remembered - which is also why replaying a
/// cached result cannot create duplicate pantry records.
nonisolated struct StoredReceiptScanOutcome: Codable, Equatable {
    struct StoredCandidate: Codable, Equatable {
        let id: UUID
        let displayName: String
        let canonicalName: String
        let classification: ReceiptItemClassification
        let category: IngredientCategory
        let quantityValue: Double?
        let quantityUnit: MeasurementUnit?
        let sourceText: String
        let order: Int

        init(_ candidate: ReceiptIngredientCandidate) {
            self.id = candidate.id
            self.displayName = candidate.displayName
            self.canonicalName = candidate.canonicalName
            self.classification = candidate.classification
            self.category = candidate.category
            self.quantityValue = candidate.quantity?.value
            self.quantityUnit = candidate.quantity?.unit
            self.sourceText = candidate.sourceText
            self.order = candidate.order
        }

        /// Rebuilds the domain value. `isAlreadyInPantry` starts `false` and
        /// is set by `ScanReceiptUseCase` from the live pantry.
        var candidate: ReceiptIngredientCandidate {
            // A value without a unit is not a quantity. Reconstructing one
            // half of a pair would invent a number the receipt never stated,
            // which `ReceiptItemDraft` relies on not happening.
            let quantity: ReceiptQuantity? = {
                guard let quantityValue, let quantityUnit else { return nil }
                return ReceiptQuantity(value: quantityValue, unit: quantityUnit)
            }()

            return ReceiptIngredientCandidate(
                id: id,
                displayName: displayName,
                canonicalName: canonicalName,
                classification: classification,
                category: category,
                quantity: quantity,
                sourceText: sourceText,
                order: order,
                isAlreadyInPantry: false
            )
        }
    }

    let pantryCandidates: [StoredCandidate]
    let excluded: [StoredCandidate]

    init(_ outcome: ReceiptScanOutcome) {
        self.pantryCandidates = outcome.pantryCandidates.map(StoredCandidate.init)
        self.excluded = outcome.excluded.map(StoredCandidate.init)
    }

    /// The outcome as the rest of the app understands it, marked as having
    /// come from the cache rather than from a model run.
    var outcome: ReceiptScanOutcome {
        ReceiptScanOutcome(
            pantryCandidates: pantryCandidates.map(\.candidate),
            excluded: excluded.map(\.candidate),
            source: .verifiedCache
        )
    }
}

/// One verified recognition result, keyed by the exact picture it describes.
nonisolated struct ReceiptRecognitionCacheEntry: Codable, Equatable {
    let fingerprint: ReceiptImageFingerprint
    let schemaVersion: Int
    let pipelineVersion: String
    /// When the verified recognition run that produced this actually
    /// happened. Shown on the preparation screen so a stale entry is
    /// visible rather than assumed fresh.
    let preparedAt: Date
    let outcome: StoredReceiptScanOutcome

    init(
        fingerprint: ReceiptImageFingerprint,
        outcome: ReceiptScanOutcome,
        preparedAt: Date,
        schemaVersion: Int = ReceiptRecognitionPipeline.schemaVersion,
        pipelineVersion: String = ReceiptRecognitionPipeline.version
    ) {
        self.fingerprint = fingerprint
        self.outcome = StoredReceiptScanOutcome(outcome)
        self.preparedAt = preparedAt
        self.schemaVersion = schemaVersion
        self.pipelineVersion = pipelineVersion
    }

    /// Whether this entry was written by a build whose results this build can
    /// still trust.
    var isCompatible: Bool {
        schemaVersion == ReceiptRecognitionPipeline.schemaVersion
            && pipelineVersion == ReceiptRecognitionPipeline.version
    }

    /// An entry with no candidates is not a usable result. Refusing to serve
    /// one means a scan that found nothing can never be replayed as though it
    /// had succeeded.
    var isUsable: Bool { !outcome.pantryCandidates.isEmpty }
}

// MARK: - Store

/// Persistent storage for verified recognition results.
///
/// Abstracted so the scan path can be tested without a filesystem, and so a
/// store that cannot be opened at all is simply absent rather than fatal.
nonisolated protocol ReceiptRecognitionCacheStoring: AnyObject {
    /// The verified entry for this picture, or `nil` for a miss.
    ///
    /// Implementations must treat an unreadable file, undecodable JSON, an
    /// incompatible version and an empty result as misses. A cache is an
    /// optimisation; it is never a reason for a scan to fail.
    func entry(for fingerprint: ReceiptImageFingerprint) -> ReceiptRecognitionCacheEntry?

    /// Persists a verified entry, replacing any existing one for the same
    /// fingerprint.
    func save(_ entry: ReceiptRecognitionCacheEntry) throws

    /// Every entry currently stored, newest preparation first. For the
    /// preparation screen's READY / NOT READY report.
    func allEntries() -> [ReceiptRecognitionCacheEntry]

    func removeAll()
}

/// File-backed cache: one JSON document in Application Support.
///
/// Follows `OnlineRecipeCacheStore`'s shape - a single small document,
/// written atomically, read failures treated as "no cache". A receipt scan is
/// a record of what someone bought, so this stays on the device and is never
/// synced anywhere.
nonisolated final class FileReceiptRecognitionCacheStore: ReceiptRecognitionCacheStoring {
    /// This exists to answer for a handful of deliberately prepared receipts,
    /// not to accumulate every scan the app has ever done.
    private static let maxEntries = 8

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? FileManager.default.temporaryDirectory
            self.fileURL = base
                .appendingPathComponent("FridgeFit", isDirectory: true)
                .appendingPathComponent("receipt-recognition-cache.json", isDirectory: false)
        }
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func entry(for fingerprint: ReceiptImageFingerprint) -> ReceiptRecognitionCacheEntry? {
        guard let entry = loadFile().entries[fingerprint.value] else { return nil }
        // An entry from an older pipeline is not an error and not a result.
        // It is simply not an answer this build may give.
        guard entry.isCompatible, entry.isUsable else { return nil }
        return entry
    }

    func save(_ entry: ReceiptRecognitionCacheEntry) throws {
        guard entry.isUsable else { throw ReceiptRecognitionCacheError.resultNotUsable }

        var file = loadFile()
        file.entries[entry.fingerprint.value] = entry
        file.order.removeAll { $0 == entry.fingerprint.value }
        file.order.append(entry.fingerprint.value)
        while file.order.count > Self.maxEntries {
            let evicted = file.order.removeFirst()
            file.entries[evicted] = nil
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(file).write(to: fileURL, options: .atomic)
    }

    func allEntries() -> [ReceiptRecognitionCacheEntry] {
        loadFile().entries.values
            .filter { $0.isCompatible && $0.isUsable }
            .sorted { $0.preparedAt > $1.preparedAt }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private struct CacheFile: Codable {
        var entries: [String: ReceiptRecognitionCacheEntry] = [:]
        /// Least-recently-prepared first.
        var order: [String] = []
    }

    /// A corrupt or absent file is an empty cache, never a thrown error - the
    /// caller's next step on a miss is a perfectly normal scan.
    private func loadFile() -> CacheFile {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode(CacheFile.self, from: data)
        else { return CacheFile() }
        return decoded
    }
}

/// In-memory store for tests and previews. Never touches the filesystem.
nonisolated final class InMemoryReceiptRecognitionCacheStore: ReceiptRecognitionCacheStoring {
    private(set) var stored: [String: ReceiptRecognitionCacheEntry] = [:]
    /// Counts reads so a test can prove the scan path consulted the cache.
    private(set) var lookupCount = 0
    /// Set to make every read fail, to exercise the fallback path.
    var readFailure = false

    init(initial: [ReceiptRecognitionCacheEntry] = []) {
        for entry in initial { stored[entry.fingerprint.value] = entry }
    }

    func entry(for fingerprint: ReceiptImageFingerprint) -> ReceiptRecognitionCacheEntry? {
        lookupCount += 1
        guard !readFailure else { return nil }
        guard let entry = stored[fingerprint.value], entry.isCompatible, entry.isUsable else { return nil }
        return entry
    }

    func save(_ entry: ReceiptRecognitionCacheEntry) throws {
        guard entry.isUsable else { throw ReceiptRecognitionCacheError.resultNotUsable }
        stored[entry.fingerprint.value] = entry
    }

    /// Plants an entry without going through `save`'s checks, to stand in
    /// for a cache file left behind by a build with a different pipeline.
    /// `save` could not produce such an entry, which is the point.
    func insertBypassingValidation(_ entry: ReceiptRecognitionCacheEntry) {
        stored[entry.fingerprint.value] = entry
    }

    func allEntries() -> [ReceiptRecognitionCacheEntry] {
        stored.values
            .filter { $0.isCompatible && $0.isUsable }
            .sorted { $0.preparedAt > $1.preparedAt }
    }

    func removeAll() {
        stored.removeAll()
    }
}

/// Why a cache write was refused.
nonisolated enum ReceiptRecognitionCacheError: LocalizedError, Equatable {
    /// The recognition produced nothing worth replaying. Caching it would
    /// turn a failed scan into a permanently fast failure.
    case resultNotUsable

    var errorDescription: String? {
        switch self {
        case .resultNotUsable:
            return "The recognition result was empty, so it was not cached."
        }
    }
}
