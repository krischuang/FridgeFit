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
        [
            "ingredientName": item.ingredient.name,
            "ingredientCategory": item.ingredient.category.rawValue,
            "quantity": item.quantity,
            "unit": item.unit.rawValue,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
    }

    /// Deliberately omits `createdAt` - including it here would reset the
    /// original creation time to "now" on every edit.
    static func encodeForUpdate(_ item: PantryItem) -> [String: Any] {
        [
            "ingredientName": item.ingredient.name,
            "ingredientCategory": item.ingredient.category.rawValue,
            "quantity": item.quantity,
            "unit": item.unit.rawValue,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
    }

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
        return PantryItem(id: uuid, ingredient: Ingredient(name: name, category: category), quantity: quantity, unit: unit)
    }
}
