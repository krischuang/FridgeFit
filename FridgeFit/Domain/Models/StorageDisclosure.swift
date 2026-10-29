//
//  StorageDisclosure.swift
//  FridgeFit
//

import Foundation

/// Where one kind of FridgeFit data is actually kept.
nonisolated enum DataLocation: Equatable, Sendable {
    /// On this device only. Never uploaded, and not synced to another
    /// device or to iCloud.
    case onDeviceOnly
    /// Cloud Firestore, under the signed-in account's own `users/{uid}`
    /// subtree and readable by nobody else (see `firestore.rules`).
    case privateCloud
    /// Sent to a third party that is not FridgeFit, carrying no account
    /// identifier.
    ///
    /// Its own case rather than being folded into `privateCloud`, because
    /// the distinction is the one a user most needs: "stored under your
    /// account, readable by nobody else" and "handed to another company"
    /// are different promises, and a screen headed *where your data lives*
    /// that collapses them is not answering the question.
    case thirdParty(name: String)

    var shortLabel: String {
        switch self {
        case .onDeviceOnly: return "On this device"
        case .privateCloud: return "Your private cloud"
        case .thirdParty(let name): return "Sent to \(name)"
        }
    }
}

/// One truthful line of "where your data lives", for Profile → Settings.
///
/// ## Why this is a domain type and not strings in the view
///
/// The row it replaces said "Sync status — Firestore account sync — Private,
/// user-scoped cloud storage", unconditionally. In the shipping
/// configuration that was **false**: `PersistenceConfiguration.compiledDefault`
/// is `.swiftData`, so the pantry, the activity log and saved recipes never
/// leave the device. The screen was telling the user their groceries were in
/// the cloud while the code kept them in a local database.
///
/// A claim about storage is only as good as its coupling to the thing that
/// decides storage. So the disclosure is derived from `PersistenceBackend` -
/// the same value `AppDependencies` switches on to pick the repositories -
/// and `StorageDisclosureTests` asserts the two cannot drift apart. The view
/// renders whatever this returns and invents nothing.
nonisolated struct StorageDisclosure: Equatable, Sendable, Identifiable {
    /// What the user calls this data.
    let title: String
    /// Where it is.
    let location: DataLocation
    /// The specific stores involved, for someone who wants the detail.
    let detail: String

    var id: String { title }

    /// The full, accurate picture for a given backend.
    ///
    /// - Parameters:
    ///   - backend: what `AppDependencies` actually built.
    ///   - onlineRecipesEnabled: whether the Discover tab may call the
    ///     recipe provider. Defaults to the live feature state. When it is
    ///     off, Discover performs no networking at all and the row is
    ///     omitted rather than describing a transfer that cannot happen.
    static func all(
        for backend: PersistenceBackend,
        onlineRecipesEnabled: Bool = OnlineRecipeFeature.provider == .enabled
    ) -> [StorageDisclosure] {
        let businessDataLocation: DataLocation
        let businessDataDetail: String

        switch backend {
        case .swiftData:
            businessDataLocation = .onDeviceOnly
            businessDataDetail = "Stored in FridgeFit's on-device database. Not uploaded, and not synced between devices."
        case .firebase:
            businessDataLocation = .privateCloud
            businessDataDetail = "Stored under your account in Cloud Firestore. Only your signed-in account can read it."
        }

        var disclosures: [StorageDisclosure] = [
            StorageDisclosure(
                title: "Pantry, activity and saved recipes",
                location: businessDataLocation,
                detail: businessDataDetail
            ),
            StorageDisclosure(
                title: "Budget, spends and saved prices",
                location: businessDataLocation,
                detail: businessDataDetail
            ),
            // Always Firebase, whatever the backend says. Two devices cannot
            // find each other through a database that only one of them can
            // read, so pairing and WebRTC signalling are infrastructure
            // rather than switchable business data - see
            // `PersistenceConfiguration`.
            StorageDisclosure(
                title: "Camera pairing",
                location: .privateCloud,
                detail: "Device names and connection setup messages, under your account. Video and photos go straight between your devices and are never uploaded."
            ),
            StorageDisclosure(
                title: "Your sign-in",
                location: .privateCloud,
                detail: "Your email address, held by Firebase Authentication to identify your account."
            ),
        ]

        // The one transfer to a company that is not FridgeFit. Omitting it
        // from a screen headed "where your data lives" was an inaccuracy by
        // omission: the Discover search carries the ingredient names *and*
        // the Avoid list, which is user-provided health information.
        if onlineRecipesEnabled {
            disclosures.append(
                StorageDisclosure(
                    title: "Discover recipe searches",
                    location: .thirdParty(name: "Spoonacular"),
                    detail: "When you search Discover, the ingredient names, your Avoid list and your diet filter go to the recipe service. No account, email or device identifier is sent, so a search isn't linked to you."
                )
            )
        }

        return disclosures
    }

    /// The sentence that has to be on the screen because its absence is what
    /// made the old copy misleading.
    ///
    /// FridgeFit has no iCloud, CloudKit or cross-device sync of any kind.
    /// Saying so explicitly is the difference between "we didn't claim sync"
    /// and "we told the user there isn't any".
    static let noSyncNotice = "FridgeFit doesn't use iCloud and doesn't sync your kitchen between devices."
}
