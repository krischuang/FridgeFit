//
//  FirestorePantryRepository.swift
//  FridgeFit
//

import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Firestore-backed implementation of `PantryRepository`.
///
/// Every pantry is scoped to the signed-in Firebase user, stored at
/// `users/{uid}/pantry/{pantryItemId}`. `userIDProvider` defaults to the
/// live `Auth.auth().currentUser?.uid` but is injectable so this type could
/// be pointed at a fake UID in tests without needing a live Firebase
/// project - the encode/decode logic is what's actually unit tested,
/// though (see `FirestorePantryRepositoryMappingTests`).
final class FirestorePantryRepository: PantryRepository {
    private let firestore: Firestore
    private let userIDProvider: () -> String?

    init(
        firestore: Firestore = Firestore.firestore(),
        userIDProvider: @escaping () -> String? = { Auth.auth().currentUser?.uid }
    ) {
        self.firestore = firestore
        self.userIDProvider = userIDProvider
    }

    /// - Throws: `PantryRepositoryError.notAuthenticated` if there's no
    ///   signed-in user - never falls back to a global/unscoped location.
    private func pantryCollection() throws -> CollectionReference {
        guard let uid = userIDProvider(), !uid.isEmpty else {
            throw PantryRepositoryError.notAuthenticated
        }
        return firestore.collection("users").document(uid).collection("pantry")
    }

    func fetchAll() async throws -> [PantryItem] {
        let snapshot = try await pantryCollection()
            .order(by: "ingredientName")
            .getDocuments()
        return snapshot.documents.compactMap { Self.decode(id: $0.documentID, data: $0.data()) }
    }

    func add(_ item: PantryItem) async throws {
        let document = try pantryCollection().document(item.id.uuidString)
        try await document.setData(Self.encodeForCreate(item))
    }

    func update(_ item: PantryItem) async throws {
        let document = try pantryCollection().document(item.id.uuidString)
        guard try await document.getDocument().exists else {
            throw UpdatePantryItemError.itemNotFound
        }
        try await document.updateData(Self.encodeForUpdate(item))
    }

    func remove(id: UUID) async throws {
        let document = try pantryCollection().document(id.uuidString)
        guard try await document.getDocument().exists else {
            throw RemovePantryItemError.pantryItemNotFound
        }
        try await document.delete()
    }
}

// MARK: - Encoding / decoding
//
// Pulled out as pure static functions (no Firestore instance needed) so
// the field mapping can be unit tested without a live Firebase project.

extension FirestorePantryRepository {
    static func encodeForCreate(_ item: PantryItem) -> [String: Any] {
        var data: [String: Any] = [
            "ingredientName": item.ingredient.name,
            "ingredientCategory": item.ingredient.category.rawValue,
            "quantity": item.quantity,
            "unit": item.unit.rawValue,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        // Kitchen fields are written only when the user actually set one.
        // An absent key is how "not tracked" is stored, and it is the same
        // state every pre-existing document is already in - so a document
        // written by this app and one written before these fields existed
        // decode identically.
        for (key, value) in kitchenFields(of: item) {
            data[key] = value
        }
        return data
    }

    /// Deliberately omits `createdAt` - including it here would reset the
    /// original creation time to "now" on every edit.
    ///
    /// Kitchen fields the user has cleared are sent as `FieldValue.delete()`
    /// rather than left out: `updateData` ignores absent keys, so omitting a
    /// now-`nil` expiry date would silently keep the old one and the item
    /// would go back to claiming it expires on a date the user just removed.
    static func encodeForUpdate(_ item: PantryItem) -> [String: Any] {
        var data: [String: Any] = [
            "ingredientName": item.ingredient.name,
            "ingredientCategory": item.ingredient.category.rawValue,
            "quantity": item.quantity,
            "unit": item.unit.rawValue,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        let present = kitchenFields(of: item)
        for key in kitchenFieldKeys {
            data[key] = present[key] ?? FieldValue.delete()
        }
        return data
    }

    /// Every key the kitchen fields can occupy, so `encodeForUpdate` can
    /// clear the ones that are absent without listing them twice.
    static let kitchenFieldKeys = [
        "expiryDate",
        "storageLocation",
        "openedState",
        "lowStockThreshold",
        "packageUnit",
        "packageLevel",
    ]

    /// The kitchen fields that have a value on `item`, keyed as stored.
    private static func kitchenFields(of item: PantryItem) -> [String: Any] {
        var data: [String: Any] = [:]
        if let expiryDate = item.expiryDate {
            data["expiryDate"] = Timestamp(date: expiryDate)
        }
        if let storageLocation = item.storageLocation {
            data["storageLocation"] = storageLocation.rawValue
        }
        if let openedState = item.openedState {
            data["openedState"] = openedState.rawValue
        }
        if let lowStockThreshold = item.lowStockThreshold {
            data["lowStockThreshold"] = lowStockThreshold
        }
        if let packageUnit = item.packageUnit {
            data["packageUnit"] = packageUnit.rawValue
        }
        if let packageLevel = item.packageLevel {
            data["packageLevel"] = packageLevel.rawValue
        }
        return data
    }

    /// Decodes one document.
    ///
    /// The four original fields stay required - a document without a name or
    /// an amount is not a pantry item and is skipped, exactly as before. The
    /// kitchen fields are all optional reads, and an unrecognised stored
    /// value (a storage location this build doesn't know) decodes as `nil`
    /// rather than discarding the whole item: losing a fridge/pantry label
    /// is recoverable, losing the user's food is not.
    static func decode(id: String, data: [String: Any]) -> PantryItem? {
        guard
            let uuid = UUID(uuidString: id),
            let name = data["ingredientName"] as? String,
            let categoryRaw = data["ingredientCategory"] as? String,
            let category = IngredientCategory(rawValue: categoryRaw),
            let quantity = data["quantity"] as? Double,
            let unitRaw = data["unit"] as? String,
            let unit = MeasurementUnit(rawValue: unitRaw)
        else {
            return nil
        }
        return PantryItem(
            id: uuid,
            ingredient: Ingredient(name: name, category: category),
            quantity: quantity,
            unit: unit,
            expiryDate: (data["expiryDate"] as? Timestamp)?.dateValue(),
            storageLocation: (data["storageLocation"] as? String).flatMap(StorageLocation.init(rawValue:)),
            openedState: (data["openedState"] as? String).flatMap(OpenedState.init(rawValue:)),
            lowStockThreshold: data["lowStockThreshold"] as? Double,
            packageUnit: (data["packageUnit"] as? String).flatMap(PackageUnit.init(rawValue:)),
            packageLevel: (data["packageLevel"] as? Double).flatMap(PackageLevel.init(rawValue:))
        )
    }
}
