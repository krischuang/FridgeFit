import Foundation

public enum SmartFridgeSeedData {
    public static func ingredients(now: Date = .now, calendar: Calendar = .current) -> [Ingredient] {
        [
            Ingredient(
                name: "Spinach",
                category: "Vegetables",
                storageLocation: .fridge,
                quantity: .measure(150, unit: .grams),
                expiryDate: calendar.date(byAdding: .day, value: 0, to: now),
                lowStockThreshold: 60
            ),
            Ingredient(
                name: "Milk",
                category: "Dairy",
                storageLocation: .fridge,
                quantity: .package(count: 1, unit: .bottle, level: .half),
                expiryDate: calendar.date(byAdding: .day, value: 1, to: now),
                openedState: .opened,
                lowStockThreshold: 0.25
            ),
            Ingredient(
                name: "Chicken Breast",
                category: "Meat",
                storageLocation: .fridge,
                quantity: .measure(500, unit: .grams),
                expiryDate: calendar.date(byAdding: .day, value: 2, to: now),
                lowStockThreshold: 150
            ),
            Ingredient(
                name: "Eggs",
                category: "Dairy",
                storageLocation: .fridge,
                quantity: .count(6),
                expiryDate: calendar.date(byAdding: .day, value: 9, to: now),
                lowStockThreshold: 3
            ),
            Ingredient(
                name: "Tomatoes",
                category: "Vegetables",
                storageLocation: .fridge,
                quantity: .count(4),
                expiryDate: calendar.date(byAdding: .day, value: 5, to: now),
                lowStockThreshold: 2
            ),
            Ingredient(
                name: "Cheddar Cheese",
                category: "Dairy",
                storageLocation: .fridge,
                quantity: .package(count: 1, unit: .block, level: .half),
                expiryDate: calendar.date(byAdding: .day, value: 12, to: now),
                openedState: .opened,
                lowStockThreshold: 0.25
            ),
            Ingredient(
                name: "Rice",
                category: "Grains",
                storageLocation: .pantry,
                quantity: .presence(.plenty)
            ),
            Ingredient(
                name: "Salt",
                category: "Staples",
                storageLocation: .pantry,
                quantity: .presence(.available)
            ),
            Ingredient(
                name: "Frozen Peas",
                category: "Vegetables",
                storageLocation: .freezer,
                quantity: .package(count: 1, unit: .pack, level: .full)
            )
        ]
    }

    public static let templates: [IngredientTemplate] = [
        IngredientTemplate(name: "Eggs", category: "Dairy", storageLocation: .fridge, defaultQuantity: .count(6), lowStockThreshold: 3, expiryOffsetDays: 14),
        IngredientTemplate(name: "Milk", category: "Dairy", storageLocation: .fridge, defaultQuantity: .package(count: 1, unit: .bottle, level: .full), openedState: .unopened, lowStockThreshold: 0.25, expiryOffsetDays: 7),
        IngredientTemplate(name: "Banana", category: "Fruit", storageLocation: .pantry, defaultQuantity: .count(6), lowStockThreshold: 2, expiryOffsetDays: 4),
        IngredientTemplate(name: "Chicken Breast", category: "Meat", storageLocation: .fridge, defaultQuantity: .measure(500, unit: .grams), lowStockThreshold: 150, expiryOffsetDays: 2),
        IngredientTemplate(name: "Tomato", category: "Vegetables", storageLocation: .fridge, defaultQuantity: .count(4), lowStockThreshold: 2, expiryOffsetDays: 5),
        IngredientTemplate(name: "Spinach", category: "Vegetables", storageLocation: .fridge, defaultQuantity: .measure(150, unit: .grams), lowStockThreshold: 60, expiryOffsetDays: 2),
        IngredientTemplate(name: "Rice", category: "Grains", storageLocation: .pantry, defaultQuantity: .presence(.plenty)),
        IngredientTemplate(name: "Salt", category: "Staples", storageLocation: .pantry, defaultQuantity: .presence(.available)),
        IngredientTemplate(name: "Frozen Peas", category: "Vegetables", storageLocation: .freezer, defaultQuantity: .package(count: 1, unit: .pack, level: .full))
    ]
}
