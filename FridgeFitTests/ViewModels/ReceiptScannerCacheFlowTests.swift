//
//  ReceiptScannerCacheFlowTests.swift
//  FridgeFitTests
//

import CoreGraphics
import UIKit
import XCTest
@testable import FridgeFit

/// How the cache behaves once it is driven through the view model: what the
/// review screen is told about provenance, and what happens when the user
/// picks two photos in quick succession.
///
/// Every test is `async` for the reason recorded in
/// `ReceiptScannerViewModel.deinit` - releasing a main-actor-isolated class
/// from a synchronous context in this target can abort.
@MainActor
final class ReceiptScannerCacheFlowTests: XCTestCase {

    private var colesLines: [String] {
        [
            "Coles Supermarkets Australia Pty Ltd",
            "COLS TOMATOES 1KG       3.60",
            "FREE RANGE EGGS 12PK    5.20",
            "FULL CREAM MILK 2L      3.00"
        ]
    }

    private func interpreter(delay: Duration? = nil) -> MockReceiptIngredientInterpreter {
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

    private var demoImage: CGImage { ReceiptImageFixtures.demoLikeReceipt() }
    private var otherImage: CGImage { ReceiptImageFixtures.visuallySimilarDifferentReceipt() }

    private func makeViewModel(
        cache: ReceiptRecognitionCacheStoring? = nil,
        interpreter: MockReceiptIngredientInterpreter? = nil,
        recognizerDelay: Duration? = nil
    ) -> ReceiptScannerViewModel {
        ReceiptScannerViewModel(
            textRecognizer: MockReceiptTextRecognizer(lines: colesLines, delay: recognizerDelay),
            interpreter: interpreter ?? self.interpreter(),
            pantryRepository: InMemoryPantryRepository(),
            recognitionCache: cache
        )
    }

    /// Runs one real scan and stores its result, the way the DEBUG
    /// preparation flow does.
    private func preparedCache(for image: CGImage) async throws -> InMemoryReceiptRecognitionCacheStore {
        let cache = InMemoryReceiptRecognitionCacheStore()
        let outcome = try await ScanReceiptUseCase(
            textRecognizer: MockReceiptTextRecognizer(lines: colesLines),
            interpreter: interpreter(),
            pantryRepository: InMemoryPantryRepository()
        ).execute(image: image)

        try cache.save(ReceiptRecognitionCacheEntry(
            fingerprint: try XCTUnwrap(ReceiptImageFingerprint.make(of: image)),
            outcome: outcome,
            preparedAt: Date()
        ))
        return cache
    }

    // MARK: - Provenance

    func testAFreshScanReportsAppleIntelligence() async throws {
        let viewModel = makeViewModel(cache: InMemoryReceiptRecognitionCacheStore())
        viewModel.selectImage(UIImage(cgImage: demoImage))
        viewModel.scan()
        try await waitForCompletion(of: viewModel)

        XCTAssertEqual(viewModel.recognitionSource, .appleIntelligence)
    }

    func testAReplayReportsTheVerifiedCache() async throws {
        let cache = try await preparedCache(for: demoImage)
        let viewModel = makeViewModel(cache: cache)

        viewModel.selectImage(UIImage(cgImage: demoImage))
        viewModel.scan()
        try await waitForCompletion(of: viewModel)

        XCTAssertEqual(
            viewModel.recognitionSource,
            .verifiedCache,
            "The review screen must be able to say the result was reused."
        )
        XCTAssertTrue(viewModel.isPresentingReview)
    }

    func testSelectingANewImageClearsTheProvenance() async throws {
        let cache = try await preparedCache(for: demoImage)
        let viewModel = makeViewModel(cache: cache)

        viewModel.selectImage(UIImage(cgImage: demoImage))
        viewModel.scan()
        try await waitForCompletion(of: viewModel)
        XCTAssertEqual(viewModel.recognitionSource, .verifiedCache)

        viewModel.selectImage(UIImage(cgImage: otherImage))
        XCTAssertNil(viewModel.recognitionSource, "A new photo has no result yet, so it has no provenance.")
        XCTAssertTrue(viewModel.drafts.isEmpty)
    }

    func testAFailedScanHasNoProvenance() async throws {
        let viewModel = ReceiptScannerViewModel(
            textRecognizer: MockReceiptTextRecognizer(lines: []),
            interpreter: interpreter(),
            pantryRepository: InMemoryPantryRepository(),
            recognitionCache: InMemoryReceiptRecognitionCacheStore()
        )
        viewModel.selectImage(UIImage(cgImage: demoImage))
        viewModel.scan()
        try await waitForFailure(of: viewModel)

        XCTAssertNil(viewModel.recognitionSource)
    }

    // MARK: - Request identity

    /// A slow scan of photo A must not land on top of a fast replay of
    /// photo B. The view model's scan token is what prevents it.
    func testASupersededSlowScanCannotReplaceANewerResult() async throws {
        let cache = try await preparedCache(for: demoImage)
        // A deliberately slow pipeline for the first (uncached) photo.
        let viewModel = ReceiptScannerViewModel(
            textRecognizer: MockReceiptTextRecognizer(lines: colesLines, delay: .milliseconds(400)),
            interpreter: interpreter(),
            pantryRepository: InMemoryPantryRepository(),
            recognitionCache: cache
        )

        viewModel.selectImage(UIImage(cgImage: otherImage))
        viewModel.scan()
        XCTAssertTrue(viewModel.scanState.isScanning)

        // Before that finishes, pick the prepared photo, which replays fast.
        viewModel.selectImage(UIImage(cgImage: demoImage))
        viewModel.scan()
        try await waitForCompletion(of: viewModel)

        XCTAssertEqual(viewModel.recognitionSource, .verifiedCache)

        // Give the abandoned scan more than enough time to come back.
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(
            viewModel.recognitionSource,
            .verifiedCache,
            "The older request must not overwrite the newer result."
        )
    }

    func testCancellingAReplayLeavesNoTrace() async throws {
        let cache = try await preparedCache(for: demoImage)
        let viewModel = makeViewModel(cache: cache, recognizerDelay: .milliseconds(300))

        viewModel.selectImage(UIImage(cgImage: demoImage))
        viewModel.scan()
        viewModel.cancelScan()

        XCTAssertEqual(viewModel.scanState, .idle)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(viewModel.drafts.isEmpty, "A cancelled scan must publish nothing.")
        XCTAssertNil(viewModel.recognitionSource)
    }

    func testRepeatedSelectionsOfTheSamePreparedPhotoAreStable() async throws {
        let cache = try await preparedCache(for: demoImage)
        let viewModel = makeViewModel(cache: cache)

        for _ in 0 ..< 3 {
            viewModel.selectImage(UIImage(cgImage: demoImage))
            viewModel.scan()
            try await waitForCompletion(of: viewModel)
            XCTAssertEqual(viewModel.recognitionSource, .verifiedCache)
            XCTAssertEqual(viewModel.drafts.count, 2)
        }
    }

    // MARK: - Helpers

    private func waitForCompletion(
        of viewModel: ReceiptScannerViewModel,
        timeout: Duration = .seconds(5)
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

    private func waitForFailure(
        of viewModel: ReceiptScannerViewModel,
        timeout: Duration = .seconds(5)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if case .failed = viewModel.scanState { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for the scan to fail.")
    }
}
