//
//  AppDependencies.swift
//  FridgeFit
//

import FirebaseAuth
import Foundation

/// The application's composition root.
///
/// Built once, at launch, by `FridgeFitApp`. It is the **only** place in the
/// app that names a concrete business-data repository type, and the only
/// place that reads `PersistenceConfiguration`.
///
/// ## Why this exists as a type
///
/// `ContentView.init()` was doing this job implicitly: it constructed
/// `FirestorePantryRepository()` and `FirestoreInventoryEventRepository()`
/// inline and wired eight view models around them. That worked, but it put
/// the backend decision inside a `View`, where it could not be varied without
/// editing the view - and it was not the only such place. The environment
/// key's default value constructed a *second* Firestore repository, reachable
/// from the camera review sheet, which is the kind of thing that only shows
/// up when a confirmed ingredient quietly lands in a different store from the
/// one the Kitchen tab is reading.
///
/// So: one object, created before any view exists, holding the two
/// repositories everything else is handed.
///
/// ## What it does not own
///
/// Firebase Authentication, device presence and WebRTC signalling. Those are
/// always Firebase and are reached directly by the features that need them -
/// they are infrastructure, not business-data storage, and routing them
/// through here would imply they were switchable when they are not.
@MainActor
final class AppDependencies {

    /// Which backend these repositories came from. Exposed so the UI can
    /// *state* it (useful in a demo and when diagnosing a report), never so a
    /// view can branch on it.
    let backend: PersistenceBackend

    let pantryRepository: any PantryRepository
    let eventRepository: any InventoryEventRepository

    /// Retained for the lifetime of the app in SwiftData mode, `nil` in
    /// Firebase mode.
    ///
    /// Held deliberately: the repositories only keep the `ModelContext`, and
    /// if the container were allowed to deallocate the store would be torn
    /// out from under them.
    private let persistenceContainer: PersistenceContainer?

    /// - Parameters:
    ///   - backend: defaults to `PersistenceConfiguration.backend`. Injectable
    ///     so tests can build either graph without touching global state.
    ///   - ownerIDProvider: who the local data belongs to. Defaults to the
    ///     signed-in Firebase uid - the same source
    ///     `FirestorePantryRepository` resolves per call, so an item is
    ///     scoped to the same account in either mode.
    ///   - storage: where the local store lives. Defaults to the real
    ///     on-disk store. Injectable so tests can build the whole graph
    ///     against an in-memory container - repeatedly opening the app's
    ///     real store from a test process is both pointless and unstable.
    init(
        backend: PersistenceBackend = PersistenceConfiguration.backend,
        storage: PersistenceContainer.Storage = .onDisk,
        ownerIDProvider: @escaping () -> String? = { Auth.auth().currentUser?.uid }
    ) throws {
        self.backend = backend

        switch backend {
        case .swiftData:
            let container = try PersistenceContainer(storage: storage)
            persistenceContainer = container
            // One context for both repositories. Required, not an
            // optimisation: an event can only be linked to its pantry item if
            // both objects are managed by the same context.
            pantryRepository = SwiftDataPantryRepository(
                context: container.mainContext,
                ownerIDProvider: ownerIDProvider
            )
            eventRepository = SwiftDataInventoryEventRepository(
                context: container.mainContext,
                ownerIDProvider: ownerIDProvider
            )

        case .firebase:
            persistenceContainer = nil
            pantryRepository = FirestorePantryRepository()
            eventRepository = FirestoreInventoryEventRepository()
        }
    }

    /// Builds the graph from an already-made pair, for previews and tests.
    init(
        backend: PersistenceBackend,
        pantryRepository: any PantryRepository,
        eventRepository: any InventoryEventRepository
    ) {
        self.backend = backend
        self.pantryRepository = pantryRepository
        self.eventRepository = eventRepository
        self.persistenceContainer = nil
    }
}
