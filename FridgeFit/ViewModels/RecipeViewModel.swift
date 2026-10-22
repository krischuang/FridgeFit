//
//  RecipeViewModel.swift
//  FridgeFit
//

import Combine
import Foundation
import UIKit

/// Presentation state and actions for browsing recipes and checking each
/// one's feasibility against the current pantry.
///
/// Never computes feasibility itself - that's all
/// `EvaluateRecipeFeasibilityUseCase`. This just loads recipes, runs the
/// use case for each one, and caches the results by recipe id so list rows
/// and the detail screen agree on the same verdict.
///
/// Also owns recipes saved from Discover: they're loaded alongside the
/// bundled ones and evaluated by the same feasibility use case. Saving and
/// removing go through `SaveOnlineRecipeUseCase` / `RemoveSavedRecipeUseCase`.
@MainActor
final class RecipeViewModel: ObservableObject {
    @Published private(set) var recipes: [Recipe] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoadErrorAlertPresented = false
    @Published private(set) var feasibilityResults: [UUID: RecipeFeasibilityResult] = [:]
    /// Ids of recipes in `recipes` that the user saved from Discover.
    @Published private(set) var savedRecipeIDs: Set<UUID> = []
    /// Online recipe ids currently being saved, for per-button spinners.
    @Published private(set) var savingOnlineRecipeIDs: Set<Int> = []
    /// A saved-collection fetch failure remains available to the inline retry
    /// UI until a later fetch succeeds. It is intentionally separate from
    /// save/remove errors, whose alert can be dismissed without losing retry.
    @Published private(set) var savedRecipeLoadErrorMessage: String?
    /// Last save/remove failure. Separate from `errorMessage` so it never
    /// shows up as "Couldn't Load Recipes".
    @Published var savedRecipeErrorMessage: String?
    /// Decoded, display-ready thumbnails of saved recipes' stored photos, by
    /// recipe id. Read from the saved-recipe store (never the network) and
    /// decoded off the main thread; views only draw them. The JPEG bytes are
    /// not kept here.
    ///
    /// List-sized (`RecipeThumbnailDecoder.listPixelSize`) - one of these per
    /// saved recipe is held at once, so this is the size that decides how much
    /// memory the screen costs. The detail hero gets its own larger copy, for
    /// the one recipe that is open: see `savedRecipeHeroImages`.
    @Published private(set) var savedRecipeThumbnails: [UUID: UIImage] = [:]
    /// Hero-sized copies, decoded on demand for the recipe being viewed.
    /// Bounded by `heroImageCache`, which holds only a handful - unlike the
    /// list, the detail screen shows one photo at a time.
    @Published private(set) var savedRecipeHeroImages: [UUID: UIImage] = [:]
    private(set) var hasLoaded = false

    private let recipeRepository: RecipeRepository
    private let evaluateFeasibilityUseCase: EvaluateRecipeFeasibilityUseCase
    private let savedRecipeRepository: SavedRecipeRepository?
    private let thumbnailCache: RecipeThumbnailCache
    private let heroImageCache: RecipeThumbnailCache
    /// Saved recipes already checked and found to have no stored photo, so
    /// a reload doesn't ask the store for them again.
    private var recipeIDsWithoutPhoto: Set<UUID> = []
    private let saveOnlineRecipeUseCase: SaveOnlineRecipeUseCase?
    private let removeSavedRecipeUseCase: RemoveSavedRecipeUseCase?

    /// Why saving from Discover is unavailable, for the UI to explain rather
    /// than quietly omit the control. `nil` when saving is available, or
    /// when the caller is a preview or test that simply didn't wire a store.
    let savedRecipeUnavailableExplanation: String?

    /// - Parameters:
    ///   - savedRecipeRepository: `nil` disables saving from Discover
    ///     (previews, tests that don't need it, and the running app while
    ///     `OnlineRecipeFeature.savedRecipeStorage` is gated off).
    ///   - savedRecipeUnavailableExplanation: shown by
    ///     `OnlineRecipeDetailView` when `savedRecipeRepository` is `nil`.
    ///     Injected rather than read from `OnlineRecipeFeature` here so the
    ///     view model stays independent of the feature gate and tests can
    ///     assert either state.
    ///
    /// `recipeRepository` and `pantryRepository` are required rather than
    /// defaulted, for the reason `InventoryStore` and `PantryViewModel`
    /// already record: the only available defaults are a bundled catalogue
    /// and an in-memory pantry, and a screen that silently shows sample data
    /// instead of the user's own is a worse failure than a compile error.
    /// It also keeps main-actor types out of default-argument expressions,
    /// which `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` warns about.
    init(
        recipeRepository: RecipeRepository,
        pantryRepository: PantryRepository,
        savedRecipeRepository: SavedRecipeRepository? = nil,
        savedRecipeUnavailableExplanation: String? = nil,
        imageDownloader: RecipeImageDownloading? = nil,
        thumbnailCache: RecipeThumbnailCache = RecipeThumbnailCache(),
        heroImageCache: RecipeThumbnailCache = RecipeThumbnailCache(
            countLimit: 4,
            totalCostLimit: 12 * 1024 * 1024
        )
    ) {
        self.recipeRepository = recipeRepository
        self.thumbnailCache = thumbnailCache
        self.heroImageCache = heroImageCache
        self.evaluateFeasibilityUseCase = EvaluateRecipeFeasibilityUseCase(pantryRepository: pantryRepository)
        self.savedRecipeRepository = savedRecipeRepository
        self.saveOnlineRecipeUseCase = savedRecipeRepository.map {
            SaveOnlineRecipeUseCase(repository: $0, imageDownloader: imageDownloader)
        }
        self.removeSavedRecipeUseCase = savedRecipeRepository.map { RemoveSavedRecipeUseCase(repository: $0) }
        self.savedRecipeUnavailableExplanation = savedRecipeRepository == nil
            ? savedRecipeUnavailableExplanation
            : nil
    }

    var canSaveRecipes: Bool { saveOnlineRecipeUseCase != nil }

    /// Recipes saved from Discover, newest first.
    var savedRecipes: [Recipe] { recipes.filter { savedRecipeIDs.contains($0.id) } }

    /// FridgeFit's own bundled recipes.
    var bundledRecipes: [Recipe] { recipes.filter { !savedRecipeIDs.contains($0.id) } }

    /// Loads (or reloads) recipes, then re-evaluates feasibility for all
    /// of them. Call whenever Recipes is opened.
    func loadRecipes() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let bundled = try await recipeRepository.fetchAll()
            errorMessage = nil
            isLoadErrorAlertPresented = false

            // A saved-recipes failure must not hide the bundled list.
            var saved: [Recipe] = []
            if let savedRecipeRepository {
                do {
                    saved = try await savedRecipeRepository.fetchAll()
                    savedRecipeLoadErrorMessage = nil
                } catch {
                    savedRecipeLoadErrorMessage = (error as? SaveOnlineRecipeError)?.errorDescription
                        ?? SaveOnlineRecipeError.loadFailed.errorDescription
                    saved = savedRecipes
                }
            } else {
                savedRecipeLoadErrorMessage = nil
            }

            let savedIDs = Set(saved.map(\.id))
            recipes = saved + bundled.filter { !savedIDs.contains($0.id) }
            savedRecipeIDs = savedIDs
            hasLoaded = true
            await loadSavedRecipeImages(for: saved)
            await refreshFeasibility()
        } catch {
            errorMessage = error.localizedDescription
            isLoadErrorAlertPresented = true
        }
    }

    /// Hides the transient alert without discarding the failed-load state.
    /// The catalogue continues to show its inline Retry action until a later
    /// load succeeds.
    func dismissLoadErrorAlert() {
        isLoadErrorAlertPresented = false
    }

    /// Loads once if nothing has been loaded yet - used by Discover so its
    /// "Saved" badges are right even before the Recipes tab is opened.
    func loadRecipesIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await loadRecipes()
    }

    /// Whether the Discover recipe with provider id `onlineRecipeID` is
    /// already on the Recipes page.
    func isSaved(onlineRecipeID: Int) -> Bool {
        savedRecipeIDs.contains(SaveOnlineRecipeUseCase.savedRecipeID(forOnlineRecipeID: onlineRecipeID))
    }

    func isSaving(onlineRecipeID: Int) -> Bool {
        savingOnlineRecipeIDs.contains(onlineRecipeID)
    }

    /// Saves a Discover recipe to the Recipes page and evaluates it against
    /// the pantry straight away.
    func saveOnlineRecipe(_ onlineRecipe: OnlineRecipe) async {
        guard let saveOnlineRecipeUseCase, !savingOnlineRecipeIDs.contains(onlineRecipe.id) else { return }
        savingOnlineRecipeIDs.insert(onlineRecipe.id)
        defer { savingOnlineRecipeIDs.remove(onlineRecipe.id) }
        savedRecipeErrorMessage = nil

        do {
            let recipe = try await saveOnlineRecipeUseCase.execute(onlineRecipe)
            recipes.removeAll { $0.id == recipe.id }
            recipes.insert(recipe, at: 0)
            savedRecipeIDs.insert(recipe.id)
            // A re-save may have stored a new photo: drop what we had.
            thumbnailCache.remove(recipe.id)
            heroImageCache.remove(recipe.id)
            recipeIDsWithoutPhoto.remove(recipe.id)
            savedRecipeThumbnails[recipe.id] = nil
            savedRecipeHeroImages[recipe.id] = nil
            let fresh = await thumbnails(for: [recipe.id])
            savedRecipeThumbnails.merge(fresh) { _, new in new }
            if let result = try? await evaluateFeasibilityUseCase.execute(recipe: recipe) {
                feasibilityResults[recipe.id] = result
            }
        } catch {
            savedRecipeErrorMessage = (error as? SaveOnlineRecipeError)?.errorDescription
                ?? SaveOnlineRecipeError.saveFailed.errorDescription
        }
    }

    /// Removes a recipe saved from Discover. Ignored for bundled recipes.
    func removeSavedRecipe(_ recipe: Recipe) async {
        guard let removeSavedRecipeUseCase, savedRecipeIDs.contains(recipe.id) else { return }
        savedRecipeErrorMessage = nil
        do {
            try await removeSavedRecipeUseCase.execute(id: recipe.id)
            recipes.removeAll { $0.id == recipe.id }
            savedRecipeIDs.remove(recipe.id)
            savedRecipeThumbnails[recipe.id] = nil
            savedRecipeHeroImages[recipe.id] = nil
            thumbnailCache.remove(recipe.id)
            heroImageCache.remove(recipe.id)
            recipeIDsWithoutPhoto.remove(recipe.id)
            feasibilityResults[recipe.id] = nil
        } catch {
            savedRecipeErrorMessage = (error as? SaveOnlineRecipeError)?.errorDescription
                ?? SaveOnlineRecipeError.removeFailed.errorDescription
        }
    }

    /// The decoded list-sized thumbnail of `recipe`'s stored photo, if it has
    /// one. What the catalogue rows draw.
    func thumbnail(for recipe: Recipe) -> UIImage? {
        savedRecipeThumbnails[recipe.id] ?? bundledPhoto(for: recipe)
    }

    /// The photo for the detail hero: the hero-sized copy once it is decoded,
    /// and the list thumbnail until then, so the screen never opens empty and
    /// then flashes.
    func heroImage(for recipe: Recipe) -> UIImage? {
        savedRecipeHeroImages[recipe.id] ?? savedRecipeThumbnails[recipe.id] ?? bundledPhoto(for: recipe)
    }

    // bundled recipes get their photo from Assets.xcassets. anything with its own
    // remote photo (saved from Discover) is left alone so the bundled one never
    // shows in front of the real one while it's still loading
    private func bundledPhoto(for recipe: Recipe) -> UIImage? {
        guard recipe.imageURL == nil else { return nil }
        return BundledPhotoAssets.recipePhoto(for: recipe)
    }

    /// Decodes `recipe`'s stored photo at hero resolution, once. Called by the
    /// detail screen; a no-op for bundled recipes, for a recipe with no stored
    /// photo, and on every visit after the first.
    func loadHeroImage(for recipe: Recipe) async {
        guard let savedRecipeRepository,
              savedRecipeIDs.contains(recipe.id),
              savedRecipeHeroImages[recipe.id] == nil,
              !recipeIDsWithoutPhoto.contains(recipe.id)
        else { return }

        if let cached = heroImageCache.image(for: recipe.id) {
            savedRecipeHeroImages[recipe.id] = cached
            return
        }
        guard let stored = try? await savedRecipeRepository.imageData(forRecipeID: recipe.id) else { return }
        guard let image = await RecipeThumbnailDecoder.thumbnails(
            from: [recipe.id: stored],
            maxPixelSize: RecipeThumbnailDecoder.heroPixelSize
        )[recipe.id] else { return }

        heroImageCache.insert(image, for: recipe.id)
        savedRecipeHeroImages[recipe.id] = image
    }

    private func loadSavedRecipeImages(for recipes: [Recipe]) async {
        guard savedRecipeRepository != nil else {
            savedRecipeThumbnails = [:]
            savedRecipeHeroImages = [:]
            return
        }
        savedRecipeThumbnails = await thumbnails(for: recipes.map(\.id))
    }

    /// Thumbnails for `ids`: cached ones are reused as-is; everything else is
    /// read from the store in **one** batch call and decoded concurrently
    /// off the main thread, then cached. Recipes known to have no photo are
    /// not asked for again.
    private func thumbnails(for ids: [UUID]) async -> [UUID: UIImage] {
        guard let savedRecipeRepository else { return [:] }

        var result: [UUID: UIImage] = [:]
        var toFetch: [UUID] = []
        for id in ids {
            if let cached = thumbnailCache.image(for: id) {
                result[id] = cached
            } else if !recipeIDsWithoutPhoto.contains(id) {
                toFetch.append(id)
            }
        }
        guard !toFetch.isEmpty,
              let stored = try? await savedRecipeRepository.imageData(forRecipeIDs: toFetch)
        else { return result }

        let decoded = await RecipeThumbnailDecoder.thumbnails(from: stored)
        for id in toFetch {
            if let image = decoded[id] {
                thumbnailCache.insert(image, for: id)
                result[id] = image
            } else if stored[id] == nil {
                recipeIDsWithoutPhoto.insert(id)
            }
        }
        return result
    }

    /// Re-evaluates every already-loaded recipe against the current
    /// pantry, without re-fetching the recipe list. Call after returning
    /// from Pantry, or on a manual pull-to-refresh.
    func refreshFeasibility() async {
        var results: [UUID: RecipeFeasibilityResult] = [:]
        for recipe in recipes {
            if let result = try? await evaluateFeasibilityUseCase.execute(recipe: recipe) {
                results[recipe.id] = result
            }
        }
        feasibilityResults = results
    }

    /// Evaluates `recipe` only if it isn't already cached - used by the
    /// detail screen as a defensive fallback in case it's opened before
    /// the list's own evaluation finishes.
    func evaluateIfNeeded(_ recipe: Recipe) async {
        guard feasibilityResults[recipe.id] == nil else { return }
        if let result = try? await evaluateFeasibilityUseCase.execute(recipe: recipe) {
            feasibilityResults[recipe.id] = result
        }
    }

    func feasibility(for recipe: Recipe) -> RecipeFeasibilityResult? {
        feasibilityResults[recipe.id]
    }
}
