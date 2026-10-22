//
//  IngredientArtwork.swift
//  FridgeFit
//

import SwiftUI

/// The category glyph on kitchen tiles and in the editor.
///
/// Reuses `IngredientCategory.symbolName` and the `tint` already defined in
/// `PantryPresentation`, so an item's icon is the same on the Kitchen tab as
/// it is on the Pantry tab. The ported version carried its own eleven-case
/// symbol table; keeping two would mean the same food drawn two ways
/// depending on which tab you opened.
struct IngredientArtwork: View {
    let category: IngredientCategory
    var size: CGFloat = 34

    var body: some View {
        // a real photo for the category if there's one in Assets, otherwise the
        // old tinted symbol
        if let photo = BundledPhotoAssets.categoryPhoto(for: category) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size + 12, height: size + 12)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
        } else {
            symbol
        }
    }

    private var symbol: some View {
        Image(systemName: category.symbolName)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(category.tint)
            .frame(width: size + 12, height: size + 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(category.tint.opacity(0.14))
            )
            .accessibilityHidden(true)
    }
}

/// The same glyph at the size the quick-add grid uses.
struct IngredientTemplateArtwork: View {
    let template: IngredientTemplate

    var body: some View {
        IngredientArtwork(category: template.category, size: 30)
    }
}
