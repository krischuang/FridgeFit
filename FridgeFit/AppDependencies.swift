//
//  AppDependencies.swift
//  FridgeFit
//

import FirebaseAuth
import Foundation
import SwiftData

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
    /// Recipes saved from Discover. In SwiftData mode they live in the same
    /// on-device store as the pantry, so a saved recipe is read back without
    /// calling the recipe provider. In Firebase mode this follows
    /// `OnlineRecipeFeature.savedRecipeStorage` and is `nil` until the
    /// Firestore rules are deployed. `nil` means saving isn't offered.
    let savedRecipeRepository: (any SavedRecipeRepository)?

    /// The money side: budget, logged spends, valued waste, per-item prices
    /// and the price book.
    ///
    /// Resolved here, from the same `backend` as the pantry, so the two
    /// cannot disagree about where the user's data is. `ContentView` used to
    /// build `FundsEnvironment.firestore(pantryRepository:)` itself, which
    /// meant the shipping build - whose `compiledDefault` is `.swiftData` -
    /// kept the pantry on the device and the prices of that pantry's contents
    /// in the cloud.
    let fundsEnvironment: FundsEnvironment

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
            // One context for these two repositories. Required, not an
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
            // Saved recipes get the container, not the shared context: they
            // relate to nothing outside their own two models, and their own
            // context is what lets a failed write roll back without
            // discarding unsaved pantry work. See
            // `SwiftDataSavedRecipeStore.context`.
            savedRecipeRepository = SwiftDataSavedRecipeRepository(
                store: SwiftDataSavedRecipeStore(
                    container: container.modelContainer,
                    ownerIDProvider: ownerIDProvider
                )
            )
            // Same context and the same owner source as the pantry above, so
            // an ingredient and its price are one account's data in one
            // store file.
            fundsEnvironment = .swiftData(
                pantryRepository: pantryRepository,
                context: container.mainContext,
                ownerIDProvider: ownerIDProvider
            )

        case .firebase:
            persistenceContainer = nil
            pantryRepository = FirestorePantryRepository()
            eventRepository = FirestoreInventoryEventRepository()
            savedRecipeRepository = OnlineRecipeFeature.makeSavedRecipeRepository()
            fundsEnvironment = .firestore(pantryRepository: pantryRepository)
        }
    }

    /// Builds the graph from an already-made pair, for previews and tests.
    ///
    /// - Parameter fundsEnvironment: defaults to the in-memory money stores
    ///   over the supplied pantry. Deliberately not the sample data: a
    ///   preview showing invented budget figures as the user's own is the
    ///   failure `FundsEnvironment.sample` is kept separate to prevent.
    init(
        backend: PersistenceBackend,
        pantryRepository: any PantryRepository,
        eventRepository: any InventoryEventRepository,
        savedRecipeRepository: (any SavedRecipeRepository)? = nil,
        fundsEnvironment: FundsEnvironment? = nil
    ) {
        self.backend = backend
        self.pantryRepository = pantryRepository
        self.eventRepository = eventRepository
        self.savedRecipeRepository = savedRecipeRepository
        self.fundsEnvironment = fundsEnvironment ?? .inMemory(pantryRepository: pantryRepository)
        self.persistenceContainer = nil
    }

    // MARK: - Account deletion

    /// Builds the account-deletion use case.
    ///
    /// ## Why Firestore is always a stage, even in SwiftData mode
    ///
    /// `PersistenceBackend` only decides where *business data* lives.
    /// Authentication, the remote-camera device registry and WebRTC
    /// signalling are always Firebase (see `PersistenceConfiguration`), so a
    /// SwiftData build still writes `users/{uid}/devices` and
    /// `users/{uid}/webrtcSessions`. On top of that, a user who ever ran a
    /// Firebase-backed build has a pantry up there too. Skipping the remote
    /// stage would therefore leave real data behind on a "deleted" account,
    /// so it runs unconditionally - and deleting collections that are already
    /// empty costs one query each.
    ///
    /// ## Order
    ///
    /// Remote, then local store, then on-device caches. The first must happen
    /// while the auth token is still valid; `DeleteAccountUseCase` explains
    /// why that forces data-before-login.
    func makeDeleteAccountUseCase() -> DeleteAccountUseCase {
        var stages: [any AccountDataDeleting] = [FirestoreAccountDataDeleter()]

        if let persistenceContainer {
            stages.append(
                SwiftDataAccountDataDeleter(
                    // The pantry and event repositories read through this
                    // context, so deleting through it too means their live
                    // objects are updated rather than invalidated behind
                    // their backs.
                    context: persistenceContainer.mainContext,
                    // Saved recipes are written through a context of their
                    // own (see `SwiftDataSavedRecipeStore.context`), which is
                    // private to that store, so deletion gets its own
                    // context over the same container - same store file,
                    // same rows.
                    savedRecipeContext: ModelContext(persistenceContainer.modelContainer)
                )
            )
        }

        stages.append(LocalStateAccountDataDeleter())

        // `nil` unless a backend is configured, which it is not by default -
        // see `AccountDeletionBackendConfiguration` for why. With `nil` the
        // use case takes the on-device path, exactly as before.
        let backend = AccountDeletionBackendConfiguration.baseURL.map {
            CallableAccountDeletionBackend(baseURL: $0)
        }

        return DeleteAccountUseCase(
            auth: FirebaseAccountAuthenticator(),
            data: CompositeAccountDataDeleter(stages: stages),
            backend: backend,
            localData: makeLocalAccountDataDeleter()
        )
    }

    /// Everything **this device** holds for one account, with no cloud stage.
    ///
    /// Two callers. On the backend deletion path the server owns the
    /// Firestore side, so the client's only remaining job is the local copy.
    /// And `AppGraphEndToEndTests` uses it to delete one account's local data
    /// through the same construction the app uses, rather than reaching into
    /// the container - which would mean the test proved something about a
    /// hand-built deleter instead of the real one.
    func makeLocalAccountDataDeleter() -> any AccountDataDeleting {
        var stages: [any AccountDataDeleting] = []

        if let persistenceContainer {
            stages.append(
                SwiftDataAccountDataDeleter(
                    context: persistenceContainer.mainContext,
                    savedRecipeContext: ModelContext(persistenceContainer.modelContainer)
                )
            )
        }
        stages.append(LocalStateAccountDataDeleter())

        return CompositeAccountDataDeleter(stages: stages)
    }
}
