//
//  FirestoreInventoryMappingTests.swift
//  FridgeFitTests
//
//  Exercises the pure encode/decode helpers for the kitchen fields on
//  `FirestorePantryRepository` and for `FirestoreInventoryEventRepository` -
//  no live Firestore project involved, per the "don't depend on live
//  Firebase in unit tests" rule.
//
//  The backward-compatibility tests here are the ones that matter most: they
//  pin the behaviour that an existing user's pantry documents, written before
//  any of these fields existed, still decode and still behave as they did.
//

import FirebaseFirestore
import XCTest
@testable import FridgeFit

final class FirestoreInventoryMappingTests: XCTestCase {
    private let sampleID = UUID()

    private func legacyData() -> [String: Any] {
        [
            "ingredientName": "Milk",
            "ingredientCategory": IngredientCategory.dairy.rawValue,
            "quantity": 1.0,
            "unit": MeasurementUnit.liters.rawValue,
        ]
    }

    // MARK: - Backward compatibility

    func test_decode_succeeds_forADocumentWrittenBeforeTheKitchenFieldsExisted() {
        let item = FirestorePantryRepository.decode(id: sampleID.uuidString, data: legacyData())

        XCTAssertNotNil(item)
        XCTAssertEqual(item?.name, "Milk")
        XCTAssertEqual(item?.quantity, 1)
        XCTAssertEqual(item?.unit, .liters)
        // Every kitchen field is absent, which is the correct reading of a
        // document that never had them.
        XCTAssertNil(item?.expiryDate)
        XCTAssertNil(item?.storageLocation)
        XCTAssertNil(item?.openedState)
        XCTAssertNil(item?.lowStockThreshold)
        XCTAssertNil(item?.packageUnit)
        XCTAssertNil(item?.packageLevel)
    }

    func test_decode_stillRequiresTheOriginalFourFields() {
        // The kitchen fields are additive; they must not make a malformed
        // document decodable.
        for missing in ["ingredientName", "ingredientCategory", "quantity", "unit"] {
            var data = legacyData()
            data.removeValue(forKey: missing)
            XCTAssertNil(
                FirestorePantryRepository.decode(id: sampleID.uuidString, data: data),
                "a document missing \(missing) should not decode"
            )
        }
    }

    func test_decode_keepsTheItem_whenAKitchenFieldIsUnrecognised() {
        // Losing a fridge/pantry label is recoverable; losing the user's
        // food is not. An unknown value reads as absent rather than
        // discarding the whole row.
        var data = legacyData()
        data["storageLocation"] = "spaceship"
        data["openedState"] = "ajar"
        data["packageUnit"] = "barrel"
        data["packageLevel"] = 0.42

        let item = FirestorePantryRepository.decode(id: sampleID.uuidString, data: data)

        XCTAssertEqual(item?.name, "Milk")
        XCTAssertNil(item?.storageLocation)
        XCTAssertNil(item?.openedState)
        XCTAssertNil(item?.packageUnit)
        XCTAssertNil(item?.packageLevel)
        XCTAssertEqual(item?.storage, .pantry)
    }

    func test_encodeForCreate_omitsKitchenFieldsThatAreNotSet() {
        // So an item added from the Pantry tab, the receipt scanner or the
        // camera is stored in exactly the shape it was before.
        let item = PantryItem(
            id: sampleID,
            ingredient: Ingredient(name: "Rice", category: .grain),
            quantity: 500,
            unit: .grams
        )

        let data = FirestorePantryRepository.encodeForCreate(item)

        for key in FirestorePantryRepository.kitchenFieldKeys {
            XCTAssertNil(data[key], "\(key) should not be written when it has no value")
        }
        XCTAssertEqual(data["quantity"] as? Double, 500)
        XCTAssertNotNil(data["createdAt"])
    }

    // MARK: - Kitchen fields

    func test_encodeForCreate_writesEveryKitchenFieldThatIsSet() {
        let expiry = Date(timeIntervalSince1970: 1_780_000_000)
        let item = PantryItem(
            id: sampleID,
            ingredient: Ingredient(name: "Milk", category: .dairy),
            quantity: 0.5,
            unit: .pieces,
            expiryDate: expiry,
            storageLocation: .fridge,
            openedState: .opened,
            lowStockThreshold: 0.25,
            packageUnit: .bottle,
            packageLevel: .half
        )

        let data = FirestorePantryRepository.encodeForCreate(item)

        XCTAssertEqual((data["expiryDate"] as? Timestamp)?.dateValue(), expiry)
        XCTAssertEqual(data["storageLocation"] as? String, StorageLocation.fridge.rawValue)
        XCTAssertEqual(data["openedState"] as? String, OpenedState.opened.rawValue)
        XCTAssertEqual(data["lowStockThreshold"] as? Double, 0.25)
        XCTAssertEqual(data["packageUnit"] as? String, PackageUnit.bottle.rawValue)
        XCTAssertEqual(data["packageLevel"] as? Double, PackageLevel.half.rawValue)
    }

    func test_decode_isInverseOf_encodeForCreate_includingTheKitchenFields() {
        let expiry = Date(timeIntervalSince1970: 1_780_000_000)
        let item = PantryItem(
            id: sampleID,
            ingredient: Ingredient(name: "Milk", category: .dairy),
            quantity: 0.5,
            unit: .pieces,
            expiryDate: expiry,
            storageLocation: .fridge,
            openedState: .opened,
            lowStockThreshold: 0.25,
            packageUnit: .bottle,
            packageLevel: .half
        )

        var data = FirestorePantryRepository.encodeForCreate(item)
        data.removeValue(forKey: "createdAt")
        data.removeValue(forKey: "updatedAt")
        let decoded = FirestorePantryRepository.decode(id: item.id.uuidString, data: data)

        XCTAssertEqual(decoded?.expiryDate, expiry)
        XCTAssertEqual(decoded?.storageLocation, .fridge)
        XCTAssertEqual(decoded?.openedState, .opened)
        XCTAssertEqual(decoded?.lowStockThreshold, 0.25)
        XCTAssertEqual(decoded?.packageUnit, .bottle)
        XCTAssertEqual(decoded?.packageLevel, .half)
        // And the kitchen UI's reading survives the round trip.
        XCTAssertEqual(decoded?.inventoryQuantity, .package(count: 1, unit: .bottle, level: .half))
    }

    func test_encodeForUpdate_deletesKitchenFieldsTheUserCleared() {
        // `updateData` ignores absent keys, so omitting a now-nil expiry
        // date would silently keep the old one - the item would go back to
        // claiming a date the user just removed.
        let cleared = PantryItem(
            id: sampleID,
            ingredient: Ingredient(name: "Milk", category: .dairy),
            quantity: 1,
            unit: .liters
        )

        let data = FirestorePantryRepository.encodeForUpdate(cleared)

        for key in FirestorePantryRepository.kitchenFieldKeys {
            XCTAssertTrue(
                data[key] is FieldValue,
                "\(key) should be sent as a delete when it has no value"
            )
        }
    }

    func test_encodeForUpdate_stillOmitsCreatedAt() {
        let item = PantryItem(
            id: sampleID,
            ingredient: Ingredient(name: "Milk", category: .dairy),
            quantity: 1,
            unit: .liters,
            storageLocation: .fridge
        )

        let data = FirestorePantryRepository.encodeForUpdate(item)

        XCTAssertNil(data["createdAt"])
        XCTAssertNotNil(data["updatedAt"])
        XCTAssertEqual(data["storageLocation"] as? String, StorageLocation.fridge.rawValue)
    }

    // MARK: - Inventory events

    func test_event_roundTripsThroughEncodeAndDecode() {
        let event = InventoryEvent(
            pantryItemID: UUID(),
            itemName: "Milk",
            kind: .used,
            note: "Used 200 ml",
            date: Date(timeIntervalSince1970: 1_780_000_000)
        )

        let data = FirestoreInventoryEventRepository.encode(event)
        let decoded = FirestoreInventoryEventRepository.decode(id: event.id.uuidString, data: data)

        XCTAssertEqual(decoded, event)
    }

    func test_event_omitsAnAbsentNoteRatherThanStoringAnEmptyString() {
        // Absent and empty are different facts, and the activity list shows
        // them differently.
        let event = InventoryEvent(pantryItemID: UUID(), itemName: "Milk", kind: .finished)

        let data = FirestoreInventoryEventRepository.encode(event)

        XCTAssertNil(data["note"])
        XCTAssertNil(FirestoreInventoryEventRepository.decode(id: event.id.uuidString, data: data)?.note)
    }

    func test_event_decodeFails_whenRequiredFieldsAreMissingOrUnrecognised() {
        let valid = FirestoreInventoryEventRepository.encode(
            InventoryEvent(pantryItemID: UUID(), itemName: "Milk", kind: .used, note: "Used 1")
        )

        for missing in ["pantryItemId", "itemName", "kind"] {
            var data = valid
            data.removeValue(forKey: missing)
            XCTAssertNil(
                FirestoreInventoryEventRepository.decode(id: UUID().uuidString, data: data),
                "an event missing \(missing) should not decode"
            )
        }

        var unknownKind = valid
        unknownKind["kind"] = "teleported"
        XCTAssertNil(FirestoreInventoryEventRepository.decode(id: UUID().uuidString, data: unknownKind))

        XCTAssertNil(FirestoreInventoryEventRepository.decode(id: "not-a-uuid", data: valid))
    }

    func test_event_fallsBackToNow_whenTheStoredDateIsUnreadable() {
        // The list is ordered by date and shows it, so a missing date must
        // not drop the event - it gets a usable one instead.
        var data = FirestoreInventoryEventRepository.encode(
            InventoryEvent(pantryItemID: UUID(), itemName: "Milk", kind: .added)
        )
        data.removeValue(forKey: "date")

        let decoded = FirestoreInventoryEventRepository.decode(id: UUID().uuidString, data: data)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.date.timeIntervalSinceNow ?? -999, 0, accuracy: 5)
    }
}
