//
//  LocalStateAccountDataDeleter.swift
//  FridgeFit
//

import Foundation
import OSLog

/// Clears the on-device preferences and derived caches that hold traces of
/// the user's kitchen.
///
/// ## Why these files are in scope at all
///
/// None of them is "the user's data" in the sense the pantry is - they are
/// settings and caches. But three of them are derived *from* the pantry and
/// contain its contents in plain text: the substitution cache is keyed on
/// recipe titles and a pantry fingerprint and stores the suggestions, the
/// receipt cache stores the interpreted contents of photographed receipts,
/// and the online-recipe cache stores search results built from pantry
/// ingredient names. Leaving them behind after "delete my account" would
/// leave a readable record of what the user had in their fridge on a device
/// that no longer has an account. So they go.
///
/// ## The honest caveat: these stores are device-scoped, not account-scoped
///
/// `UserDefaults.standard` keys and the cache files have no `ownerID` - they
/// were written as per-install state, which is what they are. That has one
/// consequence worth stating plainly rather than hiding: on a device where
/// two accounts have both been used, deleting one account resets these
/// preferences for the device, including the other account's. The data that
/// genuinely belongs to an account - pantry, events, saved recipes, budgets,
/// prices - *is* owner-scoped and is left strictly alone for other accounts
/// (see `SwiftDataAccountDataDeleter`).
///
/// Resetting a measurement-system preference is the right side of that
/// trade: the alternative is retaining a cache of the deleted account's
/// groceries so that a different account's display settings survive.
///
/// ## What is deliberately kept
///
/// `DeviceIdentity`'s `deviceId` and `preferredRole`. They identify this
/// *install* for remote-camera pairing and say nothing about any user; the
/// account's entry in the cloud device registry is removed by
/// `FirestoreAccountDataDeleter`. Minting a new device id would only make
/// the same install look like a second one.
final class LocalStateAccountDataDeleter: AccountDataDeleting {

    /// `UserDefaults` keys written by this app's own feature stores.
    ///
    /// Kept in step with the stores that own them:
    /// `UserDefaultsProfileSettingsStore`,
    /// `UserDefaultsOnlineRecipePreferencesStore` and
    /// `UserDefaultsHiddenOnlineRecipeStore`.
    static let preferenceKeys = [
        "profileSettings",
        "onlineRecipePreferences",
        "hiddenOnlineRecipeIDs",
    ]

    /// Cache file names under Application Support/FridgeFit, matching
    /// `SubstitutionCacheStore`, `FileReceiptRecognitionCacheStore` and
    /// `FileOnlineRecipeCacheStore`.
    static let cacheFileNames = [
        "substitution-cache.json",
        "receipt-recognition-cache.json",
        "online-recipe-cache.json",
    ]

    private let defaults: UserDefaults
    private let fileManager: FileManager
    /// The directory the three cache files live in. Injectable so tests
    /// operate on a temporary directory instead of the real one.
    private let cacheDirectory: URL?
    private let logger = Logger(subsystem: "com.fridgefit.app", category: "AccountDeletion")

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        cacheDirectory: URL? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory(fileManager: fileManager)
    }

    private static func defaultCacheDirectory(fileManager: FileManager) -> URL? {
        try? fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("FridgeFit", isDirectory: true)
    }

    /// - Note: `uid` is accepted to satisfy the protocol and is not used to
    ///   select what is removed, because none of this state records an owner.
    ///   That asymmetry is the subject of the caveat in this type's
    ///   documentation, and is why it is a separate conformer rather than
    ///   being folded into the owner-scoped local deleter.
    func deleteAllData(ownedBy uid: String) async throws {
        guard !uid.isEmpty else {
            throw DeleteAccountError.localDataDeletionFailed("no account id")
        }

        for key in Self.preferenceKeys {
            defaults.removeObject(forKey: key)
        }

        guard let cacheDirectory else { return }

        for name in Self.cacheFileNames {
            let url = cacheDirectory.appendingPathComponent(name, isDirectory: false)
            do {
                try fileManager.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                // Already absent. Idempotent by contract, so this is success.
            } catch let error as NSError where error.domain == NSCocoaErrorDomain
                && error.code == NSFileNoSuchFileError {
                // Same case, reported through the older error shape.
            } catch {
                logger.error(
                    "Could not remove \(name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                throw DeleteAccountError.localDataDeletionFailed(error.localizedDescription)
            }
        }
    }
}
