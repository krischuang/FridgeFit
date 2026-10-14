import SwiftUI

struct IngredientArtwork: View {
    let category: FoodCategory
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: CategorySymbol.symbol(for: category))
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(CategorySymbol.tint(for: category))
            .frame(width: size + 12, height: size + 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(CategorySymbol.tint(for: category).opacity(0.14))
            )
            .accessibilityHidden(true)
    }
}

struct IngredientTemplateArtwork: View {
    let template: IngredientTemplate
    var body: some View {
        IngredientArtwork(category: template.category, size: 30)
    }
}

enum CategorySymbol {
    static func symbol(for category: FoodCategory) -> String {
        switch category {
        case .vegetables: "leaf.fill"
        case .fruit: "circle.hexagongrid.fill"
        case .dairy: "drop.fill"
        case .meatAndFish: "fork.knife"
        case .bakery: "birthday.cake.fill"
        case .pantry: "archivebox.fill"
        case .frozen: "snowflake"
        case .beverage: "cup.and.saucer.fill"
        case .preparedMeal: "takeoutbag.and.cup.and.straw.fill"
        case .snack: "circle.grid.2x2.fill"
        case .other: "shippingbox.fill"
        }
    }

    static func tint(for category: FoodCategory) -> Color {
        switch category {
        case .vegetables:
            SmartFridgeTheme.warmAccent
        case .fruit:
            Color(red: 0.82, green: 0.28, blue: 0.24)
        case .dairy:
            Color(red: 0.22, green: 0.50, blue: 0.78)
        case .meatAndFish:
            Color(red: 0.70, green: 0.24, blue: 0.28)
        case .bakery, .pantry:
            SmartFridgeTheme.soon
        case .frozen:
            Color(red: 0.30, green: 0.58, blue: 0.86)
        case .beverage:
            Color(red: 0.25, green: 0.56, blue: 0.62)
        case .preparedMeal:
            Color(red: 0.52, green: 0.42, blue: 0.76)
        case .snack:
            Color(red: 0.78, green: 0.44, blue: 0.18)
        case .other:
            .secondary
        }
    }
}
