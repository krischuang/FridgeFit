//
//  PantryItem.swift
//  FridgeFit
//

import Foundation

/// An `Ingredient` and how much of it the user currently has on hand.
///
/// ## The kitchen fields
///
/// `expiryDate`, `storageLocation`, `openedState`, `lowStockThreshold`,
/// `packageUnit` and `packageLevel` were added for the kitchen inventory UI.
/// **Every one of them is optional**, and that is load-bearing rather than
/// laziness: documents written before they existed - which is every document
/// in every existing user's pantry - decode with `nil` in each one and behave
/// exactly as they did before. Nothing backfills them, and nothing requires
/// them.
///
/// `quantity` and `unit` are unchanged and remain the canonical amount.
/// `EvaluateRecipeFeasibilityUseCase`, `GetIngredientSubstitutionsUseCase`
/// and the receipt scanner all read them directly, so the kitchen UI writes
/// through them (see `inventoryQuantity`) instead of storing a second,
/// competing amount beside them.
nonisolated struct PantryItem: Identifiable, Hashable, Codable {
    let id: UUID
    var ingredient: Ingredient
    var quantity: Double
    var unit: MeasurementUnit

    // MARK: - Kitchen inventory fields (all optional, all absent on legacy items)

    /// When this goes off, if the user said. `nil` means expiry is not
    /// tracked for this item - which is different from "expires today", so
    /// it is never defaulted to a date.
    var expiryDate: Date?
    /// Where it is kept. `nil` for items added before storage locations
    /// existed, and for scanner/camera additions that genuinely do not know.
    /// Read through `storage` for a display-safe value.
    var storageLocation: StorageLocation?
    /// Whether the package is open. `nil` and `.notApplicable` both mean the
    /// question doesn't apply; the distinction is only that `nil` predates
    /// the field.
    var openedState: OpenedState?
    /// The amount at which the kitchen screen starts calling this low.
    /// `nil` means the user hasn't set one, so nothing is flagged.
    var lowStockThreshold: Double?
    /// For packaged quantities: the package kind ("bottle") and how much is
    /// left ("half"). Stored beside `quantity`/`unit` rather than instead of
    /// them, so a half bottle is both `0.5 pcs` for recipe feasibility and
    /// "½ bottle" for the kitchen UI.
    var packageUnit: PackageUnit?
    var packageLevel: PackageLevel?
    /// When the item first entered the pantry, set by whichever flow added
    /// it. `nil` on everything stored before this field existed, which is
    /// read as "not recent" rather than backfilled to now - dating an old
    /// item to this launch would put a week-old tomato under "Recently
    /// added".
    var addedAt: Date?

    init(
        id: UUID = UUID(),
        ingredient: Ingredient,
        quantity: Double,
        unit: MeasurementUnit,
        expiryDate: Date? = nil,
        storageLocation: StorageLocation? = nil,
        openedState: OpenedState? = nil,
        lowStockThreshold: Double? = nil,
        packageUnit: PackageUnit? = nil,
        packageLevel: PackageLevel? = nil,
        addedAt: Date? = nil
    ) {
        self.id = id
        self.ingredient = ingredient
        self.quantity = quantity
        self.unit = unit
        self.expiryDate = expiryDate
        self.storageLocation = storageLocation
        self.openedState = openedState
        self.lowStockThreshold = lowStockThreshold
        self.packageUnit = packageUnit
        self.packageLevel = packageLevel
        self.addedAt = addedAt
    }

    /// How long after being added an item still counts as recent.
    static let recentlyAddedWindow: TimeInterval = 3 * 60 * 60

    /// Whether this belongs in the "Recently added" section.
    ///
    /// False for anything with no `addedAt`, and false for a timestamp in the
    /// future - a device with a skewed clock should drop out of the section,
    /// not sit in it indefinitely.
    func wasAddedRecently(now: Date = Date()) -> Bool {
        guard let addedAt else { return false }
        let age = now.timeIntervalSince(addedAt)
        return age >= 0 && age <= Self.recentlyAddedWindow
    }

    var name: String { ingredient.name }

    var formattedQuantity: String { unit.formatted(quantity) }

    // MARK: - Kitchen inventory readings

    /// The amount, read as a `Quantity`.
    ///
    /// Derived rather than stored, so there is exactly one amount in the
    /// model and it cannot drift from what recipes read:
    ///
    /// - a package unit and level present → `.package`
    /// - unit is `.pieces` and the amount is whole → `.count`
    /// - anything else → `.measure`
    ///
    /// A legacy item lands on `.count` or `.measure` with no extra fields
    /// needed, which is why no migration is required to show one in the
    /// kitchen UI.
    var inventoryQuantity: Quantity {
        if let packageUnit, let packageLevel {
            let perPackage = packageLevel.rawValue
            let count = perPackage > 0 ? Int((quantity / perPackage).rounded()) : 0
            return .package(count: max(0, count), unit: packageUnit, level: packageLevel)
        }
        if unit == .pieces, quantity.truncatingRemainder(dividingBy: 1) == 0 {
            return .count(Int(quantity), unit: .pieces)
        }
        return .measure(quantity, unit: unit)
    }

    /// Writes a `Quantity` back through `quantity`/`unit`, keeping the
    /// package reading beside it when there is one.
    ///
    /// The only place the kitchen UI is allowed to set an amount, so the
    /// canonical fields can never be left stale.
    mutating func setInventoryQuantity(_ newValue: Quantity) {
        quantity = newValue.normalizedAmount
        unit = newValue.storageUnit
        switch newValue {
        case .package(_, let packUnit, let level):
            packageUnit = packUnit
            packageLevel = level
        case .count, .measure:
            packageUnit = nil
            packageLevel = nil
        }
    }

    /// Storage location for display. Legacy and scanner-added items have
    /// none recorded, and the pantry is the honest default for "we were
    /// never told" - it is the one place food can sit without a claim about
    /// refrigeration.
    var storage: StorageLocation {
        storageLocation ?? .pantry
    }

    /// Opened state for display, treating "never recorded" as "doesn't
    /// apply" so no row claims a jar is unopened on no evidence.
    var opened: OpenedState {
        openedState ?? .notApplicable
    }

    /// Whether the remaining amount has reached the user's own threshold.
    ///
    /// `false` when no threshold is set. Nothing is inferred from the
    /// quantity alone - two eggs is low for an omelette and plenty for a
    /// cake, and the app has no way to know which.
    var isLowStock: Bool {
        guard let lowStockThreshold else { return false }
        return quantity <= lowStockThreshold
    }

    /// How close this is to expiring, or `nil` when expiry isn't tracked.
    var expiryState: ExpiryState? {
        ExpiryService.state(for: expiryDate)
    }
}
