//
//  RecipePhoto.swift
//  FridgeFit
//

import SwiftUI
import UIKit

/// A recipe's photo, from the best source available:
///
/// 1. the stored photo of a saved recipe, already decoded off the main
///    thread (`RecipeViewModel.thumbnail(for:)`) - works offline,
/// 2. otherwise the original `imageURL`, loaded on demand,
/// 3. otherwise `placeholder` (bundled recipes, or no photo at all).
///
/// Fills its frame; callers size and clip it. Never decodes image bytes in
/// `body` - it only draws an image that is already decoded.
struct RecipePhoto<Placeholder: View>: View {
    let image: UIImage?
    let imageURL: URL?
    @ViewBuilder let placeholder: () -> Placeholder

    /// Whether there is any photo to show for this recipe.
    static func hasPhoto(image: UIImage?, imageURL: URL?) -> Bool {
        image != nil || imageURL != nil
    }

    var body: some View {
        if let image {
            Image(uiImage: image)
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
