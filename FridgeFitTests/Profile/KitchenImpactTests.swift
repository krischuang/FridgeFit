//
//  KitchenImpactTests.swift
//  FridgeFitTests
//

import SwiftData
import XCTest
@testable import FridgeFit

/// Profile's Kitchen Impact section, and the one property it exists to have:
/// that it counts the *same* records My Fridge does.
///
/// ## What went wrong before
///
/// `ProfileView.loadProfileData()` built a `FirestoreInventoryEventRepository()`
/// inline and read the activity log a second time. Nothing errored. With
/// `PersistenceConfiguration.backend` at `.swiftData` - the shipped default -
/// Kitchen Impact counted events in the cloud while My Fridge counted events
/// on the device, so the two screens quietly disagreed about what the user
/// had done with their food.
///
/// A test that only seeded a repository and read the counts back would have
/// passed throughout. So the tests here are written to fail if Profile ever
/// acquires a second source again: the injected store is seeded with known
/// records, and in `test_kitchenImpactReportsUnavailable_whenTheInjectedLogFails`
/// it is made to *fail*. A screen reading anything other than what it was
/// handed cannot satisfy both.
@MainActor
final class KitchenImpactTests: XCTestCase {

    private let owner = "owner-under-test"

    // MARK: - Helpers

    /// The composition root, the way `FridgeFitApp` builds it, but over a
    /// store that leaves nothing behind.
    private func makeDependencies(
        storage: PersistenceContainer.Storage = .inMemory
    ) throws -> AppDependencies {
        try AppDependencies(
            backend: .swiftData,
            storage: storage,
            ownerIDProvider: { [owner] in owner }
        )
    }

    /// The one store `ContentView` hands to Home, My Fridge *and* Profile.
    private func makeKitchen(_ dependencies: AppDependencies) -> InventoryStore {
        InventoryStore(
            pantryRepository: dependencies.pantryRepository,
            eventRepository: dependencies.eventRepository
        )
    }

    private func item(_ name: String) -> PantryItem {
        PantryItem(ingredient: Ingredient(name: name, category: .other), quantity: 1, unit: .pieces)
    }

    /// Names the concrete type a value actually is, without a conformance
    /// lookup. Borrowed from `PersistenceConfigurationTests`.
    private func typeName(of value: Any) -> String {
        String(describing: type(of: value))
    }

    // MARK: - The data comes from the injected SwiftData graph

    /// The repositories behind Kitchen Impact are the SwiftData ones the
    /// composition root selected - not a Firestore pair, and not a second
    /// container of this screen's own.
    func test_kitchenImpactReadsTheInjectedSwiftDataRepositories() async throws {
        let dependencies = try makeDependencies()

        XCTAssertEqual(typeName(of: dependencies.eventRepository), "SwiftDataInventoryEventRepository")
        XCTAssertNotEqual(
            typeName(of: dependencies.eventRepository),
            "FirestoreInventoryEventRepository",
            "Kitchen Impact must not be reading a Firestore log while the rest of the app is local"
        )

        let kitchen = makeKitchen(dependencies)
        let milk = item("Milk")
        try await dependencies.pantryRepository.add(milk)
        await kitchen.load()

        try await kitchen.record(outcome: .finished, for: milk.id)

        XCTAssertEqual(kitchen.kitchenImpact.state, .counted(finished: 1, discarded: 0))
    }

    /// Writing an event straight through the graph's own repository - not
    /// through the store - still shows up in Kitchen Impact. One set of
    /// records, reached two ways.
    func test_kitchenImpactSeesEventsWrittenThroughTheSharedRepository() async throws {
        let dependencies = try makeDependencies()
        let kitchen = makeKitchen(dependencies)
        let spinach = item("Spinach")

        try await dependencies.pantryRepository.add(spinach)
        try await dependencies.eventRepository.append(
            InventoryEvent(pantryItemID: spinach.id, itemName: spinach.name, kind: .discarded)
        )
        await kitchen.load()

        XCTAssertEqual(kitchen.kitchenImpact.state, .counted(finished: 0, discarded: 1))
    }

    /// Profile and My Fridge are the same object, so there is no window in
    /// which one is right and the other is stale.
    ///
    /// This is the assertion the old code could not have passed: the outcome
    /// is recorded the way My Fridge records it, and read the way Profile
    /// reads it, with nothing in between.
    func test_profileAndMyFridgeReflectTheSameRecords() async throws {
        let dependencies = try makeDependencies()
        // Both screens are handed this one instance by `ContentView`.
        let shared = makeKitchen(dependencies)

        let eggs = item("Eggs")
        let bread = item("Bread")
        try await dependencies.pantryRepository.add(eggs)
        try await dependencies.pantryRepository.add(bread)
        await shared.load()
        XCTAssertEqual(shared.items.count, 2)

        // My Fridge: finish one, bin the other.
        try await shared.record(outcome: .finished, for: eggs.id)
        try await shared.record(outcome: .discarded, for: bread.id)

        // Profile, with no load of its own.
        XCTAssertEqual(shared.kitchenImpact.state, .counted(finished: 1, discarded: 1))
        // And the pantry the other tabs read agrees that both are gone.
        XCTAssertTrue(shared.items.isEmpty)
    }

    /// Undo is the deletion path: an outcome the user took back is removed
    /// from the log, so Kitchen Impact must stop counting it.
    func test_kitchenImpactDropsAnUndoneOutcome() async throws {
        let dependencies = try makeDependencies()
        let kitchen = makeKitchen(dependencies)
        let yoghurt = item("Yoghurt")

        try await dependencies.pantryRepository.add(yoghurt)
        await kitchen.load()
        try await kitchen.record(outcome: .discarded, for: yoghurt.id)
        XCTAssertEqual(kitchen.kitchenImpact.state, .counted(finished: 0, discarded: 1))

        await kitchen.undoLastAction()

        XCTAssertEqual(
            kitchen.kitchenImpact.state,
            .empty,
            "history that can be taken back must not keep being counted"
        )
        XCTAssertEqual(kitchen.items.map(\.name), ["Yoghurt"])
    }

    /// Correcting a quantity writes an event, but not an *outcome* - nothing
    /// was eaten or thrown away, so both numbers stay at zero.
    ///
    /// Note the state: `.counted(0, 0)`, not `.empty`. A log that has
    /// entries but no outcomes is a different thing from a log with nothing
    /// in it, and only the second may say "No activity yet".
    func test_kitchenImpactIgnoresEventsThatAreNotOutcomes() async throws {
        let dependencies = try makeDependencies()
        let kitchen = makeKitchen(dependencies)
        let rice = item("Rice")

        try await dependencies.pantryRepository.add(rice)
        await kitchen.load()
        try await kitchen.adjustQuantity(of: rice.id, by: 2)

        XCTAssertFalse(kitchen.events.isEmpty, "the adjustment should be in the log")
        XCTAssertEqual(kitchen.kitchenImpact.state, .counted(finished: 0, discarded: 0))
        XCTAssertEqual(kitchen.kitchenImpact.finishedCount, 0)
        XCTAssertEqual(kitchen.kitchenImpact.discardedCount, 0)
    }

    // MARK: - Empty, loading and error states

    func test_kitchenImpactIsEmpty_whenNothingHasHappened() async throws {
        let dependencies = try makeDependencies()
        let kitchen = makeKitchen(dependencies)

        await kitchen.load()

        XCTAssertEqual(kitchen.kitchenImpact.state, .empty)
        XCTAssertEqual(kitchen.kitchenImpact.finishedCount, 0)
        XCTAssertEqual(kitchen.kitchenImpact.discardedCount, 0)
    }

    /// An unread log and an empty one are different facts. Before this
    /// change both rendered as "No activity yet", which told a user whose
    /// history had failed that they had never cooked.
    func test_kitchenImpactReportsUnavailable_whenTheInjectedLogFails() async {
        let kitchen = InventoryStore(
            pantryRepository: InMemoryPantryRepository(seedItems: [item("Milk")]),
            eventRepository: FailingEventRepository()
        )

        await kitchen.load()

        XCTAssertTrue(kitchen.isActivityUnavailable)
        XCTAssertEqual(kitchen.kitchenImpact.state, .unavailable)
        XCTAssertNil(kitchen.kitchenImpact.finishedCount, "an unread log has no number to show")
        XCTAssertNil(kitchen.kitchenImpact.discardedCount)
        // The pantry is fine, and saying otherwise would imply the food
        // list is wrong when it is not.
        XCTAssertNil(kitchen.errorMessage)
        XCTAssertEqual(kitchen.items.map(\.name), ["Milk"])
    }

    /// A failure that later clears must clear the state with it.
    func test_kitchenImpactRecoversAfterTheLogBecomesReadableAgain() async {
        let events = IntermittentEventRepository()
        let kitchen = InventoryStore(
            pantryRepository: InMemoryPantryRepository(),
            eventRepository: events
        )

        events.isFailing = true
        await kitchen.load()
        XCTAssertEqual(kitchen.kitchenImpact.state, .unavailable)

        events.isFailing = false
        events.stored = [InventoryEvent(pantryItemID: UUID(), itemName: "Milk", kind: .finished)]
        await kitchen.load()

        XCTAssertFalse(kitchen.isActivityUnavailable)
        XCTAssertEqual(kitchen.kitchenImpact.state, .counted(finished: 1, discarded: 0))
    }

    // MARK: - Persistence across a relaunch

    /// Kitchen Impact's numbers survive the app being quit and reopened.
    ///
    /// Two `AppDependencies` over one store *file*, the second built after
    /// the first is released - so it shares no container, context or cache
    /// with it, and anything it counts came off the disk. An in-memory store
    /// would pass a write-then-read test while persisting nothing, which is
    /// the failure mode this is here to exclude. Same approach as
    /// `SwiftDataPersistenceRetentionTests`.
    func test_kitchenImpactSurvivesAColdStart() async throws {
        let storeURL = URL.temporaryDirectory.appending(path: "fridgefit-impact-\(UUID().uuidString).store")
        defer { removeStore(at: storeURL) }

        try await logTwoOutcomes(in: storeURL)

        // Relaunch: a second graph over the same file, built after the first
        // has gone out of scope.
        let second = try makeDependencies(storage: .file(storeURL))
        let reopened = makeKitchen(second)
        await reopened.load()

        XCTAssertEqual(
            reopened.kitchenImpact.state,
            .counted(finished: 1, discarded: 1),
            "the counts must come off the disk, not from a cache the first graph left behind"
        )
    }

    /// Finishes one item and discards another through a graph that is
    /// released when this returns - so the caller's next read cannot be
    /// served by the first container's context or cache.
    private func logTwoOutcomes(in storeURL: URL) async throws {
        let first = try makeDependencies(storage: .file(storeURL))
        let kitchen = makeKitchen(first)
        let soup = item("Soup")
        let cream = item("Cream")

        try await first.pantryRepository.add(soup)
        try await first.pantryRepository.add(cream)
        await kitchen.load()
        try await kitchen.record(outcome: .finished, for: soup.id)
        try await kitchen.record(outcome: .discarded, for: cream.id)

        XCTAssertEqual(kitchen.kitchenImpact.state, .counted(finished: 1, discarded: 1))
    }

    /// SwiftData writes `-shm` and `-wal` sidecars beside the store; a
    /// leftover pair would let a later run inherit state.
    private func removeStore(at url: URL) {
        let manager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            let sidecar = URL(fileURLWithPath: url.path + suffix)
            if manager.fileExists(atPath: sidecar.path) {
                try? manager.removeItem(at: sidecar)
            }
        }
    }
}

// MARK: - The summary's own rules

/// `KitchenImpactSummary` with no store involved, so the state machine is
/// pinned independently of how the events were fetched.
final class KitchenImpactSummaryTests: XCTestCase {

    private func event(_ kind: InventoryEventKind) -> InventoryEvent {
        InventoryEvent(pantryItemID: UUID(), itemName: "Milk", kind: kind)
    }

    func test_countsOnlyFinishedAndDiscarded() {
        let summary = KitchenImpactSummary(events: [
            event(.finished), event(.finished),
            event(.discarded),
            event(.added), event(.used), event(.opened),
            event(.quantityAdjusted), event(.edited), event(.deleted),
        ])

        XCTAssertEqual(summary.state, .counted(finished: 2, discarded: 1))
        XCTAssertEqual(summary.finishedCount, 2)
        XCTAssertEqual(summary.discardedCount, 1)
    }

    func test_anEmptyLogIsEmptyAndNotUnavailable() {
        let summary = KitchenImpactSummary(events: [])

        XCTAssertEqual(summary.state, .empty)
        XCTAssertEqual(summary.finishedCount, 0, "zero is a real answer, and shows as 0")
    }

    func test_loadingIsReportedOnlyWhileThereIsNothingToShow() {
        XCTAssertEqual(KitchenImpactSummary(events: [], isLoading: true).state, .loading)

        // A reload after a mutation keeps the previous counts on screen
        // rather than blanking them to em-dashes for a round trip.
        XCTAssertEqual(
            KitchenImpactSummary(events: [event(.finished)], isLoading: true).state,
            .counted(finished: 1, discarded: 0)
        )
    }

    /// A failed read wins over everything: counts taken from a log that did
    /// not load are not counts.
    func test_unavailableOutranksLoadingAndCounting() {
        XCTAssertEqual(
            KitchenImpactSummary(events: [event(.finished)], isUnavailable: true).state,
            .unavailable
        )
        XCTAssertEqual(
            KitchenImpactSummary(events: [], isLoading: true, isUnavailable: true).state,
            .unavailable
        )
    }
}

// MARK: - Doubles

/// Every read fails. Stands in for not being signed in, or a store that
/// would not open.
private final class FailingEventRepository: InventoryEventRepository {
    func fetchAll(limit: Int) async throws -> [InventoryEvent] { throw PantryRepositoryError.notAuthenticated }
    func append(_ event: InventoryEvent) async throws { throw PantryRepositoryError.notAuthenticated }
    func remove(ids: [UUID]) async throws { throw PantryRepositoryError.notAuthenticated }
}

/// Fails or succeeds on demand, so recovery can be observed rather than
/// assumed.
private final class IntermittentEventRepository: InventoryEventRepository {
    var isFailing = false
    var stored: [InventoryEvent] = []

    func fetchAll(limit: Int) async throws -> [InventoryEvent] {
        if isFailing { throw PantryRepositoryError.notAuthenticated }
        return Array(stored.prefix(limit))
    }

    func append(_ event: InventoryEvent) async throws {
        if isFailing { throw PantryRepositoryError.notAuthenticated }
        stored.insert(event, at: 0)
    }

    func remove(ids: [UUID]) async throws {
        if isFailing { throw PantryRepositoryError.notAuthenticated }
        stored.removeAll { ids.contains($0.id) }
    }
}
