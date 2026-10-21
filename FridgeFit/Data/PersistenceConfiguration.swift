//
//  PersistenceConfiguration.swift
//  FridgeFit
//

import Foundation

/// Where the user's business data - the pantry and its activity history - is
/// stored.
///
/// This covers *business data only*. Authentication, remote-device presence
/// and WebRTC signalling are always Firebase, whatever this says: they need
/// listeners and a rendezvous between two devices, which a local database
/// cannot provide. See `FIREBASE_COMPATIBILITY_AND_ROLLBACK.md`.
nonisolated enum PersistenceBackend: String, Equatable, CaseIterable, Sendable {
    /// On-device SwiftData. The assessment configuration.
    case swiftData
    /// Cloud Firestore, scoped per user. Preserved for later development.
    case firebase
}

/// The one place that decides which backend the app uses.
///
/// ## Why this is centralised
///
/// Deliberately not a per-screen or per-repository choice. A build whose
/// pantry was local while its event log was in Firestore would record history
/// for food the other store has never heard of, and the Kitchen tab would
/// disagree with the Pantry tab about what the user owns. One switch, read in
/// one place.
///
/// Follows the same idiom as `OnlineRecipeFeature`, which is already "the one
/// place that decides how much of the online-recipe feature is switched on,
/// and the only file that has to change to switch more of it on".
///
/// ## The rule
///
/// **No View and no ViewModel may read this.** Only `AppDependencies` does.
/// Anything else would reintroduce exactly the scattered backend selection
/// this type exists to remove - and a screen that picked its own store would
/// be invisible until it disagreed with the rest of the app.
///
/// ## Switching backends does not move data
///
/// Changing the backend changes *which store is read*. It copies nothing. An
/// item added under `.swiftData` is not in Firestore, and vice versa. Each
/// mode has exactly one source of truth, which is why no synchronisation,
/// migration or conflict resolution exists anywhere in the project.
nonisolated enum PersistenceConfiguration {

    /// What the app will use.
    ///
    /// Resolution order:
    /// 1. A `-persistence swiftData|firebase` launch argument, so the demo and
    ///    UI-level checks can switch backend from the scheme without a code
    ///    edit or a rebuild.
    /// 2. `compiledDefault`.
    ///
    /// An unrecognised launch argument is ignored rather than treated as an
    /// error: it should not be able to stop the app from launching.
    static var backend: PersistenceBackend {
        if let override = launchArgumentOverride {
            return override
        }
        return compiledDefault
    }

    /// SwiftData is the default, so the shipped build demonstrates native
    /// persistence on launch rather than only after someone flips a switch.
    ///
    /// Change this one line to `.firebase` to put the cloud back in front -
    /// every Firestore code path is still present and still tested.
    static let compiledDefault: PersistenceBackend = .swiftData

    /// Reads `-persistence <value>`. `UserDefaults` exposes launch arguments
    /// in that form, which is why no manual `ProcessInfo` parsing is needed.
    static var launchArgumentOverride: PersistenceBackend? {
        guard let raw = UserDefaults.standard.string(forKey: "persistence") else { return nil }
        return PersistenceBackend(rawValue: raw)
    }
}
