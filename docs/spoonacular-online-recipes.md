# Spoonacular online recipes (Discover)

Online recipe search is **switched on** (it needs a key in the gitignored
`Secrets.xcconfig`). Saving online recipes to Firestore is still **switched
off**, pending rules deployment. Each is a separate switch with its own
prerequisite.

The app builds, launches and is fully usable with no Spoonacular API key.

## Current state

| Capability | State | Gate |
|---|---|---|
| Browse the Discover tab | On | — |
| Online recipe search | **On** (needs `SPOONACULAR_API_KEY` in `Secrets.xcconfig`) | `OnlineRecipeFeature.provider` |
| Save a recipe to the Recipes tab | **Off** | `OnlineRecipeFeature.savedRecipeStorage` |
| Saved recipes in context-aware recommendations | Wired, inert while saving is off | `CompositeRecipeRepository` |
| Apple Intelligence Pantry Ideas | On, unchanged | — |

While the provider is off, no `SpoonacularRecipeService` is ever
constructed - the composition root returns `UnconfiguredOnlineRecipeService`
without reading an API key at all. There is no object in the process capable
of issuing a request. Discover renders a "Not set up yet" explanation and its
search control is visibly disabled.

## Enabling online search later

Three steps, in order. Steps 1 and 2 are both required; neither alone changes
behaviour.

1. **Obtain a key** from <https://spoonacular.com/food-api/console#Dashboard>
   and put it in `Secrets.xcconfig` (gitignored) as:

   ```
   SPOONACULAR_API_KEY = <your key>
   ```

   `Secrets.xcconfig.example` carries the commented template. `Info.plist`
   already references `$(SPOONACULAR_API_KEY)`; no key value is committed
   anywhere in this repository.

2. **Flip the gate** in `FridgeFit/Data/OnlineRecipeFeature.swift`:

   ```swift
   static let provider: ProviderState = .enabled
   ```

3. **Rebuild.** If the key is missing, blank, or still the unexpanded
   `$(SPOONACULAR_API_KEY)` placeholder, `SpoonacularConfiguration.load()`
   returns `nil` and Discover reports itself as not configured rather than
   failing. No extra error handling is needed.

`OnlineRecipeFeatureTests.test_shippedProviderState_isEnabled` (formerly
`..._isDisabled`) pins this value, so it can't change by accident; it was
updated deliberately when step 2 was done.

### Before enabling, settle these

- **Rotate the credential.** The original feature branch
  (`feature/spoonacular-online-recipes`, commit `887ec88`) committed a live
  key to `FridgeFit/Info.plist` and pushed it to GitHub. That commit is **not**
  in this branch's history and the key is not in this repository, but it must
  be treated as public and rotated at the provider. Handled outside this
  branch.
- **Decide on a backend proxy.** A key placed in an iOS bundle is extractable
  from the shipped binary. The xcconfig route keeps it out of git; it does not
  keep it out of the app. A proxy is the only way to keep it private in
  production, and would also give server-side caching and quota control.
- **Quota and cost.** UNKNOWN. `complexSearch` is requested with
  `addRecipeInformation`, `addRecipeInstructions` and `fillIngredients`, which
  is a compound request costing more than a bare search. The per-point cost,
  daily caps and tier pricing have not been verified and are not guessed at
  anywhere in this code.
- **Licensing.** UNKNOWN, and worth settling before saving is enabled:
  `FirestoreSavedRecipeRepository` persists recipe titles, summaries,
  ingredients and full instruction steps server-side. Whether the provider's
  terms permit that storage, the on-device offline cache, CDN image
  hotlinking, and commercial use has not been verified. Attribution
  ("Recipe data powered by Spoonacular") is present on Discover, the recipe
  detail screen, and every saved recipe's summary.

## Enabling saved recipes later

Separate switch, separate prerequisite.

1. **Deploy the Firestore rules.** `firestore.rules` already grants
   `users/{uid}/savedRecipes/{recipeId}` via the existing `isOwner(uid)`
   helper, but the *deployed* rules still end in default-deny. Deploy, then
   run `npm test` in `firestore-tests/` against the project to confirm.
2. **Flip the gate** in `OnlineRecipeFeature.swift`:

   ```swift
   static let savedRecipeStorage: SavedRecipeStorageState = .enabled
   ```

Until then `makeSavedRecipeRepository()` returns `nil`,
`RecipeViewModel.canSaveRecipes` is `false`, and the detail screen shows the
reason instead of a Save button. That ordering is the point: there is no
user-facing save action that would fail with `permission-denied`.

## Use-it-up-first ranking

Discover results that use pantry items close to expiry rank first.

- Urgency comes from `ExpiryService` - today, tomorrow, or within 3 days -
  the same rule as the Kitchen tab's "Use First" and the context-aware
  recommendations.
- Ranking happens in the app after the search
  (`OnlineRecipeExpiryRanking`), so it costs no extra quota. Near-expiry
  names are also sent first in `includeIngredients`.
- Recipes that would use an **expired** item sink to the bottom rather than
  rising, and say so.
- A provider ingredient name credits a pantry item only on a conservative
  match (normalised, case-folded, last-word plural fold). No substring or
  synonym matching, for the same reason as `OnlineIngredientName`: "coconut
  milk" must never claim to use up the user's milk.
- Order otherwise: most urgent item, then number of urgent items, then
  fewest missing, then most used, then the provider's order.

## Keeping broken recipes out

Two layers, both checked before any ranking or safety filtering:

| Layer | Scope | Where |
|---|---|---|
| Team blocklist | Every user | `FridgeFit/Resources/blocked_online_recipes.json` |
| "Hide" (swipe left, or ⋯ on the detail screen) | This device | `UserDefaults`, via `HiddenOnlineRecipeStoring` |

**When testing finds a broken recipe:** open it, copy the "Spoonacular recipe
ID" shown at the bottom of the detail screen, and add an entry with a
specific reason:

```json
{ "recipes": [
  { "id": 716429, "reason": "steps describe a different dish" }
] }
```

A malformed file is ignored (empty list) rather than breaking Discover; a
unit test checks the shipped file is valid JSON. "Show hidden recipes again"
restores only the user's own hidden recipes, never blocklisted ones.

## How it fits the existing architecture

```
Bundled recipes ─┐
                 ├─> CompositeRecipeRepository ─> GenerateContextAwareRecommendationsUseCase
Saved recipes  ──┘        (dedupes by Recipe.id)        (unchanged)
```

`SaveOnlineRecipeUseCase` converts an `OnlineRecipe` into an ordinary
`Recipe` at the boundary. Everything downstream - quantity-aware feasibility,
expiry-aware suitability, context filtering, ranking reasons, session
feedback - is `main`'s existing code, unmodified. There is no second
recommendation engine.

`CompositeRecipeRepository` takes the bundled catalogue as its *primary*
source and the saved store as *supplementary*: a primary failure propagates,
a supplementary failure degrades to bundled-only rather than breaking the
recommendation screen. With saving gated off it behaves identically to the
bundled repository alone, which is why wiring it in now is a no-op.

### What is deliberately not carried across

`SaveOnlineRecipeUseCase` populates `totalCookingTimeInMinutes` from the
provider's `readyInMinutes` - a stated duration, used only for ranking credit.
It leaves `dietaryLabels`, `cuisine`, `tastePreferences` and `difficulty`
`nil`:

- A provider diet string is a provider claim, not a FridgeFit assessment.
  `DietaryCompliance` reports `nil` labels as `.unknown`, so a saved online
  recipe is withheld whenever the user has selected a dietary restriction -
  exactly as an unlabelled bundled recipe is. Unknown stays unknown.
- `Cuisine` is a closed five-case vocabulary; mapping arbitrary provider
  strings onto it would be guessing, and an unstated cuisine costs a recipe
  nothing but ranking credit.

## Allergen policy

This feature follows the standard `main` set in `DietaryRestriction`, rather
than the source branch's.

- `FoodIntolerance.assessmentBasis` splits the list the same way
  `DietaryRestriction` does. Composition-grade intolerances (dairy, egg,
  grain, seafood, sesame, shellfish, soy) are selectable. Provenance-grade
  ones (gluten, wheat, peanut, tree nut, sulfite) are **not** - they appear in
  the Filters screen's non-selectable "Not matched by FridgeFit" section with
  the reason, mirroring how `CookingContextFormView` treats gluten-free and
  nut-free.
- `DietPreference` has no gluten-free option, for the same reason.
- `RecipeIntoleranceAnalysis` consults **no provider booleans**. The source
  branch used Spoonacular's `glutenFree` / `dairyFree` / `vegan` /
  `vegetarian` flags to clear allergens its own keyword screen had found;
  those fields are no longer decoded, so no provider claim can override
  FridgeFit's uncertainty. The only thing that clears a keyword hit is a
  compositional fact about the ingredient (almond milk is not dairy), each
  one covered by a test.
- Matching is by whole word, not substring. The source reported aubergine as
  egg, butternut as dairy and crabapple as shellfish.
- Preferences are sanitised on load and before every search, so a filter
  stored by an older build cannot reinstate a check the app does not perform.
- `containsIntolerances == nil` means *unscreened* and fails closed: the
  recipe is dropped for anyone with an intolerance set. The detail screen says
  a clear result is a keyword screen of ingredient names, not a safety check.

## Ingredient name matching

`OnlineIngredientName` does only what cannot change an ingredient's identity:
trim, drop parenthetical asides, collapse whitespace. It deliberately does
**not** singularise or strip preparation words.

Folding "garlic cloves" onto "garlic" would make the feasibility engine report
an ingredient the user may not have - turning a name heuristic into a quantity
claim, which the engine is built never to do. Under-matching is visible and
honest; over-matching is invisible and wrong.

Cross-vocabulary matching remains an open problem. A saved online recipe will
often read as missing an ingredient the user actually has.
`OnlineRecipeIngredient.providerID` is captured and carried through for that
future work: the provider's ingredient id is a better key for a reviewed
mapping table than any string rule.

## Testing

```bash
# Swift suites (no network, no Firestore)
xcodebuild test -scheme FridgeFit -destination 'platform=iOS Simulator,name=iPhone 17'

# Firestore rules, against the emulator
cd firestore-tests && npm test
```

Everything runs on `MockOnlineRecipeService`, `InMemorySavedRecipeRepository`
and `InMemoryPantryRepository`. No test requires a provider key or production
Firestore access, and mock results are never shown in the production app -
the mocks exist only in the test target and SwiftUI previews.

## Still outstanding

- Interactive UI verification on a device or simulator **behind sign-in**: the
  five-tab bar, Discover's disabled search control, the Filters sheet, and the
  swipe-to-remove action on saved recipes. The headless rendering tests
  evaluate view bodies but not taps, sheet presentation or navigation pushes,
  and this project has no UI test target.
- Provider quota, pricing and licensing verification (above).
- Credential rotation for the leaked key on the original branch (above).
- Firestore rules deployment (above).
