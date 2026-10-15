import XCTest
import FirebaseFirestore
@testable import FridgeFit

// round trips for the dictionaries we send to Firestore. no live Firebase needed,
// same idea as FirestorePantryRepositoryMappingTests.
@MainActor
final class FundsFirestoreMappingTests: XCTestCase {

    func test_budget_roundTrips() throws {
        let budget = FoodBudget(limit: Money(Decimal(string: "120.50")!, .aud), cadence: .fortnightly, startDate: TestDates.anchor)

        let decoded = try XCTUnwrap(FundsFirestoreMapping.decodeBudget(FundsFirestoreMapping.encode(budget)))

        XCTAssertEqual(decoded, budget)
    }

    func test_money_isStoredAsAString_soCentsDontDrift() {
        let spend = GrocerySpend(amount: Money(Decimal(string: "4.45")!, .aud), spentOn: TestDates.anchor)

        let data = FundsFirestoreMapping.encode(spend)

        XCTAssertEqual(data["amount"] as? String, "4.45")
        XCTAssertEqual(data["currency"] as? String, "AUD")
    }

    func test_spend_roundTrips_includingOptionalFields() throws {
        let spend = GrocerySpend(amount: Money(35, .aud), spentOn: TestDates.day(1), store: "Coles",
                                 purchasedItemIDs: [PantryItemID("a"), PantryItemID("b")], note: "weekly shop")

        let decoded = try XCTUnwrap(FundsFirestoreMapping.decodeSpend(id: spend.id.uuidString,
                                                                      data: FundsFirestoreMapping.encode(spend)))

        XCTAssertEqual(decoded, spend)
    }

    func test_spend_withoutStoreOrNote_leavesThoseFieldsOut() {
        let data = FundsFirestoreMapping.encode(GrocerySpend(amount: Money(5, .aud), spentOn: TestDates.anchor))

        XCTAssertNil(data["store"])
        XCTAssertNil(data["note"])
    }

    func test_waste_roundTrips() throws {
        let waste = WastedFoodCost(pantryItemID: PantryItemID("milk"), quantityDiscarded: 0.5,
                                   lostAmount: Money(Decimal(string: "2.25")!, .aud),
                                   discardedOn: TestDates.day(2), reason: .expired)

        let decoded = try XCTUnwrap(FundsFirestoreMapping.decodeWaste(id: waste.id.uuidString,
                                                                      data: FundsFirestoreMapping.encode(waste)))

        XCTAssertEqual(decoded, waste)
    }

    func test_priceInfo_roundTrips() {
        let info = ItemPriceInfo(pantryItemID: PantryItemID("eggs"), unitCost: Money(Decimal(string: "0.45")!, .aud),
                                 expiryDate: TestDates.day(5))

        let decoded = FundsFirestoreMapping.decodePriceInfo(id: "eggs", data: FundsFirestoreMapping.encode(info))

        XCTAssertEqual(decoded, info)
    }

    func test_priceInfo_withNoExpiry_sendsNull_soItClearsOnTheServer() {
        let data = FundsFirestoreMapping.encode(ItemPriceInfo(pantryItemID: PantryItemID("rice"), unitCost: Money(3, .aud)))

        XCTAssertTrue(data["expiryDate"] is NSNull)
        XCTAssertNil(FundsFirestoreMapping.decodePriceInfo(id: "rice", data: data)?.expiryDate)
    }

    func test_datesComingBackAsTimestamps_areReadFine() throws {
        var data = FundsFirestoreMapping.encode(GrocerySpend(amount: Money(5, .aud), spentOn: TestDates.anchor))
        // this is what Firestore actually hands back
        data["spentOn"] = Timestamp(date: TestDates.anchor)

        let decoded = try XCTUnwrap(FundsFirestoreMapping.decodeSpend(id: UUID().uuidString, data: data))

        XCTAssertEqual(decoded.spentOn.timeIntervalSince1970, TestDates.anchor.timeIntervalSince1970, accuracy: 0.001)
    }

    func test_brokenDocuments_areSkipped_notCrashed() {
        XCTAssertNil(FundsFirestoreMapping.decodeSpend(id: "not-a-uuid", data: [:]))
        XCTAssertNil(FundsFirestoreMapping.decodeSpend(id: UUID().uuidString, data: ["amount": "abc", "currency": "AUD"]))
        XCTAssertNil(FundsFirestoreMapping.decodeBudget(["limitAmount": "100", "currency": "XYZ"]))
    }
}
