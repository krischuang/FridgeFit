//
//  PersistenceConfigurationTests.swift
//  FridgeFitTests
//

import SwiftUI
import XCTest
@testable import FridgeFit

/// Tests the backend selection itself, and the dependency graph it produces.
///
/// The thing being guarded here is subtle and was the audit's highest-risk
/// finding: a build can be *configured* for SwiftData and still reach a
/// Firestore repository through a default that nobody noticed, writing a
/// confirmed ingredient to the cloud while the Kitchen tab reads the local
/// store. Nothing errors; the item simply isn't where the user looks for it.
/// These tests exist so that failure is a red test rather than a live demo.
///
/// ## Every test that builds `AppDependencies` is `async`
///
/// Not a style choice. Constructing the graph - and therefore a
/// `ModelContainer` - from a *synchronous* test method aborts the test host
/// with `malloc: pointer being freed was not allocated`, killing the run and
/// taking the rest of the suite with it. The identical body in an `async`
/// method is fine. Narrowed by bisecting the suite one test at a time: the
/// crash tracked the first test to construct `AppDependencies`, whichever
/// that happened to be alphabetically, and disappeared when the two
/// synchronous cases were made `async`.
///
/// So any new test here that touches the graph must be `async`, or it will
/// take the whole suite down rather than fail on its own.
@MainActor
final class PersistenceConfigurationTests: XCTestCase {

    private let overrideKey = "persistence"
    private var originalOverride: String?

    override func setUp() async throws {
        try await super.setUp()
        originalOverride = UserDefaults.standard.string(forKey: overrideKey)
    }

    override func tearDown() async throws {
        if let originalOverride {
            UserDefaults.standard.set(originalOverride, forKey: overrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: overrideKey)
        }
        try await super.tearDown()
    }

    // MARK: - Configuration

    /// The assessment build must demonstrate native persistence on launch,
    /// not only after someone flips a switch.
    func test_compiledDefaultIsSwiftData() {
        XCTAssertEqual(PersistenceConfiguration.compiledDefault, .swiftData)
    }

    /// The launch argument is what makes the live demo a scheme change rather
    /// than a code edit.
    func test_launchArgumentSelectsTheBackend() {
        UserDefaults.standard.set("firebase", forKey: overrideKey)
        XCTAssertEqual(PersistenceConfiguration.launchArgumentOverride, .firebase)
        XCTAssertEqual(PersistenceConfiguration.backend, .firebase)

        UserDefaults.standard.set("swiftData", forKey: overrideKey)
        XCTAssertEqual(PersistenceConfiguration.backend, .swiftData)
    }

    /// A typo in a scheme argument must not be able to stop the app
    /// launching - it falls through to the compiled default.
    func test_unrecognisedLaunchArgumentIsIgnored() {
        UserDefaults.standard.set("postgres", forKey: overrideKey)

        XCTAssertNil(PersistenceConfiguration.launchArgumentOverride)
        XCTAssertEqual(PersistenceConfiguration.backend, PersistenceConfiguration.compiledDefault)
    }

    func test_withNoOverride_backendIsTheCompiledDefault() {
        UserDefaults.standard.removeObject(forKey: overrideKey)

        XCTAssertEqual(PersistenceConfiguration.backend, PersistenceConfiguration.compiledDefault)
    }

    // MARK: - The graph each backend produces

    /// Which concrete type a repository is, by name.
    ///
    /// ## Why reflection rather than `is SwiftDataPantryRepository`
    ///
    /// The obvious `is` check **crashes this toolchain**. Narrowed by running
    /// the tests one at a time: a dynamic cast from `any PantryRepository` to
    /// a `@MainActor`-isolated conforming class aborts with
    /// `malloc: pointer being freed was not allocated`, which kills the test
    /// host and takes the rest of the suite with it. The same cast to the
    /// `nonisolated` conformances - `FirestorePantryRepository`,
    /// `UnconfiguredPantryRepository` - is fine, which is what identifies
    /// isolated-conformance casting as the trigger rather than anything in
    /// `AppDependencies`.
    ///
    /// `type(of:)` only reads the metatype, so it never performs a
    /// conformance lookup. The assertion is just as strong: it names the
    /// exact type the composition root produced.
    private func typeName(of repository: Any) -> String {
        String(describing: type(of: repository))
    }

    /// SwiftData mode must produce SwiftData repositories - *both* of them.
    /// A graph that was local for the pantry and cloud for its history would
    /// record activity for food the other store has never heard of.
    func test_swiftDataBackend_buildsSwiftDataRepositories() async throws {
        let dependencies = try AppDependencies(backend: .swiftData, storage: .inMemory, ownerIDProvider: { "test-owner" })

        XCTAssertEqual(dependencies.backend, .swiftData)
        XCTAssertEqual(typeName(of: dependencies.pantryRepository), "SwiftDataPantryRepository")
        XCTAssertEqual(typeName(of: dependencies.eventRepository), "SwiftDataInventoryEventRepository")
    }

    /// No Firestore repository may be constructed in SwiftData mode. This is
    /// the assertion that would have caught the environment-key default.
    func test_swiftDataBackend_buildsNoFirestoreRepository() async throws {
        let dependencies = try AppDependencies(backend: .swiftData, storage: .inMemory, ownerIDProvider: { "test-owner" })

        XCTAssertNotEqual(typeName(of: dependencies.pantryRepository), "FirestorePantryRepository")
        XCTAssertNotEqual(typeName(of: dependencies.eventRepository), "FirestoreInventoryEventRepository")
    }

    /// Firebase remains a selectable backend.
    ///
    /// ## Why this does not construct the graph
    ///
    /// `AppDependencies(backend: .firebase)` was tried here and **crashes the
    /// test host**: building `Firestore.firestore()` inside this unit-test
    /// process aborts with `malloc: pointer being freed was not allocated`,
    /// which killed the run and took the rest of the suite with it.
    ///
    /// That is consistent with the rest of this project's test suite, which
    /// has never instantiated a Firestore client - the three Firestore
    /// mapping suites test `encode`/`decode` as pure static functions
    /// precisely so no live client is needed. It is an environment limit, not
    /// a defect in the adapter.
    ///
    /// So what is asserted here is the part that can be: that `.firebase` is
    /// a real, selectable configuration. **The Firebase graph itself is
    /// therefore not covered by an automated test** - it is verified by
    /// launching the app with `-persistence firebase`, and that gap is
    /// recorded rather than papered over.
    func test_firebaseIsASelectableBackend() {
        XCTAssertEqual(PersistenceBackend(rawValue: "firebase"), .firebase)
        XCTAssertTrue(PersistenceBackend.allCases.contains(.firebase))

        UserDefaults.standard.set("firebase", forKey: overrideKey)
        XCTAssertEqual(
            PersistenceConfiguration.backend,
            .firebase,
            "The cloud path must stay reachable without a code change"
        )
    }

    /// Every screen must read one store.
    ///
    /// `ContentView` hands `dependencies.pantryRepository` to eight view
    /// models and into the environment for the camera review sheet, so this
    /// is the property the whole app relies on: write through the graph's
    /// pantry, and the graph's Kitchen sees it. Two repositories over one
    /// file would pass a shallower test and then disagree the moment either
    /// cached anything.
    func test_theGraphsRepositoriesShareOneStore() async throws {
        let dependencies = try AppDependencies(
            backend: .swiftData,
            storage: .inMemory,
            ownerIDProvider: { "test-owner" }
        )
        let item = PantryItem(ingredient: Ingredient(name: "Shared Milk"), quantity: 1, unit: .liters)

        try await dependencies.pantryRepository.add(item)
        try await dependencies.eventRepository.append(
            InventoryEvent(pantryItemID: item.id, itemName: item.name, kind: .added, note: "1 L")
        )

        // The Kitchen tab, built the way ContentView builds it.
        let kitchen = InventoryStore(
            pantryRepository: dependencies.pantryRepository,
            eventRepository: dependencies.eventRepository
        )
        await kitchen.load()

        XCTAssertEqual(kitchen.items.map(\.name), ["Shared Milk"])
        XCTAssertEqual(kitchen.events.map(\.kind), [.added])
        XCTAssertNil(kitchen.errorMessage)
    }

    // MARK: - No silent fallback

    /// The environment default must refuse rather than quietly storing
    /// somewhere.
    ///
    /// Before this change it was a live `FirestorePantryRepository()`, which
    /// in SwiftData mode meant the camera review sheet wrote confirmed
    /// ingredients to Firestore while the Kitchen tab read the local store.
    /// Reads return empty (a screen that only displays the pantry shows its
    /// normal empty state); writes throw, because a write that appears to
    /// succeed and stores nothing is the failure being prevented.
    func test_environmentDefault_refusesWritesInsteadOfPickingABackend() async throws {
        let fallback = EnvironmentValues().pantryRepository

        XCTAssertEqual(
            typeName(of: fallback),
            "UnconfiguredPantryRepository",
            "The default must not construct a real backend"
        )

        let item = PantryItem(ingredient: Ingredient(name: "Anything"), quantity: 1, unit: .pieces)
        let empty = try await fallback.fetchAll()
        XCTAssertTrue(empty.isEmpty)

        await assertThrowsNotConfigured { try await fallback.add(item) }
        await assertThrowsNotConfigured { try await fallback.update(item) }
        await assertThrowsNotConfigured { try await fallback.remove(id: item.id) }
    }

    /// The injected value wins over the default, which is what makes the
    /// camera review sheet - four levels below the composition root - read
    /// the same pantry as every other screen.
    func test_injectedRepositoryOverridesTheDefault() {
        let injected = InMemoryPantryRepository()
        var environment = EnvironmentValues()
        environment.pantryRepository = injected

        XCTAssertTrue(environment.pantryRepository === injected)
    }

    private func assertThrowsNotConfigured(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected notConfigured", file: file, line: line)
        } catch let error as PantryRepositoryError {
            XCTAssertEqual(error, .notConfigured, file: file, line: line)
        } catch {
            XCTFail("Expected PantryRepositoryError, got \(error)", file: file, line: line)
        }
    }
}
