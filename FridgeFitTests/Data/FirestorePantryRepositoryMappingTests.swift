//
//  FirestorePantryRepositoryMappingTests.swift
//  FridgeFitTests
//
//  Exercises FirestorePantryRepository's pure encode/decode helpers only -
//  no live Firestore project involved, per the "don't depend on live
//  Firebase in unit tests" rule.
//

import XCTest
@testable import FridgeFit

final class FirestorePantryRepositoryMappingTests: XCTestCase {
    private let sampleID = UUID()

    func test_decode_succeeds_withCompleteValidData() {
        let data: [String: Any] = [
            "ingredientName": "Chicken Breast",
            "ingredientCategory": IngredientCategory.meat.rawValue,
            "quantity": 500.0,
            "unit": MeasurementUnit.grams.rawValue,
        ]

        let item = FirestorePantryRepository.decode(id: sampleID.uuidString, data: data)

        XCTAssertEqual(item?.id, sampleID)
        XCTAssertEqual(item?.name, "Chicken Breast")
        XCTAssertEqual(item?.ingredient.category, .meat)
        XCTAssertEqual(item?.quantity, 500)
        XCTAssertEqual(item?.unit, .grams)
    }

    func test_decode_fails_whenDocumentIDIsNotAUUID() {
        let data: [String: Any] = [
            "ingredientName": "Chicken Breast",
            "ingredientCategory": IngredientCategory.meat.rawValue,
            "quantity": 500.0,
            "unit": MeasurementUnit.grams.rawValue,
        ]

        XCTAssertNil(FirestorePantryRepository.decode(id: "not-a-uuid", data: data))
    }

    func test_decode_fails_whenCategoryIsUnrecognised() {
        let data: [String: Any] = [
            "ingredientName": "Chicken Breast",
            "ingredientCategory": "Not A Real Category",
            "quantity": 500.0,
            "unit": MeasurementUnit.grams.rawValue,
        ]

        XCTAssertNil(FirestorePantryRepository.decode(id: sampleID.uuidString, data: data))
    }

    func test_decode_fails_whenUnitIsUnrecognised() {
        let data: [String: Any] = [
            "ingredientName": "Chicken Breast",
            "ingredientCategory": IngredientCategory.meat.rawValue,
            "quantity": 500.0,
            "unit": "gallons",
        ]

        XCTAssertNil(FirestorePantryRepository.decode(id: sampleID.uuidString, data: data))
    }

    func test_decode_fails_whenRequiredFieldIsMissing() {
        let data: [String: Any] = [
            "ingredientCategory": IngredientCategory.meat.rawValue,
            "quantity": 500.0,
            "unit": MeasurementUnit.grams.rawValue,
        ]

        XCTAssertNil(FirestorePantryRepository.decode(id: sampleID.uuidString, data: data))
    }

    func test_encodeForCreate_includesAllFieldsAndBothTimestamps() {
        let item = PantryItem(id: sampleID, ingredient: Ingredient(name: "Rice", category: .grain), quantity: 500, unit: .grams)

        let data = FirestorePantryRepository.encodeForCreate(item)

        XCTAssertEqual(data["ingredientName"] as? String, "Rice")
        XCTAssertEqual(data["ingredientCategory"] as? String, IngredientCategory.grain.rawValue)
        XCTAssertEqual(data["quantity"] as? Double, 500)
        XCTAssertEqual(data["unit"] as? String, MeasurementUnit.grams.rawValue)
        XCTAssertNotNil(data["createdAt"])
        XCTAssertNotNil(data["updatedAt"])
    }

    func test_encodeForUpdate_omitsCreatedAt_soItIsNeverOverwritten() {
        let item = PantryItem(id: sampleID, ingredient: Ingredient(name: "Rice", category: .grain), quantity: 700, unit: .grams)

        let data = FirestorePantryRepository.encodeForUpdate(item)

        XCTAssertEqual(data["quantity"] as? Double, 700)
        XCTAssertNotNil(data["updatedAt"])
        XCTAssertNil(data["createdAt"])
    }

    // Round-trips decode(encodeForCreate(item)) to guard against the two
    // sides of the mapping silently drifting apart.
    func test_decode_isInverseOf_encodeForCreate_forNonTimestampFields() {
        let item = PantryItem(id: sampleID, ingredient: Ingredient(name: "Greek Yogurt", category: .dairy), quantity: 2, unit: .cups)

        var data = FirestorePantryRepository.encodeForCreate(item)
        data.removeValue(forKey: "createdAt")
        data.removeValue(forKey: "updatedAt")
        let decoded = FirestorePantryRepository.decode(id: item.id.uuidString, data: data)

        XCTAssertEqual(decoded?.id, item.id)
        XCTAssertEqual(decoded?.name, item.name)
        XCTAssertEqual(decoded?.ingredient.category, item.ingredient.category)
        XCTAssertEqual(decoded?.quantity, item.quantity)
        XCTAssertEqual(decoded?.unit, item.unit)
    }
}
