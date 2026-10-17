//
//  PantryRepositoryEnvironment.swift
//  FridgeFit
//

import SwiftUI

/// Makes the app's pantry repository reachable from the remote-camera screens.
///
/// The review sheet lives four levels below the composition root
/// (`ContentView` → `ProfileView` → `ConnectedDevicesView` →
/// `RemoteCameraView` → review sheet), and none of the views in between have
/// any business knowing about the pantry. Threading a repository through all
/// of them would add a parameter to three unrelated screens to serve one leaf.
///
/// ## Why the default is a repository that refuses
///
/// This default used to be a live `FirestorePantryRepository()`. The
/// reasoning was sound while Firestore was the only backend: a missed
/// injection should fail as a visible auth or network error rather than
/// silently write into a dictionary that disappears.
///
/// It stops being sound the moment the backend is configurable. With
/// SwiftData selected, that default would construct a *second*, Firestore
/// repository reachable from the camera review sheet - so a confirmed
/// ingredient would be written to the cloud while the Kitchen and Pantry tabs
/// read the local store. Nothing would error. The user would simply confirm
/// an ingredient and not find it in their pantry, which is the hardest class
/// of bug to diagnose and the worst one to meet during a demonstration.
///
/// So the default now refuses: every operation throws
/// `PantryRepositoryError.notConfigured`, which surfaces as an explained
/// error in the UI. A missed injection becomes a visible, specific failure
/// instead of a write to the wrong database.
private struct PantryRepositoryKey: EnvironmentKey {
    static let defaultValue: any PantryRepository = UnconfiguredPantryRepository()
}

extension EnvironmentValues {
    /// The pantry store for this part of the view tree.
    ///
    /// Injected by `ContentView` from `AppDependencies`, so it is the same
    /// instance every other screen uses and therefore the same backend.
    /// Ownership comes from the repository itself: the Firestore
    /// implementation resolves the signed-in uid per call, and the SwiftData
    /// one scopes every query by `ownerID`.
    var pantryRepository: any PantryRepository {
        get { self[PantryRepositoryKey.self] }
        set { self[PantryRepositoryKey.self] = newValue }
    }
}

/// A pantry repository that does nothing except report that it was never
/// configured.
///
/// Exists so a missing injection is *detectable*. Reads return empty rather
/// than throwing - an empty list renders as the normal empty state and does
/// not interrupt a screen that merely displays the pantry - while every write
/// throws, because a write that appears to succeed and stores nothing is the
/// failure this type is here to prevent.
nonisolated final class UnconfiguredPantryRepository: PantryRepository {
    func fetchAll() async throws -> [PantryItem] { [] }
    func fetch(id: UUID) async throws -> PantryItem? { nil }
    func fetchExpiring(before date: Date) async throws -> [PantryItem] { [] }

    func add(_ item: PantryItem) async throws {
        throw PantryRepositoryError.notConfigured
    }

    func update(_ item: PantryItem) async throws {
        throw PantryRepositoryError.notConfigured
    }

    func remove(id: UUID) async throws {
        throw PantryRepositoryError.notConfigured
    }
}
