//
//  PersistenceContainer.swift
//  FridgeFit
//

import Foundation
import SwiftData

/// Owns the app's single `ModelContainer`.
///
/// ## Why one container, built here
///
/// Two containers over one store file is a staleness and corruption risk, so
/// exactly one is created - by `AppDependencies`, at launch - and both
/// SwiftData repositories are handed its `mainContext`. Sharing the context
/// is not an optimisation: linking an `InventoryEventEntity` to its
/// `PantryItemEntity` requires both objects to be managed by the *same*
/// context, so two contexts would silently break the relationship that the
/// activity history depends on.
///
/// ## Why `mainContext` and not `@ModelActor`
///
/// `ModelContext` is not `Sendable`, so it has to be confined somewhere. The
/// only callers are already on the main actor - `InventoryStore`,
/// `PantryViewModel` and the camera review sheet are all `@MainActor` - and a
/// pantry is tens of rows, not a dataset that needs a background context. A
/// `@ModelActor` would add isolation hops and `Sendable` plumbing to move
/// data back to the actor it came from, for no measurable benefit, and would
/// give each repository its own context - which is the problem described
/// above.
///
/// ## Why there is no `.modelContainer()` modifier and no `@Query`
///
/// Neither is used anywhere in the app, on purpose. `@Query` binds a SwiftUI
/// view directly to SwiftData, which is the coupling the repository
/// abstraction exists to prevent - and a view written that way would work in
/// SwiftData mode and silently render nothing in Firebase mode. Views keep
/// reading `@Published` state from view models.
@MainActor
final class PersistenceContainer {

    /// Where the store lives.
    enum Storage {
        /// The real on-disk store, in the app's default location. What the
        /// app runs on.
        case onDisk
        /// No file at all. Used by unit tests that only need CRUD semantics
        /// and want nothing left behind between cases.
        case inMemory
        /// A specific file. Used by the relaunch test, which has to prove
        /// data survives a container being torn down and rebuilt over the
        /// same file - something an in-memory store can never demonstrate.
        case file(URL)
    }

    /// Every `@Model` type in the app, in one place.
    ///
    /// A type missing here is not a compile error - it is a crash the first
    /// time something tries to fetch it, so the list is kept beside the
    /// container rather than inline at each call site.
    static let schema = Schema([
        PantryItemEntity.self,
        InventoryEventEntity.self,
    ])

    let modelContainer: ModelContainer

    init(storage: Storage = .onDisk) throws {
        let configuration: ModelConfiguration
        switch storage {
        case .onDisk:
            configuration = ModelConfiguration(schema: Self.schema)
        case .inMemory:
            configuration = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)
        case .file(let url):
            configuration = ModelConfiguration(schema: Self.schema, url: url)
        }
        modelContainer = try ModelContainer(for: Self.schema, configurations: [configuration])
    }

    var mainContext: ModelContext { modelContainer.mainContext }
}
