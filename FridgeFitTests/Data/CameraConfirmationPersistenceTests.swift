//
//  CameraConfirmationPersistenceTests.swift
//  FridgeFitTests
//

import SwiftData
import XCTest
@testable import FridgeFit

/// End-to-end: a confirmed ingredient from the camera review sheet reaches
/// the SwiftData store, and the Kitchen reads it back.
///
/// Covers the full assessment flow through its real components, with nothing
/// mocked below the UI:
///
/// ```
/// ConfirmedIngredientDraft            (what the review sheet produces)
///   → AddDetectedIngredientsUseCase
///   → AddPantryItemUseCase            (validation + duplicate rule)
///   → PantryRepository                (protocol)
///   → SwiftDataPantryRepository
///   → SwiftData store
///   → InventoryStore                  (what the Kitchen tab renders)
/// ```
///
/// `IngredientReviewPantrySaveTests` already covers this path against a
/// counting double, which proves the *use case* behaves. What is proved here
/// is different and is the thing the audit flagged: that the ingredient
/// actually lands in the configured database, and that the Kitchen - a
/// different screen, built on a different view model - sees the same row.
@MainActor
final class CameraConfirmationPersistenceTests: XCTestCase {
    private var container: PersistenceContainer!
    private var pantry: SwiftDataPantryRepository!
    private var events: SwiftDataInventoryEventRepository!

    private let owner = "camera-owner"

    override func setUp() async throws {
        try await super.setUp()
        container = try PersistenceContainer(storage: .inMemory)
        pantry = SwiftDataPantryRepository(context: container.mainContext, ownerIDProvider: { [owner] in owner })
        events = SwiftDataInventoryEventRepository(context: container.mainContext, ownerIDProvider: { [owner] in owner })
    }

    override func tearDown() async throws {
        pantry = nil
        events = nil
        container = nil
        try await super.tearDown()
    }

    private func draft(
        _ name: String,
        quantity: Double? = 1,
        unit: MeasurementUnit = .pieces,
        category: IngredientCategory = .produce
    ) -> ConfirmedIngredientDraft {
        ConfirmedIngredientDraft(name: name, quantity: quantity, unit: unit, category: category)
    }

    /// The headline flow: confirm two detections, and both are in the store.
    func test_confirmedDetections_arePersistedToSwiftData() async throws {
        let useCase = AddDetectedIngredientsUseCase(pantryRepository: pantry)

        let summary = await useCase.execute(confirmed: [
            draft("Tomato", quantity: 3),
            draft("Spinach", quantity: 1, unit: .grams, category: .produce),
        ])

        XCTAssertEqual(summary.addedNames.sorted(), ["Spinach", "Tomato"])
        XCTAssertTrue(summary.isCompleteSuccess)

        let stored = try await pantry.fetchAll()
        XCTAssertEqual(stored.map(\.name), ["Spinach", "Tomato"], "Ordered by name, as fetched")
        XCTAssertEqual(stored.first(where: { $0.name == "Tomato" })?.quantity, 3)
    }

    /// The Kitchen tab is a different screen built on a different view model.
    /// It must see what the camera just confirmed, through the same
    /// repository instance the composition root hands to both.
    func test_theKitchenSeesWhatTheCameraConfirmed() async throws {
        let useCase = AddDetectedIngredientsUseCase(pantryRepository: pantry)
        _ = await useCase.execute(confirmed: [draft("Carrot", quantity: 4)])

        let kitchen = InventoryStore(pantryRepository: pantry, eventRepository: events)
        await kitchen.load()

        XCTAssertEqual(kitchen.items.map(\.name), ["Carrot"])
        XCTAssertNil(kitchen.errorMessage)
    }

    /// Confirming the same ingredient twice is rejected by the existing
    /// duplicate rule rather than creating a second row - and that rule runs
    /// against the real database, not an array.
    func test_confirmingTheSameIngredientTwice_doesNotCreateASecondRow() async throws {
        let useCase = AddDetectedIngredientsUseCase(pantryRepository: pantry)

        _ = await useCase.execute(confirmed: [draft("Tomato")])
        let second = await useCase.execute(confirmed: [draft("tomato")])

        XCTAssertEqual(second.duplicateNames, ["Tomato"], "Matched case-insensitively")
        XCTAssertTrue(second.addedNames.isEmpty)

        let stored = try await pantry.fetchAll()
        XCTAssertEqual(stored.count, 1, "One row, not two")
    }

    /// A detection with no stated amount is reported as a failure rather than
    /// defaulted to a quantity nobody asked for - and nothing is written.
    func test_aDetectionWithNoQuantity_isRefusedAndStoresNothing() async throws {
        let useCase = AddDetectedIngredientsUseCase(pantryRepository: pantry)

        let summary = await useCase.execute(confirmed: [draft("Mystery", quantity: nil)])

        XCTAssertEqual(summary.failures.map(\.name), ["Mystery"])
        XCTAssertTrue(summary.addedNames.isEmpty)
        let stored = try await pantry.fetchAll()
        XCTAssertTrue(stored.isEmpty, "A refused row must not be half-stored")
    }

    /// One bad row must not stop the good ones. A receipt or a fridge photo
    /// can produce a dozen candidates, and a single unusable one should not
    /// discard the rest.
    func test_oneUnusableDetection_doesNotBlockTheOthers() async throws {
        let useCase = AddDetectedIngredientsUseCase(pantryRepository: pantry)

        let summary = await useCase.execute(confirmed: [
            draft("Onion", quantity: 2),
            draft("Nameless", quantity: nil),
            draft("Garlic", quantity: 1),
        ])

        XCTAssertEqual(summary.addedNames.sorted(), ["Garlic", "Onion"])
        XCTAssertEqual(summary.failures.map(\.name), ["Nameless"])

        let stored = try await pantry.fetchAll()
        XCTAssertEqual(stored.map(\.name), ["Garlic", "Onion"])
    }

    /// If the review sheet were ever presented without an injected
    /// repository, the write must fail visibly rather than land in some other
    /// store. This is the environment-key default doing its job.
    func test_withoutAnInjectedRepository_confirmingReportsAFailure() async {
        let useCase = AddDetectedIngredientsUseCase(pantryRepository: UnconfiguredPantryRepository())

        let summary = await useCase.execute(confirmed: [draft("Tomato")])

        XCTAssertTrue(summary.addedNames.isEmpty, "Nothing may be reported as added")
        XCTAssertEqual(summary.failures.map(\.name), ["Tomato"])
        XCTAssertEqual(
            summary.failures.first?.message,
            PantryRepositoryError.notConfigured.errorDescription
        )
    }

    /// The whole flow survives a relaunch, on a real file. This is the
    /// automated form of the demonstration: confirm an ingredient from a
    /// photo, quit the app, reopen it, and the ingredient is still there.
    func test_aConfirmedIngredientSurvivesRelaunch() async throws {
        let storeURL = URL.temporaryDirectory.appending(path: "fridgefit-camera-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }

        do {
            let first = try PersistenceContainer(storage: .file(storeURL))
            let repository = SwiftDataPantryRepository(
                context: first.mainContext,
                ownerIDProvider: { [owner] in owner }
            )
            _ = await AddDetectedIngredientsUseCase(pantryRepository: repository)
                .execute(confirmed: [draft("Broccoli", quantity: 2)])
        }

        let second = try PersistenceContainer(storage: .file(storeURL))
        let reopened = SwiftDataPantryRepository(
            context: second.mainContext,
            ownerIDProvider: { [owner] in owner }
        )
        let stored = try await reopened.fetchAll()

        XCTAssertEqual(stored.map(\.name), ["Broccoli"])
        XCTAssertEqual(stored.first?.quantity, 2)
    }
}
