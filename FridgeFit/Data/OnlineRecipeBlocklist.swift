//
//  OnlineRecipeBlocklist.swift
//  FridgeFit
//

import Foundation

/// The team-curated list of provider recipes FridgeFit never recommends,
/// shipped in the app bundle as `Resources/blocked_online_recipes.json`.
///
/// Spoonacular's data is uneven; some recipes stay broken even after
/// `SpoonacularContentCleaner` (wrong photo, nonsense steps, unsafe method).
/// When testing finds one, add its id - shown at the bottom of the Discover
/// detail screen - with a specific reason:
///
/// ```json
/// { "id": 716429, "reason": "steps describe a different dish" }
/// ```
///
/// This list applies to every user. The in-app "Hide" action is per device
/// and lives in `HiddenOnlineRecipeStoring` instead.
///
/// A missing or malformed file yields an empty list rather than failing:
/// a blocklist problem must never take Discover down.
nonisolated enum OnlineRecipeBlocklist {
    struct Entry: Decodable, Equatable {
        let id: Int
        let reason: String?
    }

    private struct File: Decodable {
        let recipes: [Entry]
    }

    static let resourceName = "blocked_online_recipes"

    static func entries(from data: Data) -> [Entry] {
        (try? JSONDecoder().decode(File.self, from: data))?.recipes ?? []
    }

    static func blockedIDs(from data: Data) -> Set<Int> {
        Set(entries(from: data).map(\.id))
    }

    static func bundledIDs(bundle: Bundle = .main) -> Set<Int> {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        return blockedIDs(from: data)
    }
}
