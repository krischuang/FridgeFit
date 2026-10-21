//
//  RecipePhoto.swift
//  FridgeFit
//

import SwiftUI
import UIKit

/// A recipe's photo, from the best source available:
///
/// 1. the copy stored with the saved recipe (`imageData`) - works offline,
/// 2. otherwise the original `imageURL`, loaded on demand,
/// 3. otherwise `placeholder` (bundled recipes, or no photo at all).
///
/// Fills its frame; callers size and clip it.
struct RecipePhoto<Placeholder: View>: View {
    let imageData: Data?
    let imageURL: URL?
    @ViewBuilder let placeholder: () -> Placeholder

    /// Whether there is any photo to show for this recipe.
    static func hasPhoto(imageData: Data?, imageURL: URL?) -> Bool {
        imageData != nil || imageURL != nil
    }

    var body: some View {
        if let imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else if let imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholder()
                }
            }
        } else {
            placeholder()
        }
    }
}
