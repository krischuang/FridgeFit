//
//  FirestoreSavedRecipeRepository.swift
//  FridgeFit
//

import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Firestore-backed `SavedRecipeRepository`, scoped per user at
/// `users/{uid}/savedRecipes/{recipeId}` (see firestore.rules).
///
/// The recipe is stored as one JSON string (`recipeJSON`) rather than a
/// field-per-property map: it's only ever read back whole, and it keeps the
/// mapping to `Recipe`'s existing `Codable` conformance instead of a second
/// hand-written schema that could drift.
nonisolated final class FirestoreSavedRecipeRepository: SavedRecipeRepository {
    private let firestore: Firestore
    private let userIDProvider: () -> String?

    init(
        firestore: Firestore = Firestore.firestore(),
        userIDProvider: @escaping () -> String? = { Auth.auth().currentUser?.uid }
    ) {
        self.firestore = firestore
        self.userIDProvider = userIDProvider
    }

    private func collection() throws -> CollectionReference {
        guard let uid = userIDProvider(), !uid.isEmpty else {
            throw SaveOnlineRecipeError.notAuthenticated
        }
        return firestore.collection("users").document(uid).collection("savedRecipes")
    }

    func fetchAll() async throws -> [Recipe] {
        let snapshot = try await collection()
            .order(by: "savedAt", descending: true)
            .getDocuments()
        return snapshot.documents.compactMap { Self.decode(id: $0.documentID, data: $0.data()) }
    }

    func save(_ recipe: Recipe, sourceRecipeID: Int) async throws {
        let document = try collection().document(recipe.id.uuidString)
        try await document.setData(Self.encode(recipe, sourceRecipeID: sourceRecipeID))
    }

    func remove(id: UUID) async throws {
        try await collection().document(id.uuidString).delete()
    }
}

// MARK: - Encoding / decoding (pure, unit tested without Firebase)

nonisolated extension FirestoreSavedRecipeRepository {
    static func encode(_ recipe: Recipe, sourceRecipeID: Int) throws -> [String: Any] {
        let json = try JSONEncoder().encode(recipe)
        return [
            "title": recipe.title,
            "sourceRecipeID": sourceRecipeID,
            "recipeJSON": String(decoding: json, as: UTF8.self),
            "savedAt": FieldValue.serverTimestamp(),
        ]
    }

    /// `nil` for a malformed document, or one whose stored recipe doesn't
    /// belong to this document id - skipped rather than crashing the list.
    static func decode(id: String, data: [String: Any]) -> Recipe? {
        guard
            let uuid = UUID(uuidString: id),
            let json = data["recipeJSON"] as? String,
            let recipe = try? JSONDecoder().decode(Recipe.self, from: Data(json.utf8)),
            recipe.id == uuid
        else {
            return nil
        }
        return recipe
    }
}
