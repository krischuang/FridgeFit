//
//  FirestoreInventoryEventRepository.swift
//  FridgeFit
//

import FirebaseAuth
import FirebaseFirestore
import Foundation

/// Firestore-backed implementation of `InventoryEventRepository`.
///
/// Stored at `users/{uid}/inventoryEvents/{eventId}`, under the same
/// `users/{uid}` subtree and therefore the same security boundary as the
/// pantry - see `firestore.rules`. Scoping is resolved per call from
/// `Auth.auth().currentUser?.uid`, exactly as `FirestorePantryRepository`
/// does, so a signed-out user cannot read or write anything.
final class FirestoreInventoryEventRepository: InventoryEventRepository {
    private let firestore: Firestore
    private let userIDProvider: () -> String?

    init(
        firestore: Firestore = Firestore.firestore(),
        userIDProvider: @escaping () -> String? = { Auth.auth().currentUser?.uid }
    ) {
        self.firestore = firestore
        self.userIDProvider = userIDProvider
    }

    /// - Throws: `PantryRepositoryError.notAuthenticated` when there is no
    ///   signed-in user. Reuses the pantry's error rather than inventing a
    ///   second one - it is the same condition with the same message.
    private func eventCollection() throws -> CollectionReference {
        guard let uid = userIDProvider(), !uid.isEmpty else {
            throw PantryRepositoryError.notAuthenticated
        }
        return firestore.collection("users").document(uid).collection("inventoryEvents")
    }

    func fetchAll(limit: Int) async throws -> [InventoryEvent] {
        let snapshot = try await eventCollection()
            .order(by: "date", descending: true)
            .limit(to: limit)
            .getDocuments()
        return snapshot.documents.compactMap { Self.decode(id: $0.documentID, data: $0.data()) }
    }

    func append(_ event: InventoryEvent) async throws {
        let document = try eventCollection().document(event.id.uuidString)
        try await document.setData(Self.encode(event))
    }

    func remove(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        let collection = try eventCollection()
        // One batch so an undo either removes every event it created or
        // none of them - a half-undone action would leave history claiming
        // something happened that was rolled back.
        let batch = firestore.batch()
        for id in ids {
            batch.deleteDocument(collection.document(id.uuidString))
        }
        try await batch.commit()
    }
}

// MARK: - Encoding / decoding
//
// Pure static functions, no Firestore instance needed, so the field mapping
// is unit testable without a live project - same approach as
// `FirestorePantryRepository`.

extension FirestoreInventoryEventRepository {
    static func encode(_ event: InventoryEvent) -> [String: Any] {
        var data: [String: Any] = [
            "pantryItemId": event.pantryItemID.uuidString,
            "itemName": event.itemName,
            "kind": event.kind.rawValue,
            "date": Timestamp(date: event.date),
        ]
        // Written only when there is one: an absent key and a stored empty
        // string are different facts, and the activity list distinguishes
        // them.
        if let note = event.note {
            data["note"] = note
        }
        return data
    }

    static func decode(id: String, data: [String: Any]) -> InventoryEvent? {
        guard
            let uuid = UUID(uuidString: id),
            let itemIDRaw = data["pantryItemId"] as? String,
            let pantryItemID = UUID(uuidString: itemIDRaw),
            let itemName = data["itemName"] as? String,
            let kindRaw = data["kind"] as? String,
            let kind = InventoryEventKind(rawValue: kindRaw)
        else {
            return nil
        }
        // `serverTimestamp()` is deliberately not used for `date`: the
        // activity list is ordered by it and shows it to the user, so a
        // pending write that reads back as `nil` for a moment would appear
        // out of order. The client clock is good enough for a history list
        // and is always present.
        let date = (data["date"] as? Timestamp)?.dateValue() ?? Date()
        return InventoryEvent(
            id: uuid,
            pantryItemID: pantryItemID,
            itemName: itemName,
            kind: kind,
            note: data["note"] as? String,
            date: date
        )
    }
}
