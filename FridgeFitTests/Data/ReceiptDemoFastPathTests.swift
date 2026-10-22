//
//  ReceiptDemoFastPathTests.swift
//  FridgeFitTests
//

import CoreGraphics
import UIKit
import XCTest
@testable import FridgeFit

/// The demonstration, end to end: prepare, relaunch, replay.
///
/// `MockReceiptIngredientInterpreter` stands in for Apple Intelligence with
/// a deliberate delay, because the thing being demonstrated is the
/// *difference* between running the model and not running it, and that
/// difference has to be visible in a test that cannot call the real model.
///
/// Timings asserted here are simulator timings and are treated as such: the
/// only hard assertions are about relative cost and about the cache-hit path
/// doing no model work. See `docs/receipt-demo-fast-path.md` for how the
/// device figure is obtained.
@MainActor
final class ReceiptDemoFastPathTests: XCTestCase {
    private var directory: URL!
    private var cacheFileURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cacheFileURL = directory.appendingPathComponent("receipt-recognition-cache.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// Each relaunch is a brand new store over the same file.
    private func storeAfterRelaunch() -> FileReceiptRecognitionCacheStore {
        FileReceiptRecognitionCacheStore(fileURL: cacheFileURL)
    }

    private var colesLines: [String] {
        [
            "Coles Supermarkets Australia Pty Ltd",
            "Store: 7702 - CS HUNTLEE",
            "COLS TOMATOES 1KG       3.60",
            "FREE RANGE EGGS 12PK    5.20",
            "FULL CREAM MILK 2L      3.00",
            "Total for 3 items:     11.80"
        ]
    }

    /// Stands in for the real model, including its cost.
    private func slowInterpreter(delay: Duration = .milliseconds(250)) -> MockReceiptIngredientInterpreter {
        MockReceiptIngredientInterpreter(
            result: .success(ReceiptInterpretationResult(items: [
                RawInterpretedReceiptItem(
                    originalText: "COLS TOMATOES 1KG",
                    displayName: "Tomatoes",
                    canonicalName: "tomato",
                    classification: "ingredient",
                    category: "Produce",
                    quantity: 1,
                    unit: "kg"
                ),
                RawInterpretedReceiptItem(
                    originalText: "FREE RANGE EGGS 12PK",
                    displayName: "Free Range Eggs",
                    canonicalName: "egg",
                    classification: "ingredient",
                    category: "Dairy",
                    quantity: 12,
                    unit: "pcs"
                ),
                RawInterpretedReceiptItem(
                    originalText: "FULL CREAM MILK 2L",
                    displayName: "Full Cream Milk",
                    canonicalName: "milk",
                    classification: "ingredient",
                    category: "Dairy",
                    quantity: 2,
                    unit: "L"
                )
            ])),
            delay: delay
        )
    }

    /// The real thing is 971x1619, and the fingerprint's cost scales with
    /// pixel count, so the fixture matches it.
    private func demoSizedReceipt() -> CGImage {
        ReceiptImageFixtures.demoLikeReceipt(width: 971, height: 1619)
    }

    private func makeViewModel(
        image: CGImage,
        cache: ReceiptRecognitionCacheStoring?,
        interpreter: MockReceiptIngredientInterpreter,
        metrics: InMemoryReceiptScanMetricsRecorder
    ) -> ReceiptScannerViewModel {
        ReceiptScannerViewModel(
            textRecognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: interpreter,
            pantryRepository: InMemoryPantryRepository(),
            recognitionCache: cache,
            metrics: metrics
        )
    }

    // MARK: - The whole journey

    func testPrepareRelaunchThenReplay() async throws {
        let image = demoSizedReceipt()
        let fingerprint = try XCTUnwrap(ReceiptImageFingerprint.make(of: image))

        // 1. Before preparation, the cache is NOT READY.
        XCTAssertNil(storeAfterRelaunch().entry(for: fingerprint))

        // 2. Preparation runs the genuine pipeline, with no cache attached.
        let preparer = ReceiptDemoCachePreparer(
            textRecognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: slowInterpreter(),
            cache: storeAfterRelaunch()
        )
        let report = try await preparer.analyze(image: image)

        XCTAssertEqual(report.outcome.source, .appleIntelligence, "Preparation must never replay.")
        XCTAssertEqual(report.outcome.pantryCandidates.count, 3)
        XCTAssertTrue(report.isPersistable, "Discrepancies: \(report.discrepancies.map(\.message))")
        XCTAssertEqual(report.fingerprint, fingerprint)

        // 3. Accepted and persisted.
        try preparer.persist(report)

        // 4. READY, and still ready in a brand new process.
        let afterRelaunch = try XCTUnwrap(
            storeAfterRelaunch().entry(for: fingerprint),
            "The cache must survive relaunch, or there is no demo."
        )
        XCTAssertEqual(afterRelaunch.outcome.pantryCandidates.count, 3)

        // 5. The demo itself: the same photo, through the whole app path.
        let interpreter = slowInterpreter()
        let metrics = InMemoryReceiptScanMetricsRecorder()
        let viewModel = makeViewModel(
            image: image,
            cache: storeAfterRelaunch(),
            interpreter: interpreter,
            metrics: metrics
        )

        viewModel.selectImage(UIImage(cgImage: image))
        viewModel.scan()
        try await waitForCompletion(of: viewModel)

        XCTAssertEqual(interpreter.interpretCallCount, 0, "The demo must not re-invoke the model.")
        XCTAssertEqual(viewModel.recognitionSource, .verifiedCache)
        XCTAssertTrue(viewModel.isPresentingReview)
        XCTAssertEqual(viewModel.drafts.count, 3)
        XCTAssertEqual(
            viewModel.drafts.map(\.name).sorted(),
            ["Free Range Eggs", "Full Cream Milk", "Tomatoes"]
        )
    }

    /// The point of the exercise, stated as a test: the prepared photo is
    /// dramatically cheaper than the unprepared one, on the same machine.
    func testAReplayIsFarCheaperThanAModelRun() async throws {
        let image = demoSizedReceipt()
        let other = ReceiptImageFixtures.visuallySimilarDifferentReceipt(width: 971, height: 1619)

        let preparer = ReceiptDemoCachePreparer(
            textRecognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: slowInterpreter(),
            cache: storeAfterRelaunch()
        )
        try preparer.persist(try await preparer.analyze(image: image))

        let metrics = InMemoryReceiptScanMetricsRecorder()
        let useCase = ScanReceiptUseCase(
            textRecognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: slowInterpreter(),
            pantryRepository: InMemoryPantryRepository(),
            recognitionCache: storeAfterRelaunch(),
            metrics: metrics
        )

        _ = try await useCase.execute(image: image)
        let hit = try XCTUnwrap(metrics.last)
        XCTAssertTrue(hit.isCacheHit)

        _ = try await useCase.execute(image: other)
        let miss = try XCTUnwrap(metrics.last)
        XCTAssertFalse(miss.isCacheHit)

        XCTAssertLessThan(
            ReceiptScanMetrics.seconds(hit.total),
            ReceiptScanMetrics.seconds(miss.total),
            "A replay must cost less than running the pipeline."
        )
    }

    // MARK: - Instrumentation

    func testEveryStageIsMeasuredOnACacheHit() async throws {
        let image = demoSizedReceipt()
        let preparer = ReceiptDemoCachePreparer(
            textRecognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: slowInterpreter(),
            cache: storeAfterRelaunch()
        )
        try preparer.persist(try await preparer.analyze(image: image))

        let metrics = InMemoryReceiptScanMetricsRecorder()
        _ = try await ScanReceiptUseCase(
            textRecognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: slowInterpreter(),
            pantryRepository: InMemoryPantryRepository(),
            recognitionCache: storeAfterRelaunch(),
            metrics: metrics
        ).execute(image: image)

        let sample = try XCTUnwrap(metrics.last)
        XCTAssertNotNil(sample.fingerprinting, "Fingerprint duration must be recorded.")
        XCTAssertNotNil(sample.cacheLookup, "Cache lookup duration must be recorded.")
        XCTAssertGreaterThan(ReceiptScanMetrics.seconds(sample.total), 0)
        XCTAssertTrue(sample.summary.contains("verifiedCache"))
    }

    func testTheViewModelMeasuresTimeToReviewPresentation() async throws {
        let image = demoSizedReceipt()
        let preparer = ReceiptDemoCachePreparer(
            textRecognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: slowInterpreter(),
            cache: storeAfterRelaunch()
        )
        try preparer.persist(try await preparer.analyze(image: image))

        let metrics = InMemoryReceiptScanMetricsRecorder()
        let viewModel = makeViewModel(
            image: image,
            cache: storeAfterRelaunch(),
            interpreter: slowInterpreter(),
            metrics: metrics
        )

        viewModel.selectImage(UIImage(cgImage: image))
        viewModel.scan()
        try await waitForCompletion(of: viewModel)

        let latency = try XCTUnwrap(viewModel.lastScanLatency, "Time to review must be measured.")
        XCTAssertGreaterThan(ReceiptScanMetrics.seconds(latency), 0)

        // A generous ceiling. This is a simulator figure and is only here to
        // catch a gross regression - the real target is measured on device.
        XCTAssertLessThan(
            ReceiptScanMetrics.seconds(latency),
            2.0,
            "Cache-hit latency on the simulator should be well under the 2s demo target."
        )
    }

    /// Fingerprinting a full-size receipt is the one genuinely expensive
    /// step on the fast path, so its cost is pinned on its own.
    func testFingerprintingAFullSizeReceiptIsFast() throws {
        let image = demoSizedReceipt()
        XCTAssertEqual(image.width, 971)
        XCTAssertEqual(image.height, 1619)

        let start = ContinuousClock.now
        let fingerprint = ReceiptImageFingerprint.make(of: image)
        let elapsed = ContinuousClock.now - start

        XCTAssertNotNil(fingerprint)
        XCTAssertLessThan(
            ReceiptScanMetrics.seconds(elapsed),
            0.5,
            "Fingerprinting 971x1619 must not eat the latency budget."
        )
    }

    // MARK: - Fallback, end to end

    func testOtherReceiptsStillTakeTheFullPathAfterPreparation() async throws {
        let image = demoSizedReceipt()
        let preparer = ReceiptDemoCachePreparer(
            textRecognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: slowInterpreter(),
            cache: storeAfterRelaunch()
        )
        try preparer.persist(try await preparer.analyze(image: image))

        let interpreter = slowInterpreter()
        let metrics = InMemoryReceiptScanMetricsRecorder()
        let viewModel = makeViewModel(
            image: image,
            cache: storeAfterRelaunch(),
            interpreter: interpreter,
            metrics: metrics
        )

        // A different receipt entirely.
        viewModel.selectImage(UIImage(cgImage: ReceiptImageFixtures.visuallySimilarDifferentReceipt(width: 971, height: 1619)))
        viewModel.scan()
        try await waitForCompletion(of: viewModel)

        XCTAssertEqual(interpreter.interpretCallCount, 1, "Another receipt must still use Apple Intelligence.")
        XCTAssertEqual(viewModel.recognitionSource, .appleIntelligence)
        XCTAssertEqual(viewModel.drafts.count, 3)
    }

    /// If the prepared file is destroyed between preparation and the demo,
    /// the app must still work - just slowly.
    func testADeletedCacheFileFallsBackToTheModel() async throws {
        let image = demoSizedReceipt()
        let preparer = ReceiptDemoCachePreparer(
            textRecognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: slowInterpreter(),
            cache: storeAfterRelaunch()
        )
        try preparer.persist(try await preparer.analyze(image: image))
        try FileManager.default.removeItem(at: cacheFileURL)

        let interpreter = slowInterpreter()
        let viewModel = makeViewModel(
            image: image,
            cache: storeAfterRelaunch(),
            interpreter: interpreter,
            metrics: InMemoryReceiptScanMetricsRecorder()
        )

        viewModel.selectImage(UIImage(cgImage: image))
        viewModel.scan()
        try await waitForCompletion(of: viewModel)

        XCTAssertEqual(interpreter.interpretCallCount, 1)
        XCTAssertEqual(viewModel.recognitionSource, .appleIntelligence)
        XCTAssertEqual(viewModel.drafts.count, 3, "The result must be just as good, only slower.")
    }

    // MARK: - Helpers

    private func waitForCompletion(
        of viewModel: ReceiptScannerViewModel,
        timeout: Duration = .seconds(10)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if case .completed = viewModel.scanState { return }
            if case .failed(let message) = viewModel.scanState {
                XCTFail("Scan failed: \(message)")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for the scan to finish.")
    }
}
