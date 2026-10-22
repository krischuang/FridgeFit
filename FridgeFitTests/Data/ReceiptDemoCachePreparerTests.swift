//
//  ReceiptDemoCachePreparerTests.swift
//  FridgeFitTests
//

import CoreGraphics
import XCTest
@testable import FridgeFit

/// What preparation refuses to cache.
///
/// The preparer is the only thing that can write to the recognition cache,
/// so its judgement is the last line between a misread receipt and a
/// permanently fast misread receipt.
@MainActor
final class ReceiptDemoCachePreparerTests: XCTestCase {

    private var colesLines: [String] {
        [
            "Coles Supermarkets Australia Pty Ltd",
            "COLS TOMATOES 1KG       3.60",
            "FREE RANGE EGGS 12PK    5.20",
            "FULL CREAM MILK 2L      3.00"
        ]
    }

    private func item(
        _ echo: String,
        _ displayName: String,
        _ canonicalName: String,
        quantity: Double,
        unit: String
    ) -> RawInterpretedReceiptItem {
        RawInterpretedReceiptItem(
            originalText: echo,
            displayName: displayName,
            canonicalName: canonicalName,
            classification: "ingredient",
            category: "Produce",
            quantity: quantity,
            unit: unit
        )
    }

    private func makePreparer(
        interpreting items: [RawInterpretedReceiptItem],
        lines: [String]? = nil,
        cache: ReceiptRecognitionCacheStoring = InMemoryReceiptRecognitionCacheStore()
    ) -> ReceiptDemoCachePreparer {
        ReceiptDemoCachePreparer(
            textRecognizer: MockReceiptTextRecognizer(lines: lines ?? colesLines),
            interpreter: MockReceiptIngredientInterpreter(
                result: .success(ReceiptInterpretationResult(items: items))
            ),
            cache: cache
        )
    }

    private var image: CGImage { ReceiptImageFixtures.demoLikeReceipt(width: 971, height: 1619) }

    private var goodItems: [RawInterpretedReceiptItem] {
        [
            item("COLS TOMATOES 1KG", "Tomatoes", "tomato", quantity: 1, unit: "kg"),
            item("FREE RANGE EGGS 12PK", "Free Range Eggs", "egg", quantity: 12, unit: "pcs"),
            item("FULL CREAM MILK 2L", "Full Cream Milk", "milk", quantity: 2, unit: "L")
        ]
    }

    // MARK: - A good result

    func testACleanResultHasNoDiscrepanciesAndIsPersistable() async throws {
        let report = try await makePreparer(interpreting: goodItems).analyze(image: image)

        XCTAssertTrue(
            report.discrepancies.isEmpty,
            "Unexpected: \(report.discrepancies.map(\.message))"
        )
        XCTAssertTrue(report.isPersistable)
        XCTAssertEqual(report.outcome.source, .appleIntelligence)
    }

    func testPreparationAlwaysRunsTheModel() async throws {
        let cache = InMemoryReceiptRecognitionCacheStore()
        let preparer = makePreparer(interpreting: goodItems, cache: cache)

        try preparer.persist(try await preparer.analyze(image: image))

        // Even with the entry now present, a second preparation must still
        // run the pipeline rather than replay what it just wrote.
        let second = try await preparer.analyze(image: image)
        XCTAssertEqual(
            second.outcome.source,
            .appleIntelligence,
            "Preparation that replayed its own output would verify nothing."
        )
    }

    // MARK: - The confusions that matter

    /// First, the reassuring half: on a cleanly read line the deterministic
    /// `ReceiptQuantityParser` wins outright, so a model that proposes the
    /// price cannot get it onto the candidate at all.
    func testTheDeterministicParserOverridesAModelThatProposesThePrice() async throws {
        let report = try await makePreparer(interpreting: [
            item("COLS TOMATOES 1KG", "Tomatoes", "tomato", quantity: 3.60, unit: "kg"),
            item("FREE RANGE EGGS 12PK", "Free Range Eggs", "egg", quantity: 12, unit: "pcs"),
            item("FULL CREAM MILK 2L", "Full Cream Milk", "milk", quantity: 2, unit: "L")
        ]).analyze(image: image)

        let tomatoes = try XCTUnwrap(report.outcome.pantryCandidates.first { $0.displayName.contains("Tomato") })
        XCTAssertEqual(
            tomatoes.quantity,
            ReceiptQuantity(value: 1, unit: .kilograms),
            "The pack size printed on the line beats the model's number."
        )
        XCTAssertTrue(report.isPersistable)
    }

    /// And the half that needs a guard: when OCR mangles the pack size
    /// ("1KG" read as "IKG"), the parser finds nothing and the model's
    /// proposal is used - at which point $3.60 really can become
    /// "3.6 kg of tomatoes". That is the failure a demo would hide, because
    /// a cached wrong answer looks exactly like a cached right one.
    func testAPriceReadAsAQuantityBlocksCaching() async throws {
        let report = try await makePreparer(
            interpreting: [
                item("COLS TOMATOES IKG", "Tomatoes", "tomato", quantity: 3.60, unit: "kg"),
                item("FREE RANGE EGGS 12PK", "Free Range Eggs", "egg", quantity: 12, unit: "pcs"),
                item("FULL CREAM MILK 2L", "Full Cream Milk", "milk", quantity: 2, unit: "L")
            ],
            lines: [
                "Coles Supermarkets Australia Pty Ltd",
                "COLS TOMATOES IKG       3.60",
                "FREE RANGE EGGS 12PK    5.20",
                "FULL CREAM MILK 2L      3.00"
            ]
        ).analyze(image: image)

        let tomatoes = try XCTUnwrap(report.outcome.pantryCandidates.first { $0.displayName.contains("Tomato") })
        XCTAssertEqual(tomatoes.quantity?.value, 3.6, "Fixture precondition: the price got through as a quantity.")

        XCTAssertFalse(report.isPersistable)
        XCTAssertEqual(report.blockingDiscrepancies.count, 1)
        XCTAssertTrue(
            report.blockingDiscrepancies.first?.message.contains("price has been read as a quantity") == true,
            "Got: \(report.blockingDiscrepancies.map(\.message))"
        )
    }

    func testABlockedResultCannotBePersisted() async throws {
        let cache = InMemoryReceiptRecognitionCacheStore()
        let preparer = makePreparer(
            interpreting: [item("COLS TOMATOES IKG", "Tomatoes", "tomato", quantity: 3.60, unit: "kg")],
            lines: ["Coles Supermarkets Australia Pty Ltd", "COLS TOMATOES IKG       3.60"],
            cache: cache
        )
        let report = try await preparer.analyze(image: image)

        XCTAssertFalse(report.isPersistable)
        XCTAssertThrowsError(try preparer.persist(report))
        XCTAssertTrue(cache.stored.isEmpty, "Nothing blocked may reach the cache.")
    }

    /// A pack size that disagrees with the reference receipt - here OCR read
    /// "500G" where the paper says 1KG - is worth reading, but it is a
    /// legitimate answer. The operator decides.
    func testAPackageSizeMismatchIsReportedWithoutBlocking() async throws {
        let report = try await makePreparer(
            interpreting: [
                item("COLS TOMATOES 500G", "Tomatoes", "tomato", quantity: 500, unit: "g"),
                item("FREE RANGE EGGS 12PK", "Free Range Eggs", "egg", quantity: 12, unit: "pcs"),
                item("FULL CREAM MILK 2L", "Full Cream Milk", "milk", quantity: 2, unit: "L")
            ],
            lines: [
                "Coles Supermarkets Australia Pty Ltd",
                "COLS TOMATOES 500G      3.60",
                "FREE RANGE EGGS 12PK    5.20",
                "FULL CREAM MILK 2L      3.00"
            ]
        ).analyze(image: image)

        XCTAssertTrue(report.blockingDiscrepancies.isEmpty)
        XCTAssertTrue(report.isPersistable)
        XCTAssertTrue(
            report.discrepancies.contains { $0.message.contains("the line states 1 kg") },
            "Got: \(report.discrepancies.map(\.message))"
        )
    }

    func testAMissingExpectedItemIsReportedWithoutBlocking() async throws {
        let report = try await makePreparer(interpreting: [
            item("COLS TOMATOES 1KG", "Tomatoes", "tomato", quantity: 1, unit: "kg"),
            item("FULL CREAM MILK 2L", "Full Cream Milk", "milk", quantity: 2, unit: "L")
        ]).analyze(image: image)

        XCTAssertTrue(report.isPersistable)
        XCTAssertTrue(
            report.discrepancies.contains { $0.message.contains("FREE RANGE EGGS 12PK") },
            "Got: \(report.discrepancies.map(\.message))"
        )
    }

    /// The reference values are a checklist, never a source of data - a
    /// missing item stays missing rather than being filled in.
    func testExpectedValuesAreNeverSubstitutedIntoTheResult() async throws {
        let cache = InMemoryReceiptRecognitionCacheStore()
        let preparer = makePreparer(interpreting: [
            item("COLS TOMATOES 1KG", "Tomatoes", "tomato", quantity: 1, unit: "kg"),
            item("FULL CREAM MILK 2L", "Full Cream Milk", "milk", quantity: 2, unit: "L")
        ], cache: cache)

        let report = try await preparer.analyze(image: image)
        try preparer.persist(report)

        let names = report.outcome.pantryCandidates.map(\.displayName)
        XCTAssertEqual(names.count, 2, "The eggs the model did not find must not appear from nowhere.")
        XCTAssertFalse(names.contains { $0.localizedCaseInsensitiveContains("egg") })

        let stored = try XCTUnwrap(cache.entry(for: report.fingerprint))
        XCTAssertEqual(stored.outcome.pantryCandidates.count, 2)
    }

    /// A line that states no pack size should produce no quantity. The
    /// review screen asks the user rather than inventing one.
    func testAnAbsentQuantityIsPreservedRatherThanInvented() async throws {
        let report = try await makePreparer(
            interpreting: [item("CAPS RED", "Red Capsicum", "capsicum", quantity: 0, unit: "")],
            lines: ["Coles Supermarkets Australia Pty Ltd", "CAPS RED                2.71"]
        ).analyze(image: image)

        let capsicum = try XCTUnwrap(report.outcome.pantryCandidates.first)
        XCTAssertNil(capsicum.quantity, "A receipt that states no quantity must produce none.")

        let draft = ReceiptItemDraft(candidate: capsicum)
        XCTAssertEqual(draft.quantityText, "", "The user supplies the number.")
        XCTAssertFalse(draft.hasDetectedQuantity)
    }

    // MARK: - Nothing worth caching

    /// A scan the model could make nothing of fails outright, so there is
    /// never an empty report to be tempted into caching.
    func testAnEmptyResultFailsRatherThanProducingACacheableReport() async {
        let preparer = makePreparer(
            interpreting: [],
            lines: ["Coles Supermarkets Australia Pty Ltd", "COLS TOMATOES 1KG 3.60"]
        )

        do {
            _ = try await preparer.analyze(image: image)
            XCTFail("A scan that found nothing should fail rather than report an empty result.")
        } catch {
            XCTAssertEqual(error as? ReceiptScanError, .noFoodItemsFound)
        }
    }

    func testAnUnexpectedImageSizeIsFlagged() async throws {
        let report = try await makePreparer(interpreting: goodItems)
            .analyze(image: ReceiptImageFixtures.demoLikeReceipt(width: 100, height: 200))

        XCTAssertTrue(report.isPersistable, "A different size is a warning, not a refusal.")
        XCTAssertTrue(
            report.discrepancies.contains { $0.message.contains("100×200") },
            "Got: \(report.discrepancies.map(\.message))"
        )
    }

    // MARK: - Readiness reporting

    func testReadinessIsReadBackFromTheStore() async throws {
        let cache = InMemoryReceiptRecognitionCacheStore()
        let preparer = makePreparer(interpreting: goodItems, cache: cache)
        let report = try await preparer.analyze(image: image)

        XCTAssertNil(preparer.preparedEntry(for: report.fingerprint), "NOT READY before persisting.")
        try preparer.persist(report)
        XCTAssertNotNil(preparer.preparedEntry(for: report.fingerprint), "READY after persisting.")

        preparer.clear()
        XCTAssertNil(preparer.preparedEntry(for: report.fingerprint))
        XCTAssertTrue(preparer.allPreparedEntries().isEmpty)
    }

    func testTheReportCarriesTheFingerprintAndRecognitionTime() async throws {
        let report = try await makePreparer(interpreting: goodItems).analyze(image: image)

        XCTAssertEqual(report.fingerprint, ReceiptImageFingerprint.make(of: image))
        XCTAssertEqual(report.pixelWidth, 971)
        XCTAssertEqual(report.pixelHeight, 1619)
        XCTAssertGreaterThan(ReceiptScanMetrics.seconds(report.recognitionDuration), 0)
    }
}
