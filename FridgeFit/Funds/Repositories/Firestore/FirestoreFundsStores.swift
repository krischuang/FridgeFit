//
//  FirestoreFundsStores.swift
//  FridgeFit
//

import FirebaseAuth
import FirebaseFirestore
import Foundation
import OSLog

// Firestore versions of BudgetStore / ItemPriceStore. the protocols are sync (that's
// how the FridgeFunds use cases were written), Firestore isn't - so each store keeps
// a local copy: load() fills it once, reads come straight from it, and every write
// updates the copy right away and then saves to Firestore in the background.
// Firestore queues writes itself when offline, so nothing gets lost that way.
//
// everything lives under the signed-in user, next to the pantry:
//   users/{uid}/fundsBudget/current
//   users/{uid}/fundsSpends/{spendId}
//   users/{uid}/fundsWaste/{wasteId}
//   users/{uid}/fundsItemPrices/{pantryItemId}
//   users/{uid}/fundsPriceBook/{encoded ingredient name}

private let logger = Logger(subsystem: "com.fridgefit.app", category: "FridgeFunds")

private func userDocument(_ firestore: Firestore, _ uid: () -> String?) throws -> DocumentReference {
    guard let uid = uid(), !uid.isEmpty else { throw PantryRepositoryError.notAuthenticated }
    return firestore.collection("users").document(uid)
}

private func logIfFailed(_ what: String) -> (Error?) -> Void {
    { error in
        if let error { logger.error("Saving \(what, privacy: .public) failed: \(error.localizedDescription, privacy: .public)") }
    }
}

final class FirestoreBudgetStore: BudgetStore {
    private let firestore: Firestore
    private let userIDProvider: () -> String?

    private var budget: FoodBudget?
    private var spends: [GrocerySpend] = []
    private var wasteCosts: [WastedFoodCost] = []

    init(
        firestore: Firestore = Firestore.firestore(),
        userIDProvider: @escaping () -> String? = { Auth.auth().currentUser?.uid }
    ) {
        self.firestore = firestore
        self.userIDProvider = userIDProvider
    }

    func load() async throws {
        let user = try userDocument(firestore, userIDProvider)
        let budgetSnapshot = try await user.collection("fundsBudget").document("current").getDocument()
        let spendDocs = try await user.collection("fundsSpends").getDocuments().documents
        let wasteDocs = try await user.collection("fundsWaste").getDocuments().documents

        budget = budgetSnapshot.data().flatMap(FundsFirestoreMapping.decodeBudget)
        spends = spendDocs.compactMap { FundsFirestoreMapping.decodeSpend(id: $0.documentID, data: $0.data()) }
        wasteCosts = wasteDocs.compactMap { FundsFirestoreMapping.decodeWaste(id: $0.documentID, data: $0.data()) }
    }

    func activeBudget() -> FoodBudget? { budget }

    func saveBudget(_ budget: FoodBudget) {
        self.budget = budget
        guard let user = try? userDocument(firestore, userIDProvider) else { return }
        user.collection("fundsBudget").document("current")
            .setData(FundsFirestoreMapping.encode(budget), completion: logIfFailed("budget"))
    }

    func allSpends() -> [GrocerySpend] { spends }

    func addSpend(_ spend: GrocerySpend) {
        spends.append(spend)
        guard let user = try? userDocument(firestore, userIDProvider) else { return }
        user.collection("fundsSpends").document(spend.id.uuidString)
            .setData(FundsFirestoreMapping.encode(spend), completion: logIfFailed("spend"))
    }

    func allWasteCosts() -> [WastedFoodCost] { wasteCosts }

    func addWasteCost(_ cost: WastedFoodCost) {
        wasteCosts.append(cost)
        guard let user = try? userDocument(firestore, userIDProvider) else { return }
        user.collection("fundsWaste").document(cost.id.uuidString)
            .setData(FundsFirestoreMapping.encode(cost), completion: logIfFailed("waste"))
    }

    func wasteAlreadyRecorded(for itemID: PantryItemID, on day: Date) -> Bool {
        wasteCosts.contains {
            $0.pantryItemID == itemID && Calendar.current.isDate($0.discardedOn, inSameDayAs: day)
        }
    }
}

final class FirestoreItemPriceStore: ItemPriceStore {
    private let firestore: Firestore
    private let userIDProvider: () -> String?
    private var byID: [PantryItemID: ItemPriceInfo] = [:]

    init(
        firestore: Firestore = Firestore.firestore(),
        userIDProvider: @escaping () -> String? = { Auth.auth().currentUser?.uid }
    ) {
        self.firestore = firestore
        self.userIDProvider = userIDProvider
    }

    func load() async throws {
        let docs = try await userDocument(firestore, userIDProvider).collection("fundsItemPrices").getDocuments().documents
        let infos = docs.compactMap { FundsFirestoreMapping.decodePriceInfo(id: $0.documentID, data: $0.data()) }
        byID = Dictionary(infos.map { ($0.pantryItemID, $0) }, uniquingKeysWith: { _, last in last })
    }

    func info(for itemID: PantryItemID) -> ItemPriceInfo? { byID[itemID] }

    func save(_ info: ItemPriceInfo) {
        byID[info.pantryItemID] = info
        guard let user = try? userDocument(firestore, userIDProvider) else { return }
        user.collection("fundsItemPrices").document(info.pantryItemID.rawValue)
            .setData(FundsFirestoreMapping.encode(info), completion: logIfFailed("item price"))
    }
}

final class FirestorePriceBookStore: PriceBookStore {
    private let firestore: Firestore
    private let userIDProvider: () -> String?
    private var byKey: [String: PriceBookEntry] = [:]

    init(
        firestore: Firestore = Firestore.firestore(),
        userIDProvider: @escaping () -> String? = { Auth.auth().currentUser?.uid }
    ) {
        self.firestore = firestore
        self.userIDProvider = userIDProvider
    }

    func load() async throws {
        let docs = try await userDocument(firestore, userIDProvider).collection("fundsPriceBook").getDocuments().documents
        let entries = docs.compactMap { FundsFirestoreMapping.decodePriceBookEntry($0.data()) }
        byKey = Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
    }

    func entry(forIngredientNamed name: String) -> PriceBookEntry? {
        byKey[PriceBookEntry.key(for: name)]
    }

    func record(_ entry: PriceBookEntry) {
        byKey[entry.key] = entry
        guard let user = try? userDocument(firestore, userIDProvider) else { return }
        user.collection("fundsPriceBook").document(FundsFirestoreMapping.documentID(forPriceBookKey: entry.key))
            .setData(FundsFirestoreMapping.encode(entry), completion: logIfFailed("price book"))
    }
}

// plain dictionary <-> model functions, no Firestore instance needed, so they can be
// unit tested (same approach as FirestorePantryRepository's mapping).
// money is stored as a string on purpose - Decimal through a Double would turn
// 4.5 into 4.4999999... eventually.
enum FundsFirestoreMapping {

    static func encode(_ budget: FoodBudget) -> [String: Any] {
        [
            "id": budget.id.uuidString,
            "limitAmount": "\(budget.limit.amount)",
            "currency": budget.currency.rawValue,
            "cadence": budget.cadence.rawValue,
            "startDate": budget.startDate,
        ]
    }

    static func decodeBudget(_ data: [String: Any]) -> FoodBudget? {
        guard
            let id = (data["id"] as? String).flatMap(UUID.init(uuidString:)),
            let limit = money(data["limitAmount"], data["currency"]),
            let cadence = (data["cadence"] as? String).flatMap(BudgetCadence.init(rawValue:)),
            let start = date(data["startDate"])
        else { return nil }
        return FoodBudget(id: id, limit: limit, cadence: cadence, startDate: start)
    }

    static func encode(_ spend: GrocerySpend) -> [String: Any] {
        var data: [String: Any] = [
            "amount": "\(spend.amount.amount)",
            "currency": spend.amount.currency.rawValue,
            "spentOn": spend.spentOn,
            "purchasedItemIDs": spend.purchasedItemIDs.map(\.rawValue),
        ]
        if let store = spend.store { data["store"] = store }
        if let note = spend.note { data["note"] = note }
        return data
    }

    static func decodeSpend(id: String, data: [String: Any]) -> GrocerySpend? {
        guard
            let uuid = UUID(uuidString: id),
            let amount = money(data["amount"], data["currency"]),
            let spentOn = date(data["spentOn"])
        else { return nil }
        let itemIDs = (data["purchasedItemIDs"] as? [String] ?? []).map(PantryItemID.init)
        return GrocerySpend(id: uuid, amount: amount, spentOn: spentOn,
                            store: data["store"] as? String,
                            purchasedItemIDs: itemIDs,
                            note: data["note"] as? String)
    }

    static func encode(_ cost: WastedFoodCost) -> [String: Any] {
        [
            "pantryItemID": cost.pantryItemID.rawValue,
            "quantityDiscarded": cost.quantityDiscarded,
            "lostAmount": "\(cost.lostAmount.amount)",
            "currency": cost.lostAmount.currency.rawValue,
            "discardedOn": cost.discardedOn,
            "reason": cost.reason.rawValue,
        ]
    }

    static func decodeWaste(id: String, data: [String: Any]) -> WastedFoodCost? {
        guard
            let uuid = UUID(uuidString: id),
            let itemID = data["pantryItemID"] as? String,
            let quantity = data["quantityDiscarded"] as? Double,
            let lost = money(data["lostAmount"], data["currency"]),
            let discardedOn = date(data["discardedOn"]),
            let reason = (data["reason"] as? String).flatMap(DiscardReason.init(rawValue:))
        else { return nil }
        return WastedFoodCost(id: uuid, pantryItemID: PantryItemID(itemID), quantityDiscarded: quantity,
                              lostAmount: lost, discardedOn: discardedOn, reason: reason)
    }

    static func encode(_ info: ItemPriceInfo) -> [String: Any] {
        var data: [String: Any] = [:]
        if let cost = info.unitCost {
            data["unitCost"] = "\(cost.amount)"
            data["currency"] = cost.currency.rawValue
        }
        // explicit null so clearing an expiry actually clears it on the server
        data["expiryDate"] = info.expiryDate ?? NSNull()
        return data
    }

    static func decodePriceInfo(id: String, data: [String: Any]) -> ItemPriceInfo? {
        guard !id.isEmpty else { return nil }
        return ItemPriceInfo(pantryItemID: PantryItemID(id),
                             unitCost: money(data["unitCost"], data["currency"]),
                             expiryDate: date(data["expiryDate"]))
    }

    // names can have spaces, slashes etc, which a document id can't, so encode it
    static func documentID(forPriceBookKey key: String) -> String {
        key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
    }

    static func encode(_ entry: PriceBookEntry) -> [String: Any] {
        [
            "displayName": entry.displayName,
            "unitCost": "\(entry.unitCost.amount)",
            "currency": entry.unitCost.currency.rawValue,
            "unit": entry.unit,
            "recordedOn": entry.recordedOn,
        ]
    }

    static func decodePriceBookEntry(_ data: [String: Any]) -> PriceBookEntry? {
        guard
            let name = data["displayName"] as? String,
            let cost = money(data["unitCost"], data["currency"]),
            let unit = data["unit"] as? String,
            let recordedOn = date(data["recordedOn"])
        else { return nil }
        return PriceBookEntry(displayName: name, unitCost: cost, unit: unit, recordedOn: recordedOn)
    }

    private static func money(_ amount: Any?, _ currency: Any?) -> Money? {
        guard
            let amountString = amount as? String,
            let value = Decimal(string: amountString, locale: Locale(identifier: "en_US_POSIX")),
            let currency = (currency as? String).flatMap(Currency.init(rawValue:))
        else { return nil }
        return Money(value, currency)
    }

    // Firestore hands dates back as Timestamp, but tests (and anything not yet
    // round-tripped) will just have a Date
    private static func date(_ value: Any?) -> Date? {
        if let timestamp = value as? Timestamp { return timestamp.dateValue() }
        return value as? Date
    }
}
