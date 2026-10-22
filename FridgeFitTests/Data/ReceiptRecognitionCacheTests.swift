//
//  ReceiptRecognitionCacheTests.swift
//  FridgeFitTests
//

import XCTest
@testable import FridgeFit

/// Covers the persistent half of the demo fast path: what gets written, what
/// is refused, and what happens to an entry a later build can no longer
/// trust.
final class ReceiptRecognitionCacheTests: XCTestCase {
    private var directory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("receipt-recognition-cache.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeStore() -> FileReceiptRecognitionCacheStore {
        FileReceiptRecognitionCacheStore(fileURL: fileURL)
    }

    private var demoFingerprint: ReceiptImageFingerprint {
        ReceiptImageFingerprint.make(of: ReceiptImageFixtures.demoLikeReceipt())!
    }

    private var otherFingerprint: ReceiptImageFingerprint {
        ReceiptImageFingerprint.make(of: ReceiptImageFixtures.visuallySimilarDifferentReceipt())!
    }

    /// Stands in for a real verified Coles result: three pantry candidates
    /// and one excluded line.
    private func makeOutcome(names: [String] = ["Tomatoes", "Eggs", "Milk"]) -> ReceiptScanOutcome {
        ReceiptScanOutcome(
            pantryCandidates: names.enumerated().map { index, name in
                ReceiptIngredientCandidate(
                    displayName: name,
                    canonicalName: name.lowercased(),
                    classification: .ingredient,
                    category: .produce,
                    quantity: index == 0 ? ReceiptQuantity(value: 1, unit: .kilograms) : nil,
                    sourceText: "\(name.uppercased()) 3.60",
                    order: index
                )
            },
            excluded: [
                ReceiptIngredientCandidate(
                    displayName: "Shopping Bag",
                    canonicalName: "shopping_bag",
                    classification: .household,
                    category: .other,
                    quantity: nil,
                    sourceText: "BAG 0.15",
                    order: 9
                )
            ]
        )
    }

    // MARK: - Round trip

    func testAVerifiedResultCanBeSavedAndRead() throws {
        let store = makeStore()
        let fingerprint = demoFingerprint
        try store.save(ReceiptRecognitionCacheEntry(
            fingerprint: fingerprint,
            outcome: makeOutcome(),
            preparedAt: Date()
        ))

        let entry = try XCTUnwrap(store.entry(for: fingerprint))
        XCTAssertEqual(entry.outcome.outcome.pantryCandidates.map(\.displayName), ["Tomatoes", "Eggs", "Milk"])
    }

    /// The point of persisting at all: the entry has to still be there
    /// tomorrow morning. A second store over the same file is exactly what a
    /// relaunch produces.
    func testTheEntrySurvivesApplicationRelaunch() throws {
        let fingerprint = demoFingerprint
        try makeStore().save(ReceiptRecognitionCacheEntry(
            fingerprint: fingerprint,
            outcome: makeOutcome(),
            preparedAt: Date()
        ))

        let afterRelaunch = makeStore()
        XCTAssertNotNil(afterRelaunch.entry(for: fingerprint), "The cache must outlive the process that wrote it.")
    }

    func testTheExactImageHitsAndAnAbsentEntryMisses() throws {
        let store = makeStore()
        try store.save(ReceiptRecognitionCacheEntry(
            fingerprint: demoFingerprint,
            outcome: makeOutcome(),
            preparedAt: Date()
        ))

        XCTAssertNotNil(store.entry(for: demoFingerprint))
        XCTAssertNil(store.entry(for: otherFingerprint), "A receipt nobody prepared must miss.")
    }

    func testStoredQuantitiesAndAbsentQuantitiesBothSurvive() throws {
        let store = makeStore()
        try store.save(ReceiptRecognitionCacheEntry(
            fingerprint: demoFingerprint,
            outcome: makeOutcome(),
            preparedAt: Date()
        ))

        let candidates = try XCTUnwrap(store.entry(for: demoFingerprint)).outcome.outcome.pantryCandidates
        XCTAssertEqual(candidates[0].quantity, ReceiptQuantity(value: 1, unit: .kilograms))
        XCTAssertNil(candidates[1].quantity, "A receipt that stated no quantity must replay as stating none.")
    }

    func testExcludedItemsSurviveSoDiagnosticsStillWork() throws {
        let store = makeStore()
        try store.save(ReceiptRecognitionCacheEntry(
            fingerprint: demoFingerprint,
            outcome: makeOutcome(),
            preparedAt: Date()
        ))

        let outcome = try XCTUnwrap(store.entry(for: demoFingerprint)).outcome.outcome
        XCTAssertEqual(outcome.excluded.map(\.displayName), ["Shopping Bag"])
    }

    func testAReplayedOutcomeIsMarkedAsComingFromTheCache() throws {
        let store = makeStore()
        try store.save(ReceiptRecognitionCacheEntry(
            fingerprint: demoFingerprint,
            outcome: makeOutcome(),
            preparedAt: Date()
        ))

        XCTAssertEqual(try XCTUnwrap(store.entry(for: demoFingerprint)).outcome.outcome.source, .verifiedCache)
    }

    /// Pantry membership is a fact about the pantry, not about the receipt,
    /// so it must not be carried across a relaunch.
    func testPantryMembershipIsNotPersisted() throws {
        let store = makeStore()
        let outcome = ReceiptScanOutcome(
            pantryCandidates: [
                ReceiptIngredientCandidate(
                    displayName: "Milk",
                    canonicalName: "milk",
                    classification: .ingredient,
                    category: .dairy,
                    quantity: nil,
                    sourceText: "FULL CREAM MILK 2L 3.00",
                    order: 0,
                    isAlreadyInPantry: true
                )
            ]
        )
        try store.save(ReceiptRecognitionCacheEntry(
            fingerprint: demoFingerprint,
            outcome: outcome,
            preparedAt: Date()
        ))

        let replayed = try XCTUnwrap(store.entry(for: demoFingerprint)).outcome.outcome
        XCTAssertFalse(
            replayed.pantryCandidates[0].isAlreadyInPantry,
            "Membership must be recomputed from the live pantry, not remembered."
        )
    }

    // MARK: - What must not be cached

    func testAFailedOrEmptyAnalysisIsNotCached() {
        let store = makeStore()
        let entry = ReceiptRecognitionCacheEntry(
            fingerprint: demoFingerprint,
            outcome: .empty,
            preparedAt: Date()
        )

        XCTAssertThrowsError(try store.save(entry)) { error in
            XCTAssertEqual(error as? ReceiptRecognitionCacheError, .resultNotUsable)
        }
        XCTAssertNil(store.entry(for: demoFingerprint))
    }

    // MARK: - Versioning and corruption

    func testAnEntryFromAnotherPipelineVersionIsIgnored() throws {
        let store = makeStore()
        try store.save(ReceiptRecognitionCacheEntry(
            fingerprint: demoFingerprint,
            outcome: makeOutcome(),
            preparedAt: Date(),
            pipelineVersion: "receipt-pipeline-from-an-older-build"
        ))

        XCTAssertNil(
            store.entry(for: demoFingerprint),
            "A result from a different pipeline is not an answer this build may give."
        )
        XCTAssertTrue(store.allEntries().isEmpty)
    }

    func testAnEntryFromAnotherSchemaVersionIsIgnored() throws {
        let store = makeStore()
        try store.save(ReceiptRecognitionCacheEntry(
            fingerprint: demoFingerprint,
            outcome: makeOutcome(),
            preparedAt: Date(),
            schemaVersion: ReceiptRecognitionPipeline.schemaVersion + 1
        ))

        XCTAssertNil(store.entry(for: demoFingerprint))
    }

    /// An incompatible entry must degrade to a miss - which means a normal
    /// Apple Intelligence scan - rather than to an error or a crash.
    func testACorruptFileIsTreatedAsAnEmptyCache() throws {
        try Data("this is not JSON".utf8).write(to: fileURL)
        let store = makeStore()

        XCTAssertNil(store.entry(for: demoFingerprint))
        XCTAssertTrue(store.allEntries().isEmpty)

        // And it must recover: a later save over the rubbish should work.
        try store.save(ReceiptRecognitionCacheEntry(
            fingerprint: demoFingerprint,
            outcome: makeOutcome(),
            preparedAt: Date()
        ))
        XCTAssertNotNil(store.entry(for: demoFingerprint))
    }

    func testAnAbsentFileIsTreatedAsAnEmptyCache() {
        XCTAssertNil(makeStore().entry(for: demoFingerprint))
    }

    // MARK: - Housekeeping

    func testSavingTheSameImageTwiceReplacesRatherThanDuplicates() throws {
        let store = makeStore()
        let fingerprint = demoFingerprint

        try store.save(ReceiptRecognitionCacheEntry(
            fingerprint: fingerprint,
            outcome: makeOutcome(names: ["Old"]),
            preparedAt: Date(timeIntervalSince1970: 1_000)
        ))
        try store.save(ReceiptRecognitionCacheEntry(
            fingerprint: fingerprint,
            outcome: makeOutcome(names: ["New"]),
            preparedAt: Date(timeIntervalSince1970: 2_000)
        ))

        XCTAssertEqual(store.allEntries().count, 1)
        XCTAssertEqual(
            try XCTUnwrap(store.entry(for: fingerprint)).outcome.outcome.pantryCandidates.map(\.displayName),
            ["New"]
        )
    }

    func testAllEntriesReportsNewestPreparationFirst() throws {
        let store = makeStore()
        try store.save(ReceiptRecognitionCacheEntry(
            fingerprint: demoFingerprint,
            outcome: makeOutcome(names: ["Older"]),
            preparedAt: Date(timeIntervalSince1970: 1_000)
        ))
        try store.save(ReceiptRecognitionCacheEntry(
            fingerprint: otherFingerprint,
            outcome: makeOutcome(names: ["Newer"]),
            preparedAt: Date(timeIntervalSince1970: 2_000)
        ))

        XCTAssertEqual(
            store.allEntries().map { $0.outcome.outcome.pantryCandidates[0].displayName },
            ["Newer", "Older"]
        )
    }

    func testRemoveAllClearsTheCache() throws {
        let store = makeStore()
        try store.save(ReceiptRecognitionCacheEntry(
            fingerprint: demoFingerprint,
            outcome: makeOutcome(),
            preparedAt: Date()
        ))

        store.removeAll()
        XCTAssertNil(store.entry(for: demoFingerprint))
    }
}
