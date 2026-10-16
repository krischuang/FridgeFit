//
//  IngredientTemplate.swift
//  FridgeFit
//

import Foundation

/// A starting point for the quick-add grid - not a stored item.
///
/// Templates suggest a typical category, location, amount and shelf life so
/// adding milk takes one tap instead of five fields. Nothing is saved until
/// the user confirms in the editor, and every value is editable there.
nonisolated struct IngredientTemplate: Identifiable, Equatable, Sendable {
    /// Keyed by name, so the same food picked twice is the same template.
    var id: String { name.lowercased() }
    var name: String
    var category: IngredientCategory
    var storageLocation: StorageLocation
    var defaultQuantity: Quantity
    var openedState: OpenedState
    var lowStockThreshold: Double?
    /// Typical shelf life in days from today, used to pre-fill the expiry
    /// date. `nil` for food with no meaningful expiry, which leaves the
    /// editor's expiry toggle off rather than inventing a date.
    var expiryOffsetDays: Int?

    init(
        name: String,
        category: IngredientCategory,
        storageLocation: StorageLocation,
        defaultQuantity: Quantity,
        openedState: OpenedState = .notApplicable,
        lowStockThreshold: Double? = nil,
        expiryOffsetDays: Int? = nil
    ) {
        self.name = name
        self.category = category
        self.storageLocation = storageLocation
        self.defaultQuantity = defaultQuantity
        self.openedState = openedState
        self.lowStockThreshold = lowStockThreshold
        self.expiryOffsetDays = expiryOffsetDays
    }

    /// The expiry date this template suggests, or `nil` when it suggests
    /// none.
    func suggestedExpiryDate(from now: Date = .now, calendar: Calendar = .current) -> Date? {
        expiryOffsetDays.flatMap { calendar.date(byAdding: .day, value: $0, to: now) }
    }
}

/// The common picks offered by the quick-add grid.
///
/// Deliberately short and deliberately not seeded into anyone's pantry: the
/// branch this came from wrote nine sample items into storage on first
/// launch, which would mean a new FridgeFit user's Firestore pantry arriving
/// pre-filled with food they do not own. These are suggestions only.
///
/// Categories are mapped onto FridgeFit's existing `IngredientCategory`
/// rather than introducing a second taxonomy, so a template-added item is
/// indistinguishable from one added on the Pantry tab.
nonisolated enum InventoryTemplateCatalog {
    static let templates: [IngredientTemplate] = [
        IngredientTemplate(
            name: "Eggs",
            category: .dairy,
            storageLocation: .fridge,
            defaultQuantity: .count(6),
            lowStockThreshold: 3,
            expiryOffsetDays: 14
        ),
        IngredientTemplate(
            name: "Milk",
            category: .dairy,
            storageLocation: .fridge,
            defaultQuantity: .package(count: 1, unit: .bottle, level: .full),
            openedState: .unopened,
            lowStockThreshold: 0.25,
            expiryOffsetDays: 7
        ),
        IngredientTemplate(
            name: "Banana",
            category: .produce,
            storageLocation: .pantry,
            defaultQuantity: .count(6),
            lowStockThreshold: 2,
            expiryOffsetDays: 4
        ),
        IngredientTemplate(
            name: "Chicken Breast",
            category: .meat,
            storageLocation: .fridge,
            defaultQuantity: .measure(500, unit: .grams),
            lowStockThreshold: 150,
            expiryOffsetDays: 2
        ),
        IngredientTemplate(
            name: "Tomato",
            category: .produce,
            storageLocation: .fridge,
            defaultQuantity: .count(4),
            lowStockThreshold: 2,
            expiryOffsetDays: 5
        ),
        IngredientTemplate(
            name: "Spinach",
            category: .produce,
            storageLocation: .fridge,
            defaultQuantity: .measure(150, unit: .grams),
            lowStockThreshold: 60,
            expiryOffsetDays: 2
        ),
        IngredientTemplate(
            name: "Cheddar Cheese",
            category: .dairy,
            storageLocation: .fridge,
            defaultQuantity: .package(count: 1, unit: .block, level: .full),
            openedState: .unopened,
            lowStockThreshold: 0.25,
            expiryOffsetDays: 21
        ),
        // Staples carry a real measured amount rather than "plenty": the
        // pantry stores a number, and a bag of rice has one.
        IngredientTemplate(
            name: "Rice",
            category: .grain,
            storageLocation: .pantry,
            defaultQuantity: .measure(1, unit: .kilograms),
            lowStockThreshold: 0.2
        ),
        IngredientTemplate(
            name: "Salt",
            category: .spice,
            storageLocation: .pantry,
            defaultQuantity: .measure(500, unit: .grams),
            lowStockThreshold: 100
        ),
        IngredientTemplate(
            name: "Frozen Peas",
            category: .produce,
            storageLocation: .freezer,
            defaultQuantity: .package(count: 1, unit: .pack, level: .full),
            openedState: .unopened,
            lowStockThreshold: 0.25
        ),
    ]

    /// Templates matching `query` by name or category, or all of them when
    /// the query is blank.
    static func matching(_ query: String) -> [IngredientTemplate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return templates }
        return templates.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.category.displayName.localizedCaseInsensitiveContains(trimmed)
        }
    }
}
