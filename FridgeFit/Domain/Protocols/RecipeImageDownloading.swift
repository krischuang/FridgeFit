//
//  RecipeImageDownloading.swift
//  FridgeFit
//

import Foundation

/// Fetches a recipe photo once, at save time, so it can be stored with the
/// saved recipe.
///
/// Never throws: a photo is a nice-to-have, so any failure (offline, not an
/// image, too large) returns `nil` and the recipe is still saved.
nonisolated protocol RecipeImageDownloading: AnyObject {
    func imageData(from url: URL) async -> Data?
}
