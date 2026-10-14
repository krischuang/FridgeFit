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
/// The default is the real Firestore repository rather than an in-memory one
/// on purpose: if the injection is ever missed, the failure should be a
/// visible auth or network error, not a silent write into a dictionary that
/// disappears. Previews and tests inject explicitly.
private struct PantryRepositoryKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: any PantryRepository = FirestorePantryRepository()
}

extension EnvironmentValues {
    /// The pantry store for this part of the view tree.
    ///
    /// Ownership comes from the repository itself: `FirestorePantryRepository`
    /// resolves `Auth.auth().currentUser?.uid` per call and writes to
    /// `users/{uid}/pantry`, so Firestore rules apply unchanged and a signed
    /// out user cannot write at all.
    var pantryRepository: any PantryRepository {
        get { self[PantryRepositoryKey.self] }
        set { self[PantryRepositoryKey.self] = newValue }
    }
}
