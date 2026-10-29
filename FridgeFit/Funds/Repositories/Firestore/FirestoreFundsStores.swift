//
//  FirestoreFundsStores.swift
//  FridgeFit
//

import FirebaseAuth
import FirebaseFirestore
import Foundation
import OSLog

// Firestore versions of BudgetStore / ItemPriceStore / PriceBookStore. Reads are sync
// (that's how the FridgeFunds use cases were written), Firestore isn't - so each store
// keeps a local copy: load() fills it once and reads come straight from it.
//
// everything lives under the signed-in user, next to the pantry:
//   users/{uid}/fundsBudget/current
//   users/{uid}/fundsSpends/{spendId}
//   users/{uid}/fundsWaste/{wasteId}
//   users/{uid}/fundsItemPrices/{pantryItemId}
//   users/{uid}/fundsPriceBook/{encoded ingredient name}
//
// ## What changed about the writes, and why
//
// Every write used to look like this:
//
//     func saveBudget(_ budget: FoodBudget) {
//         self.budget = budget                                  // local copy, now
//         guard let user = try? userDocument(...) else { return }   // <- swallowed
//         user.collection("fundsBudget").document("current")
//             .setData(encode(budget), completion: logIfFailed("budget"))  // <- swallowed
//     }
//
// Three separate ways for a failed save to look like a successful one:
//
//  1. `try?` on user resolution. A signed-out user (or one whose token had expired)
//     returned early, having already updated the local copy. The screen showed the new
//     budget; nothing was ever sent anywhere.
//  2. `logIfFailed` as the completion handler. A permission-denied or
//     unauthenticated write wrote a line to the console and nothing else. The user saw
//     a saved budget the backend had refused.
//  3. No rollback. In both cases the in-memory copy kept the value, so even a *reload*
//     would not correct the display until the process restarted.
//
// Now: the user is resolved with `try` so a signed-out write throws, the write is
// awaited so its real result is propagated, and the local copy is only kept if the
// write was accepted - otherwise it is rolled back to what it was.
//
// ## The offline subtlety
//
// `setData`'s completion fires on *server* acknowledgement. Offline, Firestore
// persists the write to a durable local queue and sends it later, which can be much
// later - so awaiting it without a bound would hang Save for the whole time a device
// was off the network. The wait is therefore bounded: past the bound the write is
// still safely queued, and the store reports `.pendingSync` rather than claiming a
// server round trip it has not had. See `FundsWriteOutcome`.

private let logger = Logger(subsystem: "com.fridgefit.app", category: "FridgeFunds")

/// How long to wait for the server before calling a write queued rather than
/// committed. Short enough that Save never feels stuck, long enough that a
/// healthy connection reports the truthful `.committed`.
private let acknowledgementTimeout: Duration = .seconds(5)

private func userDocument(_ firestore: Firestore, _ uid: () -> String?) throws -> DocumentReference {
    guard let uid = uid(), !uid.isEmpty else { throw PantryRepositoryError.notAuthenticated }
    return firestore.collection("users").document(uid)
}

/// Marker for "the bound elapsed", never surfaced to a caller.
private struct AcknowledgementPending: Error {}

/// Writes `data` to `document` and reports whether the server confirmed it.
///
/// - Throws: whatever Firestore rejected the write with. A thrown error means
///   the write will never land, so the caller must roll its local copy back.
private func commit(_ data: [String: Any], to document: DocumentReference, describing what: String) async throws -> FundsWriteOutcome {
    do {
        try await BoundedWork.run(
            timeout: acknowledgementTimeout,
            timeoutError: { AcknowledgementPending() }
        ) {
            try await document.setData(data)
        }
        return .committed
    } catch is AcknowledgementPending {
        // Not a failure. Firestore has it on disk and will deliver it; we
        // simply have not heard back yet.
        logger.notice("\(what, privacy: .public) is queued for sync, not yet acknowledged")
        return .pendingSync
    } catch {
        logger.error("Saving \(what, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        throw error
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

    /// Resolved before the local copy is touched, so a signed-out write
    /// changes nothing at all rather than updating the screen and returning.
    @discardableResult
    func saveBudget(_ budget: FoodBudget) async throws -> FundsWriteOutcome {
        let user = try userDocument(firestore, userIDProvider)
        let previous = self.budget
        self.budget = budget
        do {
            return try await commit(
                FundsFirestoreMapping.encode(budget),
                to: user.collection("fundsBudget").document("current"),
                describing: "budget"
            )
        } catch {
            self.budget = previous
            throw error
        }
    }

    func allSpends() -> [GrocerySpend] { spends }

    /// Keyed by the spend's own id, so a retry after a failure overwrites one
    /// document rather than appending a second identical spend.
    @discardableResult
    func addSpend(_ spend: GrocerySpend) async throws -> FundsWriteOutcome {
        let user = try userDocument(firestore, userIDProvider)
        spends.append(spend)
        do {
            return try await commit(
                FundsFirestoreMapping.encode(spend),
                to: user.collection("fundsSpends").document(spend.id.uuidString),
                describing: "spend"
            )
        } catch {
            spends.removeAll { $0.id == spend.id }
            throw error
        }
    }

    func allWasteCosts() -> [WastedFoodCost] { wasteCosts }

    @discardableResult
    func addWasteCost(_ cost: WastedFoodCost) async throws -> FundsWriteOutcome {
        let user = try userDocument(firestore, userIDProvider)
        wasteCosts.append(cost)
        do {
            return try await commit(
                FundsFirestoreMapping.encode(cost),
                to: user.collection("fundsWaste").document(cost.id.uuidString),
                describing: "waste"
            )
        } catch {
            wasteCosts.removeAll { $0.id == cost.id }
            throw error
        }
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

    @discardableResult
    func save(_ info: ItemPriceInfo) async throws -> FundsWriteOutcome {
        let user = try userDocument(firestore, userIDProvider)
        let previous = byID[info.pantryItemID]
        byID[info.pantryItemID] = info
        do {
            return try await commit(
                FundsFirestoreMapping.encode(info),
                to: user.collection("fundsItemPrices").document(info.pantryItemID.rawValue),
                describing: "item price"
            )
        } catch {
            byID[info.pantryItemID] = previous
            throw error
        }
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

    @discardableResult
    func record(_ entry: PriceBookEntry) async throws -> FundsWriteOutcome {
        let user = try userDocument(firestore, userIDProvider)
        let previous = byKey[entry.key]
        byKey[entry.key] = entry
        do {
            return try await commit(
                FundsFirestoreMapping.encode(entry),
                to: user.collection("fundsPriceBook")
                    .document(FundsFirestoreMapping.documentID(forPriceBookKey: entry.key)),
                describing: "price book"
            )
        } catch {
            byKey[entry.key] = previous
            throw error
        }
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
