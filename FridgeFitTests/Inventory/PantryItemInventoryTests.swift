//
//  PantryItemInventoryTests.swift
//  FridgeFitTests
//
//  The bridge between the pantry's stored amount (a Double plus a unit, read
//  by recipes and substitutions) and the kitchen UI's richer `Quantity`.
//  These are the tests that guard backward compatibility at the model level:
//  an item with none of the kitchen fields set is exactly what every
//  pre-existing Firestore document decodes to.
//

import XCTest
@testable import FridgeFit

final class PantryItemInventoryTests: XCTestCase {

    private func item(
        quantity: Double,
        unit: MeasurementUnit,
        packageUnit: PackageUnit? = nil,
        packageLevel: PackageLevel? = nil,
        expiryDate: Date? = nil,
        storageLocation: StorageLocation? = nil,
        openedState: OpenedState? = nil,
        lowStockThreshold: Double? = nil
    ) -> PantryItem {
        PantryItem(
            ingredient: Ingredient(name: "Test", category: .other),
            quantity: quantity,
            unit: unit,
            expiryDate: expiryDate,
            storageLocation: storageLocation,
            openedState: openedState,
            lowStockThreshold: lowStockThreshold,
            packageUnit: packageUnit,
            packageLevel: packageLevel
        )
    }

    // MARK: - A legacy item behaves exactly as it did before

    func test_legacyItem_hasNoKitchenFieldsSet() {
        // This is the shape of every pantry item written before the kitchen
        // UI existed: four fields, nothing else.
        let legacy = PantryItem(
            ingredient: Ingredient(name: "Rice", category: .grain),
            quantity: 500,
            unit: .grams
        )

        XCTAssertNil(legacy.expiryDate)
        XCTAssertNil(legacy.storageLocation)
        XCTAssertNil(legacy.openedState)
        XCTAssertNil(legacy.lowStockThreshold)
        XCTAssertNil(legacy.packageUnit)
        XCTAssertNil(legacy.packageLevel)
        // And the fields main already relied on are untouched.
        XCTAssertEqual(legacy.quantity, 500)
        XCTAssertEqual(legacy.unit, .grams)
        XCTAssertEqual(legacy.formattedQuantity, "500 g")
    }

    func test_legacyItem_showsInThePantryZone_ratherThanDisappearing() {
        // `storage` resolves the absence so the kitchen screen's three zones
        // still account for every item. Dropping unlocated items would hide
        // the user's food.
        let legacy = item(quantity: 1, unit: .pieces)
        XCTAssertEqual(legacy.storage, .pantry)
    }

    func test_legacyItem_isNotTreatedAsOpenedOrUnopened() {
        XCTAssertEqual(item(quantity: 1, unit: .pieces).opened, .notApplicable)
    }

    func test_legacyItem_isNeverFlaggedLowStock() {
        // Nothing is inferred from the amount alone: two eggs is low for an
        // omelette and plenty for a cake.
        XCTAssertFalse(item(quantity: 1, unit: .pieces).isLowStock)
        XCTAssertFalse(item(quantity: 0, unit: .grams).isLowStock)
    }

    func test_legacyItem_hasNoExpiryState() {
        XCTAssertNil(item(quantity: 1, unit: .pieces).expiryState)
    }

    // MARK: - Deriving a Quantity from the stored amount

    func test_inventoryQuantity_readsWholePiecesAsACount() {
        XCTAssertEqual(item(quantity: 6, unit: .pieces).inventoryQuantity, .count(6))
    }

    func test_inventoryQuantity_readsFractionalPiecesAsAMeasure() {
        // 1.5 pieces cannot be a count, so it stays a measure rather than
        // rounding the user's data.
        XCTAssertEqual(
            item(quantity: 1.5, unit: .pieces).inventoryQuantity,
            .measure(1.5, unit: .pieces)
        )
    }

    func test_inventoryQuantity_readsWeightsAndVolumesAsMeasures() {
        XCTAssertEqual(item(quantity: 500, unit: .grams).inventoryQuantity, .measure(500, unit: .grams))
        XCTAssertEqual(item(quantity: 1, unit: .liters).inventoryQuantity, .measure(1, unit: .liters))
    }

    func test_inventoryQuantity_readsAPackageWhenThePackageFieldsAreSet() {
        let halfBottle = item(quantity: 0.5, unit: .pieces, packageUnit: .bottle, packageLevel: .half)
        XCTAssertEqual(halfBottle.inventoryQuantity, .package(count: 1, unit: .bottle, level: .half))
    }

    func test_inventoryQuantity_readsMultiplePackages() {
        let twoFullPacks = item(quantity: 2, unit: .pieces, packageUnit: .pack, packageLevel: .full)
        XCTAssertEqual(twoFullPacks.inventoryQuantity, .package(count: 2, unit: .pack, level: .full))
    }

    func test_inventoryQuantity_isReadableForAnyLegacyUnit() {
        // Including the recipe-only units, which the kitchen editor does not
        // offer but existing pantry items may already use.
        for unit in MeasurementUnit.allCases {
            let quantity = item(quantity: 2, unit: unit).inventoryQuantity
            XCTAssertEqual(quantity.normalizedAmount, 2, "\(unit) should read back its amount")
        }
    }

    // MARK: - Writing a Quantity back

    func test_setInventoryQuantity_writesThroughToTheCanonicalFields() {
        var subject = item(quantity: 0, unit: .pieces)

        subject.setInventoryQuantity(.measure(250, unit: .grams))

        // What recipes and substitutions read:
        XCTAssertEqual(subject.quantity, 250)
        XCTAssertEqual(subject.unit, .grams)
    }

    func test_setInventoryQuantity_storesThePackageReadingBesideTheAmount() {
        var subject = item(quantity: 0, unit: .pieces)

        subject.setInventoryQuantity(.package(count: 1, unit: .bottle, level: .half))

        // Truthful for recipe feasibility *and* for the kitchen UI.
        XCTAssertEqual(subject.quantity, 0.5)
        XCTAssertEqual(subject.unit, .pieces)
        XCTAssertEqual(subject.packageUnit, .bottle)
        XCTAssertEqual(subject.packageLevel, .half)
        XCTAssertEqual(subject.inventoryQuantity.displayText, "½ bottle")
    }

    func test_setInventoryQuantity_clearsThePackageReadingWhenMovingOffAPackage() {
        // Otherwise a jar edited into "500 g" would still read back as a
        // fraction of a jar.
        var subject = item(quantity: 0.5, unit: .pieces, packageUnit: .jar, packageLevel: .half)

        subject.setInventoryQuantity(.measure(500, unit: .grams))

        XCTAssertNil(subject.packageUnit)
        XCTAssertNil(subject.packageLevel)
        XCTAssertEqual(subject.inventoryQuantity, .measure(500, unit: .grams))
    }

    func test_setInventoryQuantity_roundTripsEveryQuantityKind() {
        let cases: [Quantity] = [
            .count(6),
            .measure(1.5, unit: .kilograms),
            .package(count: 2, unit: .tub, level: .threeQuarters),
        ]

        for quantity in cases {
            var subject = item(quantity: 0, unit: .pieces)
            subject.setInventoryQuantity(quantity)
            XCTAssertEqual(subject.inventoryQuantity, quantity, "\(quantity) should survive a round trip")
        }
    }

    // MARK: - Low stock and expiry

    func test_isLowStock_whenTheAmountReachesTheUsersThreshold() {
        XCTAssertTrue(item(quantity: 2, unit: .pieces, lowStockThreshold: 2).isLowStock)
        XCTAssertTrue(item(quantity: 1, unit: .pieces, lowStockThreshold: 2).isLowStock)
        XCTAssertFalse(item(quantity: 3, unit: .pieces, lowStockThreshold: 2).isLowStock)
    }

    func test_expiryState_isDerivedRatherThanStored() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        XCTAssertEqual(item(quantity: 1, unit: .pieces, expiryDate: tomorrow).expiryState?.urgency, .tomorrow)
    }

    // MARK: - Codable

    func test_pantryItem_decodesLegacyJSON_withNoKitchenFields() throws {
        // Guards the Codable path (previews, any cached JSON) the same way
        // the Firestore mapping tests guard the stored path.
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "ingredient": { "id": "\(UUID().uuidString)", "name": "Milk", "category": "Dairy" },
          "quantity": 1,
          "unit": "L"
        }
        """

        let decoded = try JSONDecoder().decode(PantryItem.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.name, "Milk")
        XCTAssertEqual(decoded.quantity, 1)
        XCTAssertEqual(decoded.unit, .liters)
        XCTAssertNil(decoded.expiryDate)
        XCTAssertNil(decoded.storageLocation)
        XCTAssertEqual(decoded.storage, .pantry)
    }
}
