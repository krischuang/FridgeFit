# FridgeFit Feature Progress Audit

**Project:** FridgeFit (iOS (SwiftUI))  
**Audit date:** 2026-10-11  
**Commit audited:** `65d2b60` on `main`  
**Working tree:** 1 uncommitted change: FridgeFit.xcodeproj/project.pbxproj (adds DEVELOPMENT_TEAM)  
**Method:** Static source audit + local test execution

---

## ⚠️ Read this first: the specification was not available

The Notion Feature List could not be read. No requirement IDs, names, acceptance criteria, sections or priorities from Notion are present in this dataset. Every requirement below was DERIVED by the auditor from the source code, git history and in-code documentation. It is a provisional baseline for discussion, NOT the project specification. Requirement IDs are prefixed 'CD-' (code-derived) specifically so they cannot be mistaken for Notion IDs.

**Consequences for this document, stated plainly:**

| Consequence | Why |
|---|---|
| No overall completion percentage against spec | A requirement nobody implemented leaves no code trace to derive, so the denominator would be wrong in the one direction that flatters the project. |
| Section *Not Started* may be incomplete | It lists requirements this auditor inferred *should* exist. Notion requirements with zero implementation are invisible here by construction. |
| Priorities are the auditor's judgement | Notion's own stated priorities and acceptance criteria were not read. |
| Requirement IDs are prefixed `CD-` | Code-derived. Deliberately chosen so they cannot be mistaken for Notion IDs. |

Everything about the **codebase** below is first-hand evidence and is cited to file and line. Everything about **requirements** is provisional. Those are two different confidence levels and this document keeps them apart.

### Source availability

| Source | Status | Detail |
|---|---|---|
| Notion Feature List (Source A) | ❌ Inaccessible | HTTPS GET of https://app.notion.com/p/Feature-List-3b96f7ba99b48029ba51de5a17531e72 returns HTTP 200 but serves only the Notion single-page-application shell; no page content is delivered to an unauthenticated fetch. The www.notion.so form 307-redirects to the same app.notion.com URL. A POST to Notion's private loadPageChunk API returned no response (blocked). No Notion MCP connector or integration token is configured in this session. |
| Exported requirements in repository | ❌ Absent | Repository contains no Markdown, CSV, PDF, DOCX or plain-text requirements document. A full-tree search for non-source files returned only firebase.json, firestore.indexes.json and Asset catalogue Contents.json. No README, no docs/ directory prior to this audit. The sibling FridgeFit.zip in the parent directory is an archive of this same repository and contains no requirements document either. |
| FridgeFit Xcode project (Source B) | ✅ Available | Full recursive read of 89 production Swift files (7,760 lines) and 25 test files (3,472 lines), plus Config.xcconfig, Secrets.example.xcconfig, Info.plist, firestore.rules, firebase.json, .gitignore and FridgeFit.xcodeproj/project.pbxproj. 26 commits of git history reviewed. |
| Local build and test execution | ✅ Available | Xcode 26.1 (17B55) with iOS 26.1 simulator SDK and an iPhone 17 Pro (iOS 26.1) simulator present, matching the project's IPHONEOS_DEPLOYMENT_TARGET of 26.1. The unit test suite was executed on this simulator; the result is recorded in the testExecution block. |

---

## A. Executive overview

FridgeFit is an iOS application that tracks what a user actually has in their kitchen and tells them what they can cook with it. A user signs in, builds a pantry — by hand or by photographing a grocery receipt — and the app evaluates every recipe against that pantry to answer one question: *can I make this?* Three features use generative AI to reduce the manual work: on-device receipt reading, on-device recipe ideas generated from the pantry, and remote ingredient substitution suggestions.

**What the audit found.** The codebase is small, coherent and unusually disciplined. 7,760 lines of production Swift across 89 files are organised into a genuine SwiftUI / MVVM / Use Case / Repository separation where the layering is real rather than nominal: views collect input, view models map state, and every rule lives in a use case behind a protocol with a test double. The 3,472-line test suite was executed as part of this audit — **240 tests, 0 failures, 0 skipped, `TEST SUCCEEDED`** — and its coverage is weighted toward the riskiest logic rather than spread evenly.

The strongest property in the codebase is architectural: **no generative model is permitted to assert pantry state.** Model output enters as an untrusted `Raw*` value and must pass a deterministic validator before any view sees it. Receipt items whose echoed source line was never sent are discarded outright, which is the hard stop on invented groceries. Each of the three AI features has a test asserting that adversarial case by name.

**The gap is not code quality — it is evidence.** Every one of the 240 tests runs against a double. The audit found no test, and produced no runtime observation, touching any of the four production integrations: Firebase Auth, Cloud Firestore, Apple Foundation Models, or OpenRouter. Two features are hardware-gated and cannot run on a simulator at all. One feature — ingredient substitution — is non-functional in this checkout because the gitignored `Secrets.xcconfig` is absent, so it falls back to an explicit *not configured* error. That is why **14 requirements are marked Needs Verification and 1 Blocked**: the implementation reads correct, and correctness was not established.

### KPI summary

| Metric | Value |
|---|---|
| Requirements identified (code-derived baseline) | **65** |
| ✅ Completed | **22** |
| 🟡 Partially Completed | **6** |
| 🔍 Needs Verification | **14** |
| 🚧 Blocked | **1** |
| ⬜ Not Started | **22** |
| Automated tests executed / passed | **240 / 240** |
| Overall completion vs. specification | **Not calculable** — see below |

#### How the numbers were calculated

**Overall completion against the specification: not calculable.** Not calculable. A completion percentage against the specification requires the authoritative requirement set, which was inaccessible. Any percentage computed against the code-derived baseline measures the code against itself and would systematically hide requirements that were never implemented (a requirement nobody built leaves no code trace to derive).

**Code-derived baseline coverage: 22/65 = 33.8%.**  
Method: `count(status == 'completed') / count(all code-derived requirements)`.  
⚠️ Denominator is the code-derived baseline, not the Notion requirement count. This figure describes the maturity of what was found in the repository; it is not the project's completion against spec.

The honest reading of this report is the *status distribution*, not any single percentage: 22 requirements are done and test-verified, 6 are partly done, 15 are built but unproven, and 22 have no implementation.

---

## B. Implementation progress by category

| Category | Total | ✅ Completed | 🟡 Partially Completed | 🔍 Needs Verification | 🚧 Blocked | ⬜ Not Started |
|---|---:|---:|---:|---:|---:|---:|
| **Authentication** | 9 | 0 | 1 | 5 | 0 | 3 |
| **Pantry Management** | 10 | 5 | 0 | 2 | 0 | 3 |
| **Recipe Management** | 9 | 3 | 1 | 0 | 0 | 5 |
| **AI Recipe Suggestions** | 4 | 2 | 0 | 1 | 0 | 1 |
| **Receipt Scanning** | 11 | 6 | 1 | 3 | 1 | 0 |
| **Ingredient Substitution** | 6 | 2 | 2 | 1 | 0 | 1 |
| **User Profile** | 6 | 1 | 0 | 1 | 0 | 4 |
| **Testing & Infrastructure** | 10 | 3 | 1 | 1 | 0 | 5 |
| **Total** | **65** | **22** | **6** | **14** | **1** | **22** |

**Reading the shape of this table.** Receipt Scanning and Pantry Management carry the most completed requirements, which matches where the test suite is concentrated. Authentication is the outlier: nine requirements, zero completed, five needing verification — it is the only feature area with no automated coverage at all, a direct consequence of `AuthViewModel` calling the `Auth.auth()` singleton directly instead of depending on a protocol like every other view model in the project. User Profile is the thinnest area: four of six requirements have no implementation, and the screen is 37 lines holding an icon, one line of text and a sign-out button.

---

## C. Completed features (22)

Implemented, wired into the UI, and exercised by tests that were executed in this audit. Caveats are recorded where a requirement is satisfied but something adjacent is worth knowing.

### Pantry Management

#### ✅ `CD-PANTRY-01` — View the pantry

**Priority:** P0 · **Integration:** `production`

*The signed-in user sees everything currently in their pantry, with category, icon and formatted quantity, plus a distinct loading state, empty state and pull-to-refresh.*

**Implementation evidence.** PantryView renders a ProgressView while loading-and-empty, a ContentUnavailableView with Scan Receipt and Add Ingredient actions when genuinely empty, and otherwise an inset-grouped List of rows carrying a tinted category IconBadge, name, category and monospaced-digit quantity. Rows are accessibility-combined with an explicit label and hint. .task loads on appear and .refreshable reloads on pull. PantryViewModel.loadItems toggles isLoading and maps failure into errorMessage.

**Source files.** `FridgeFit/Views/Pantry/PantryView.swift:19`, `FridgeFit/ViewModels/PantryViewModel.swift:39`, `FridgeFit/Views/Support/PantryPresentation.swift:22`

**Tests (1, all passing).**

- `FridgeFitTests/ViewModels/PantryViewModelTests.swift: test_pantryViewModel_loadItems_loadsSeededItems`

**Remaining work.** None.

**Risks.** None identified.

**Caveats.** The load-error alert is suppressed while any sheet is presented, so a failure that occurs behind a sheet is shown only after dismissal.

#### ✅ `CD-PANTRY-02` — Add a pantry item with validation

**Priority:** P0 · **Integration:** `production`

*The user adds an ingredient by name, category, quantity and unit. Blank names and negative quantities are rejected with a message written for the user.*

**Implementation evidence.** AddPantryItemView is a pure form; AddPantryItemUseCase.execute trims the name, rejects empty with .emptyIngredientName, rejects quantity < 0 with .invalidQuantity, then constructs the PantryItem and persists it. A non-numeric quantity field becomes -1 in the view and is therefore rejected by the same rule rather than by a second one. Validation sits in the use case, so no caller can bypass it.

**Source files.** `FridgeFit/UseCases/AddPantryItemUseCase.swift:34`, `FridgeFit/Views/Pantry/AddPantryItemView.swift:80`, `FridgeFit/Domain/Errors/AddPantryItemError.swift:11`

**Tests (5, all passing).**

- `FridgeFitTests/UseCases/AddPantryItemUseCaseTests.swift: test_addPantryItem_succeeds_withValidNameAndQuantity`
- `FridgeFitTests/UseCases/AddPantryItemUseCaseTests.swift: test_addPantryItem_succeeds_withZeroQuantity`
- `FridgeFitTests/UseCases/AddPantryItemUseCaseTests.swift: test_addPantryItem_fails_whenIngredientNameIsEmpty`
- `FridgeFitTests/UseCases/AddPantryItemUseCaseTests.swift: test_addPantryItem_fails_whenQuantityIsNegative`
- `FridgeFitTests/ViewModels/PantryViewModelTests.swift: test_pantryViewModel_addItem_appendsNewItem_andClearsErrorMessage`

**Remaining work.** None.

**Risks.** None identified.

**Caveats.** Quantity zero is deliberately allowed ('I have none left but still track it'), which is asserted by a dedicated test.

#### ✅ `CD-PANTRY-03` — Duplicate prevention with guided recovery

**Priority:** P1 · **Integration:** `production`

*Adding an ingredient the pantry already holds is rejected rather than silently merged, and the user is offered the update-the-existing-item path instead.*

**Implementation evidence.** AddPantryItemUseCase matches against the existing pantry with Ingredient.matches(name:) (trimmed, case-insensitive) and throws .duplicateIngredient(name:). PantryViewModel catches that specific case and publishes duplicateItem; AddPantryItemView then renders an 'Update Existing Quantity' button which hands the item back to PantryView to present UpdatePantryItemView.

**Source files.** `FridgeFit/UseCases/AddPantryItemUseCase.swift:42`, `FridgeFit/ViewModels/PantryViewModel.swift:58`, `FridgeFit/Views/Pantry/AddPantryItemView.swift:52`, `FridgeFit/Domain/Models/Ingredient.swift:26`

**Tests (4, all passing).**

- `FridgeFitTests/UseCases/AddPantryItemUseCaseTests.swift: test_addPantryItem_fails_whenIngredientAlreadyExists`
- `FridgeFitTests/UseCases/AddPantryItemUseCaseTests.swift: test_addPantryItem_treatsNamesCaseInsensitively_asDuplicates`
- `FridgeFitTests/ViewModels/PantryViewModelTests.swift: test_pantryViewModel_addItem_setsHumanReadableErrorMessage_whenDuplicate`
- `FridgeFitTests/ViewModels/PantryViewModelTests.swift: test_pantryViewModel_addItem_exposesDuplicateItem_forGuidedRecovery`

**Remaining work.** None.

**Risks.** None identified.

**Caveats.** Matching is on the display name only. The canonical identity produced by IngredientCanonicalizer during a receipt scan is not used for pantry duplicate detection, so a hand-typed 'Bell Pepper' and a scanned 'Red Capsicum' are two pantry rows even though the scanner knows they are one ingredient. This is a real inconsistency worth a decision.

#### ✅ `CD-PANTRY-04` — Update an item's quantity and unit

**Priority:** P0 · **Integration:** `production`

*The user corrects how much of an ingredient they have, and in what unit.*

**Implementation evidence.** Tapping a row sets editingItem and presents UpdatePantryItemView pre-filled from the item. UpdatePantryItemUseCase re-applies the quantity rule, resolves the item by id, mutates quantity and unit, and persists through the repository, throwing .itemNotFound if it vanished in between.

**Source files.** `FridgeFit/UseCases/UpdatePantryItemUseCase.swift:22`, `FridgeFit/Views/Pantry/UpdatePantryItemView.swift:63`, `FridgeFit/ViewModels/PantryViewModel.swift:70`

**Tests (5, all passing).**

- `FridgeFitTests/UseCases/UpdatePantryItemUseCaseTests.swift: test_updatePantryItem_succeeds_withValidQuantity`
- `FridgeFitTests/UseCases/UpdatePantryItemUseCaseTests.swift: test_updatePantryItem_fails_whenQuantityIsNegative`
- `FridgeFitTests/UseCases/UpdatePantryItemUseCaseTests.swift: test_updatePantryItem_fails_whenItemNoLongerExists`
- `FridgeFitTests/ViewModels/PantryViewModelTests.swift: test_pantryViewModel_updateQuantity_changesExistingItem_andClearsErrorMessage`
- `FridgeFitTests/ViewModels/PantryViewModelTests.swift: test_pantryViewModel_updateQuantity_setsErrorMessage_whenQuantityIsInvalid`

**Remaining work.** None.

**Risks.** None identified.

**Caveats.** UpdatePantryItemView seeds its text field by splitting item.formattedQuantity on a space, so a fractional quantity arrives pre-rounded to one decimal place by MeasurementUnit.formatted. Saving an untouched form can therefore write back a slightly rounded value. Minor, but real.

#### ✅ `CD-PANTRY-05` — Remove a pantry item

**Priority:** P0 · **Integration:** `production`

*The user removes an ingredient they have used up, with a distinct error if it was already gone.*

**Implementation evidence.** PantryView's List uses .onDelete; RemovePantryItemUseCase verifies presence first and throws .pantryItemNotFound rather than treating a missing item as a silent no-op. PantryViewModel routes that into removalErrorMessage, which is a separate published property from errorMessage specifically so a removal alert cannot collide with a form's inline error; the alert's OK handler reloads the list.

**Source files.** `FridgeFit/UseCases/RemovePantryItemUseCase.swift:22`, `FridgeFit/Views/Pantry/PantryView.swift:157`, `FridgeFit/ViewModels/PantryViewModel.swift:82`

**Tests (4, all passing).**

- `FridgeFitTests/UseCases/RemovePantryItemUseCaseTests.swift: test_removePantryItem_succeeds_whenItemExists`
- `FridgeFitTests/UseCases/RemovePantryItemUseCaseTests.swift: test_removePantryItem_fails_whenItemNoLongerExists`
- `FridgeFitTests/ViewModels/PantryViewModelTests.swift: test_pantryViewModel_removeItem_removesFromItems`
- `FridgeFitTests/ViewModels/PantryViewModelTests.swift: test_pantryViewModel_removeItem_setsHumanReadableErrorMessage_whenItemNoLongerExists`

**Remaining work.** None.

**Risks.** removeItems(at:) spawns one unstructured Task per offset and each reloads the list on completion. Deleting several rows in one gesture therefore issues concurrent deletes and interleaved reloads. The repository operations are id-scoped so the end state is correct, but the intermediate list can flicker and the reloads are redundant.

**Caveats.** Not a correctness defect; worth tidying if multi-row deletion is a common path.

### Recipe Management

#### ✅ `CD-RECIPE-01` — Browse recipes

**Priority:** P0 · **Integration:** `production-local-dataset`

*The user browses a list of recipes, each showing a feasibility badge and pantry coverage at a glance.*

**Implementation evidence.** RecipeListView renders a List of RecipeRow, each with a feasibility-tinted IconBadge, the status title, matched/total counts and a coverage percentage, falling back to 'Checking pantry…' before evaluation completes. It has a loading state, a ContentUnavailableView empty state, pull-to-refresh bound to refreshFeasibility, and an error alert. RecipeViewModel.loadRecipes fetches through the RecipeRepository protocol and then evaluates every recipe.

**Source files.** `FridgeFit/Views/Recipes/RecipeListView.swift:28`, `FridgeFit/ViewModels/RecipeViewModel.swift:36`, `FridgeFit/Views/Support/RecipePresentation.swift:30`

**Tests (4, all passing).**

- `FridgeFitTests/ViewModels/RecipeViewModelTests.swift: test_loadRecipes_populatesRecipesAndClearsErrorMessage`
- `FridgeFitTests/ViewModels/RecipeViewModelTests.swift: test_loadRecipes_alsoEvaluatesFeasibilityForEachRecipe`
- `FridgeFitTests/Data/RecipeRepositoryTests.swift: test_bundledRecipeRepository_loadsAtLeastTenRecipes`
- `FridgeFitTests/Data/RecipeRepositoryTests.swift: test_bundledRecipeRepository_recipesHaveIngredientsAndInstructions`

**Remaining work.** None for this requirement; the data source is tracked separately as CD-RECIPE-05.

**Risks.** RecipeListView calls loadRecipes from .onAppear, which fires on every tab return and re-fetches and re-evaluates the whole list each time. Harmless with 10 bundled recipes; it would need rethinking against a remote catalogue.

**Caveats.** The catalogue is 10 hard-coded recipes compiled into the binary (BundledRecipeRepository.sampleRecipes). The code documents this as a phase decision and the RecipeRepository protocol is the seam for a remote source, but a reviewer should not read 'recipe browsing works' as 'a recipe backend exists'.

#### ✅ `CD-RECIPE-02` — Recipe detail with ingredients and instructions

**Priority:** P0 · **Integration:** `production`

*A recipe's full detail shows its summary, servings, each ingredient compared against the pantry, and numbered cooking steps.*

**Implementation evidence.** RecipeDetailView renders summary and servings, a Feasibility section with status and coverage, an Ingredients section of RecipeIngredientRow built from the evaluated result, and numbered Instructions. RecipeIngredientRow renders availability-specific detail text — on-hand versus required, 'Need N more', 'Optional, missing', or 'Check amount' — and renders unresolved optional ingredients in a muted style so they cannot be mistaken for blockers. .task calls evaluateIfNeeded as a defensive fallback if the detail opens before the list's evaluation lands.

**Source files.** `FridgeFit/Views/Recipes/RecipeDetailView.swift:24`, `FridgeFit/Views/Support/RecipePresentation.swift:76`, `FridgeFit/ViewModels/RecipeViewModel.swift:64`

**Tests (2, all passing).**

- `FridgeFitTests/ViewModels/RecipeViewModelTests.swift: test_evaluateIfNeeded_evaluatesOnlyWhenNotAlreadyCached`
- `FridgeFitTests/ViewModels/RecipeViewModelTests.swift: test_feasibility_forUnknownRecipe_returnsNil`

**Remaining work.** None.

**Risks.** None identified.

**Caveats.** No images (see CD-RECIPE-07), no serving-size scaling, and no step-by-step cooking mode.

#### ✅ `CD-RECIPE-03` — Recipe feasibility evaluation against the pantry

**Priority:** P0 · **Integration:** `production`

*FridgeFit answers 'can I make this?' deterministically from the current pantry, distinguishing makeable, almost makeable and not makeable, and reporting coverage of essential ingredients.*

**Implementation evidence.** EvaluateRecipeFeasibilityUseCase reads the pantry fresh on every call and classifies each ingredient as available, insufficient, missing, or quantityUnverified when the units cannot be safely converted — failing closed rather than guessing. Matching is by normalised name via Ingredient.matches(name:), the same rule Pantry uses, because recipe and pantry ids are generated independently and could never match. Status is a single documented rule: all essential available -> makeable; at least half available -> almostMakeable; otherwise notMakeable; a recipe with no essential ingredients is trivially makeable. Optional ingredients never affect the verdict. RecipeFeasibilityResult exposes the derived groupings and coveragePercentage so list row, detail screen and tests read one verdict.

**Source files.** `FridgeFit/UseCases/EvaluateRecipeFeasibilityUseCase.swift:28`, `FridgeFit/UseCases/EvaluateRecipeFeasibilityUseCase.swift:61`, `FridgeFit/Domain/Models/RecipeFeasibilityResult.swift:61`, `FridgeFit/Domain/Models/IngredientAvailability.swift:16`

**Tests (17, all passing).**

- `FridgeFitTests/UseCases/EvaluateRecipeFeasibilityUseCaseTests.swift: test_scenario1_fullPantry_isMakeable_with100PercentCoverage`
- `FridgeFitTests/UseCases/EvaluateRecipeFeasibilityUseCaseTests.swift: test_scenario2_missingEssentialIngredient_isReportedAndLowersCoverage`
- `FridgeFitTests/UseCases/EvaluateRecipeFeasibilityUseCaseTests.swift: test_scenario3_kilogramsInPantry_satisfiesGramsRequirement`
- `FridgeFitTests/UseCases/EvaluateRecipeFeasibilityUseCaseTests.swift: test_millilitersToLitersConversion_satisfiesRequirement`
- `FridgeFitTests/UseCases/EvaluateRecipeFeasibilityUseCaseTests.swift: test_scenario4_unrelatedIngredientWithEqualQuantity_doesNotSatisfyRequirement`
- `FridgeFitTests/UseCases/EvaluateRecipeFeasibilityUseCaseTests.swift: test_incompatibleUnitDimensions_sameIngredientName_failsClosedAsUnverified`
- `FridgeFitTests/UseCases/EvaluateRecipeFeasibilityUseCaseTests.swift: test_scenario5_missingOptionalIngredient_doesNotBlockMakeability`
- `FridgeFitTests/UseCases/EvaluateRecipeFeasibilityUseCaseTests.swift: test_exactIngredientMatch_isAvailable`
- `FridgeFitTests/UseCases/EvaluateRecipeFeasibilityUseCaseTests.swift: test_caseInsensitiveMatching`
- `FridgeFitTests/UseCases/EvaluateRecipeFeasibilityUseCaseTests.swift: test_trimmedNameMatching`
- `FridgeFitTests/UseCases/EvaluateRecipeFeasibilityUseCaseTests.swift: test_sufficientQuantity_isAvailable`
- `FridgeFitTests/UseCases/EvaluateRecipeFeasibilityUseCaseTests.swift: test_insufficientQuantity_reportsShortfall`
- `FridgeFitTests/UseCases/EvaluateRecipeFeasibilityUseCaseTests.swift: test_emptyPantry_allEssentialIngredientsMissing_isNotMakeable`
- `FridgeFitTests/UseCases/EvaluateRecipeFeasibilityUseCaseTests.swift: test_multipleMissingIngredients_belowHalfCoverage_isNotMakeable`
- `FridgeFitTests/UseCases/EvaluateRecipeFeasibilityUseCaseTests.swift: test_multipleMissingIngredients_atHalfCoverage_isAlmostMakeable`
- `FridgeFitTests/UseCases/EvaluateRecipeFeasibilityUseCaseTests.swift: test_recipeWithOnlyOptionalIngredients_isTriviallyMakeable`
- `FridgeFitTests/ViewModels/RecipeViewModelTests.swift: test_refreshFeasibility_reflectsPantryChangesSinceLastEvaluation`

**Remaining work.** None.

**Risks.** None identified. This is the most thoroughly tested rule in the codebase: 16 dedicated cases covering each status boundary, both conversion directions, the fail-closed path and the trivial case.

**Caveats.** Name matching is exact-after-normalisation. 'Chicken' in the pantry does not satisfy a recipe's 'Chicken Breast', even though IngredientCanonicalizer would resolve both to 'chicken'. The canonicaliser is used only in the scan pipeline. See CD-PANTRY-03.

### AI Recipe Suggestions

#### ✅ `CD-AI-02` — Pantry-authoritative availability split on suggestions

**Priority:** P0 · **Integration:** `production`

*A suggestion's available-versus-missing ingredient split is computed from the real pantry, never taken from the model, so the app can never tell the user they have something they do not.*

**Implementation evidence.** The @Generable schema deliberately has no 'available' or 'missing' field — the model is asked only what a recipe requires. SuggestRecipesFromPantryUseCase.validate recomputes both lists by matching required names against the real pantry with Ingredient.matches(name:), drops suggestions with a blank name or no ingredients, deduplicates required ingredients case-insensitively, drops suggestions that use nothing from the pantry, and normalises a zero-minute estimate to nil. RawRecipeSuggestion and RecipeSuggestion are separate types precisely so the untrusted and validated shapes cannot be confused.

**Source files.** `FridgeFit/UseCases/SuggestRecipesFromPantryUseCase.swift:65`, `FridgeFit/Data/AppleRecipeSuggestionService.swift:17`, `FridgeFit/Domain/Models/RecipeSuggestion.swift:16`

**Tests (7, all passing).**

- `FridgeFitTests/UseCases/SuggestRecipesFromPantryUseCaseTests.swift: test_suggestRecipes_splitsIngredientsUsingRealPantry`
- `FridgeFitTests/UseCases/SuggestRecipesFromPantryUseCaseTests.swift: test_suggestRecipes_marksIngredientMissing_whenPantryDisagrees`
- `FridgeFitTests/UseCases/SuggestRecipesFromPantryUseCaseTests.swift: test_suggestRecipes_matchesIngredientNamesCaseInsensitively`
- `FridgeFitTests/UseCases/SuggestRecipesFromPantryUseCaseTests.swift: test_suggestRecipes_dropsSuggestionsUsingNothingFromPantry`
- `FridgeFitTests/UseCases/SuggestRecipesFromPantryUseCaseTests.swift: test_suggestRecipes_dropsSuggestionsWithBlankNameOrNoIngredients`
- `FridgeFitTests/UseCases/SuggestRecipesFromPantryUseCaseTests.swift: test_suggestRecipes_deduplicatesRequiredIngredients`
- `FridgeFitTests/UseCases/SuggestRecipesFromPantryUseCaseTests.swift: test_suggestRecipes_treatsZeroMinutesAsNoEstimate`

**Remaining work.** None.

**Risks.** None identified. test_suggestRecipes_marksIngredientMissing_whenPantryDisagrees asserts the adversarial case directly: the model claims availability, the pantry disagrees, and the pantry wins.

**Caveats.** The UI states this to the user in PantryRecipeIdeasView's footer, so the guarantee is visible rather than merely internal.

#### ✅ `CD-AI-03` — Apple Intelligence unavailable-state handling

**Priority:** P0 · **Integration:** `production`

*When Apple Intelligence cannot run, the affected feature explains why in plain language and the rest of the app keeps working.*

**Implementation evidence.** AppleIntelligenceAvailability models five states — available, appleIntelligenceNotEnabled, deviceNotSupported, modelNotReady, unavailableForUnknownReason — each with a user-facing title and explanation that never mentions a framework, and an unrecognised SDK reason maps to unavailableForUnknownReason and fails closed rather than assuming the feature works. Availability is re-read on every access so returning from Settings reflects the new state. PantryRecipeIdeasView and ReceiptScannerView both substitute a ContentUnavailableView and offer the manual path instead. Nothing in Pantry, Recipes or Firebase depends on this type.

**Source files.** `FridgeFit/Domain/Models/AppleIntelligenceAvailability.swift:30`, `FridgeFit/Views/Recipes/PantryRecipeIdeasView.swift:88`, `FridgeFit/Views/Scanner/ReceiptScannerView.swift:196`, `FridgeFit/Data/AppleReceiptIngredientInterpreter.swift:61`

**Tests (5, all passing).**

- `FridgeFitTests/UseCases/SuggestRecipesFromPantryUseCaseTests.swift: test_suggestRecipes_throwsUnavailable_whenModelUnavailable`
- `FridgeFitTests/UseCases/SuggestRecipesFromPantryUseCaseTests.swift: test_loadSuggestions_isBlocked_whenModelUnavailable`
- `FridgeFitTests/UseCases/ScanReceiptUseCaseTests.swift: test_execute_throwsWhenAppleIntelligenceIsUnavailable`
- `FridgeFitTests/UseCases/ScanReceiptUseCaseTests.swift: test_execute_doesNotRunOCR_whenScanningIsUnavailable`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_canScan_isFalse_whenAppleIntelligenceIsUnavailable`

**Remaining work.** None.

**Risks.** None identified. test_execute_doesNotRunOCR_whenScanningIsUnavailable asserts the availability check happens before any work, so an unavailable model does not cause the device to OCR a photo for nothing.

**Caveats.** The mapping from SystemLanguageModel.Availability onto these cases is itself untested (it needs the real SDK type), so the five states are proven to behave correctly once set, but not proven to be set correctly on real hardware.

### Receipt Scanning

#### ✅ `CD-SCAN-03` — Deterministic receipt line parsing

**Priority:** P0 · **Integration:** `production`

*OCR output is reduced to candidate product lines by removing receipt furniture — totals, payment lines, store metadata — and splitting the trailing price off each description, without modifying the original text.*

**Implementation evidence.** ReceiptLineParser is a deliberately weak filter: it removes only what is unambiguously not a product, documenting that a wrongly dropped line is invisible to the user whereas a wrongly kept one costs one extra row the model will triage anyway. Metadata is matched as whole words so CASHEWS survives CASH and CARDAMOM survives CARD; multi-word phrases are matched as consecutive words; ambiguous leading words such as TOTAL are treated as metadata only when nothing alphabetic follows, so 'TOTAL 45.67' is dropped and 'TOTAL GREEK YOGURT 6.00' is kept. Price splitting works on the last whitespace-separated token and requires exactly two decimal places, which keeps 500G and 2L from being read as prices; a trailing tax flag token is tolerated. A leading 5+ digit barcode is stripped. A bare '2 @ $3.00' multiplier line is folded into the previous line rather than discarded. originalText is never modified.

**Source files.** `FridgeFit/Data/ReceiptLineParser.swift:71`, `FridgeFit/Data/ReceiptLineParser.swift:116`, `FridgeFit/Data/ReceiptLineParser.swift:184`, `FridgeFit/Data/ReceiptLineParser.swift:207`

**Tests (19, all passing).**

- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_keepsProductLinesAndDropsReceiptFurniture`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_preservesReadingOrder`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_splitsTrailingPriceFromDescription`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_keepsWeightWhileRemovingPrice`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_handlesCurrencySymbolAndTaxFlag`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_leavesDescriptionIntactWhenThereIsNoPrice`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_priceValue_rejectsWeightsAndPlainNumbers`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_dropsStoreAndPaymentMetadata`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_dropsLinesWithNoLetters`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_keepsProductsThatBeginWithAnAmbiguousKeyword`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_keepsProductsWhoseWordsContainMetadataSubstrings`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_stripsLeadingItemCode`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_keepsShortLeadingNumbers`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_foldsMultiplierContinuationIntoPreviousLine`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_treatsMultiplierWithProductNameAsItsOwnLine`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_originalTextIsNeverModified`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_returnsEmpty_forEmptyOCR`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_returnsEmpty_whenEveryLineIsNoise`
- `FridgeFitTests/Data/ReceiptLineParserTests.swift: test_parse_dropsDescriptionsThatAreTooShort`

**Remaining work.** None.

**Risks.** None identified. The substring-collision cases (CASHEWS/CASH, CARDAMOM/CARD) and the TOTAL-as-brand case are each asserted by a dedicated test.

**Caveats.** The metadata word list is Australian-retailer oriented. A receipt from another market could leak more furniture through — which, by this parser's stated design, is the safe direction to fail.

#### ✅ `CD-SCAN-04` — Deterministic quantity extraction from receipt text

**Priority:** P0 · **Integration:** `production`

*A quantity is read from the receipt line by scanning characters, never inferred, and 'the receipt did not say' is a real answer rather than a default.*

**Implementation evidence.** ReceiptQuantityParser reads weight and volume suffixes (g/gm/gms/gr/grm, kg/kgs, ml/mls, L/lt/ltr), handling both '500G' and '500 G', and prefers weight or volume over a count because '2 @ CHKN 500G' means 500 g of chicken. A count is read only from an explicit '2 @' or '3 x' multiplier shape, deliberately ignoring a bare leading number because on receipts that is as often a line number or PLU as a quantity. Trailing punctuation left by OCR is tolerated. Returning nil is documented as the honest answer, which the UI renders as 'quantity not detected'. ReceiptQuantityParser.text(_:states:) exists specifically so a model-proposed number can be checked against the receipt text.

**Source files.** `FridgeFit/Data/ReceiptQuantityParser.swift:44`, `FridgeFit/Data/ReceiptQuantityParser.swift:92`, `FridgeFit/Data/ReceiptQuantityParser.swift:125`, `FridgeFit/Domain/Models/ReceiptQuantity.swift:14`

**Tests (14, all passing).**

- `FridgeFitTests/Data/ReceiptQuantityParserTests.swift: test_quantity_readsGramsAttachedToNumber`
- `FridgeFitTests/Data/ReceiptQuantityParserTests.swift: test_quantity_readsKilogramsWithDecimal`
- `FridgeFitTests/Data/ReceiptQuantityParserTests.swift: test_quantity_readsLitresAndMillilitres`
- `FridgeFitTests/Data/ReceiptQuantityParserTests.swift: test_quantity_readsUnitSeparatedByASpace`
- `FridgeFitTests/Data/ReceiptQuantityParserTests.swift: test_quantity_isCaseInsensitive`
- `FridgeFitTests/Data/ReceiptQuantityParserTests.swift: test_quantity_returnsNil_whenTheLineStatesNoAmount`
- `FridgeFitTests/Data/ReceiptQuantityParserTests.swift: test_quantity_ignoresPrices`
- `FridgeFitTests/Data/ReceiptQuantityParserTests.swift: test_quantity_ignoresBareLeadingNumbers`
- `FridgeFitTests/Data/ReceiptQuantityParserTests.swift: test_quantity_readsMultiplierAsACountOfPieces`
- `FridgeFitTests/Data/ReceiptQuantityParserTests.swift: test_quantity_prefersWeightOverCount`
- `FridgeFitTests/Data/ReceiptQuantityParserTests.swift: test_splitLeadingNumber_separatesValueFromSuffix`
- `FridgeFitTests/Data/ReceiptQuantityParserTests.swift: test_splitLeadingNumber_doesNotSwallowTrailingPunctuation`
- `FridgeFitTests/Data/ReceiptQuantityParserTests.swift: test_textStates_recognisesNumbersThatAppearInTheLine`
- `FridgeFitTests/Data/ReceiptQuantityParserTests.swift: test_textStates_rejectsNumbersTheLineNeverMentions`

**Remaining work.** None.

**Risks.** None identified.

**Caveats.** Pack counts written without a multiplier (for example 'EGGS 12PK') are not recognised as a quantity of 12, and correctly fall through to 'not detected' for the user to supply.

#### ✅ `CD-SCAN-06` — Deterministic normalisation and anti-hallucination of model output

**Priority:** P0 · **Integration:** `production`

*Every interpreted item is validated against the lines that were actually sent, so a product the model invented can never reach the pantry; survivors are canonicalised, quantity-resolved, deduplicated and split into pantry candidates and exclusions.*

**Implementation evidence.** ReceiptItemNormalizer applies seven documented rules in order. The first is the hard stop: an item is matched back to a real receipt line through the model's echo, compared on folded text (uppercased alphanumerics only, tolerating spacing and punctuation drift), and discarded if no line corresponds — a model that decides a shopper probably bought milk has nowhere to attach the claim. Matched lines are consumed, so an echo repeated twice yields one candidate. Blank and over-60-character names are dropped; unrecognised classifications and categories fall back to .unknown and .other rather than being guessed. Quantity resolution runs the deterministic parser first and accepts the model's proposal only when the parser found nothing AND the proposed number literally appears in the line. Duplicates are collapsed by canonical name in receipt order, adding same-unit quantities (two 500 g chicken lines really is a kilogram) and keeping the first quantity when units differ rather than inventing a conversion. An item is excluded only if every line for it was non-ingredient. ReceiptItemClassification.shouldAddToPantry is the single place the product decision lives, and only .ingredient qualifies.

**Source files.** `FridgeFit/UseCases/ReceiptItemNormalizer.swift:53`, `FridgeFit/UseCases/ReceiptItemNormalizer.swift:114`, `FridgeFit/UseCases/ReceiptItemNormalizer.swift:145`, `FridgeFit/UseCases/ReceiptItemNormalizer.swift:178`, `FridgeFit/Domain/Models/ReceiptItemClassification.swift:18`

**Tests (25, all passing).**

- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_keepsIngredientsAndExcludesEverythingElse`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_excludesHouseholdAndPersonalCare`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_excludesBeveragesAndNonCookingFood`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_keepsMilkWhenClassifiedAsAnIngredient`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_dropsItemsThatEchoALineNeverSent`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_consumesEachLineOnlyOnce`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_matchesEchoesDespiteSpacingAndCaseDrift`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_takesQuantityFromTheReceiptText`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_prefersTheReceiptQuantityOverTheModels`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_rejectsAModelQuantityThatIsNotInTheLine`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_acceptsAModelQuantityCorroboratedByTheLine`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_leavesQuantityUnknownWhenNobodyStatedOne`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_collapsesSynonymsOntoOnePantryCandidate`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_addsQuantitiesOfTheSameUnitWhenMerging`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_keepsFirstQuantityWhenUnitsDiffer`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_doesNotMergeDifferentIngredients`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_returnsEmpty_forEmptyInterpretation`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_returnsEmpty_whenNoLinesWereSent`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_dropsItemsWithNoUsableName`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_dropsOverlongNames`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_treatsUnrecognisedClassificationAsUnknown`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_fallsBackToOtherCategory_forUnrecognisedCategory`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_excludesUnknownItems`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_carriesTheOriginalReceiptLineThrough`
- `FridgeFitTests/UseCases/ReceiptItemNormalizerTests.swift: test_normalize_ordersCandidatesByPositionOnTheReceipt`

**Remaining work.** None.

**Risks.** None identified at unit level. The 25 tests are the most comprehensive set in the project and include the adversarial case directly (test_normalize_dropsItemsThatEchoALineNeverSent). The residual risk is upstream and is recorded under CD-SCAN-05: how often a real model echoes faithfully enough to be matched.

**Caveats.** The containment fallback accepts a match only when exactly one remaining line contains the echo or is contained by it, which keeps the tolerance from becoming ambiguous.

#### ✅ `CD-SCAN-07` — Ingredient name canonicalisation

**Priority:** P1 · **Integration:** `production`

*The same food arriving spelled several ways resolves to one stable internal identity, while the user keeps reading the receipt's own wording.*

**Implementation evidence.** IngredientCanonicalizer runs a four-step pipeline: fold (lowercase, strip diacritics, turn _ - / into spaces, drop punctuation, delete apostrophes so za'atar stays one word); phrase lookup of the whole folded phrase and its singularised form against the synonym table BEFORE any words are removed, which is what protects compounds — 'sweet potato' is matched whole so descriptor removal never strips 'sweet' and merges it into 'potato'; descriptor removal of a conservative list of words that modify a food without changing which food it is, kept if removing them would leave nothing because 'cherry' alone is a fruit; then lookup again, falling back to the stripped phrase in snake_case so an unknown grocery still gets a stable identity. Display names keep the receipt's flavour ('Red Capsicum', not 'bell_pepper'), with a preferred-Australian-term fallback when the model returned something internal-looking. The model's canonical suggestion is treated as a hint that wins only when it resolves to a known name.

**Source files.** `FridgeFit/UseCases/IngredientCanonicalizer.swift:172`, `FridgeFit/UseCases/IngredientCanonicalizer.swift:196`, `FridgeFit/UseCases/IngredientCanonicalizer.swift:114`, `FridgeFit/UseCases/IngredientCanonicalizer.swift:272`

**Tests (18, all passing).**

- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_resolvesEveryCapsicumSpellingToOneIdentity`
- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_collapsesChickenCuts`
- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_collapsesMushroomVarieties`
- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_collapsesTomatoVarieties`
- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_collapsesSalmonCuts`
- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_collapsesSaladLeaves`
- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_protectsCompoundFoodsFromDescriptorRemoval`
- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_keepsNamesThatAreEntirelyDescriptorWords`
- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_keepsUnrelatedFoodsApart`
- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_mapsDialectSynonyms`
- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_givesUnknownFoodsAStableIdentity`
- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_isStableAcrossPunctuationAndSpacing`
- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_keepsTheReadableNameForDisplay`
- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_titleCasesALowercaseDisplayName`
- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_replacesInternalLookingDisplayNames`
- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_fallsBackToDisplayName_whenModelHintIsUnrecognised`
- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_usesModelHint_whenItResolvesAndDisplayNameDoesNot`
- `FridgeFitTests/UseCases/IngredientCanonicalizerTests.swift: test_canonicalize_returnsEmpty_forNamesWithNothingInThem`

**Remaining work.** None for the scan pipeline. Extending canonical identity to pantry duplicate detection and recipe matching is tracked under CD-PANTRY-03 and CD-RECIPE-03.

**Risks.** The descriptor list merges names that were previously distinct, and a wrong merge is much harder for a user to notice than a missed one. The code says this explicitly and keeps the list conservative — notably omitting colour words like 'orange' that are also foods — and test_canonicalize_keepsUnrelatedFoodsApart guards the direction that matters.

**Caveats.** The canonical identity is computed and stored on ReceiptIngredientCandidate but is NOT carried into PantryItem, so the work is used for scan-time deduplication only and is discarded at the pantry boundary. That is the root of the inconsistency noted in CD-PANTRY-03.

#### ✅ `CD-SCAN-08` — Review and correct detected items before saving

**Priority:** P0 · **Integration:** `production`

*Nothing is stored until the user confirms it. Every detected row can be renamed, recategorised, requantified, unticked or deleted first, with the originating receipt line shown so the user can check it against the paper.*

**Implementation evidence.** ReceiptItemReviewView lists one editable ReceiptItemRow per draft with a tick, an editable name field, the source receipt line, and quantity, unit and category pickers; swipe-to-delete removes a row. ReceiptScannerViewModel owns the drafts and exposes toggleSelection, updateName, updateCategory, updateQuantityText, updateUnit, removeDraft and removeDrafts. A row with no detected quantity starts with an empty field and says 'Quantity not detected — enter one to add this item' rather than being pre-filled with a made-up '1 pcs'; an item already in the pantry starts unticked and warns why. Two things are deliberately absent and documented: no confidence badge (the old fridge-scan showed the model's self-reported confidence, which measured nothing and gave the user no action) and no canonical identifiers in the UI. Excluded items are inspectable in a DisclosureGroup behind #if DEBUG only.

**Source files.** `FridgeFit/Views/Scanner/ReceiptItemReviewView.swift:24`, `FridgeFit/Views/Scanner/ReceiptItemReviewView.swift:155`, `FridgeFit/ViewModels/ReceiptScannerViewModel.swift:255`, `FridgeFit/Domain/Models/ReceiptItemDraft.swift:25`

**Tests (15, all passing).**

- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_scan_populatesConfirmationDrafts`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_scan_keepsExcludedItemsOutOfTheDraftsButAvailableForDiagnostics`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_scan_fillsQuantityOnlyWhenTheReceiptStatedOne`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_scan_carriesTheReceiptLineOntoEachDraft`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_scan_startsItemsAlreadyInThePantryUnticked`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_editing_updatesTheDraftWithoutRescanning`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_removeDraft_dropsTheRow`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_scan_storesNothingOnItsOwn`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_cancelScan_leavesNoResults`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_scan_isIgnoredWhileAScanIsAlreadyRunning`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_reset_clearsEverything`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_scan_reportsFailure_whenNoTextIsRecognized`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_scan_reportsFailure_whenNothingIsAnIngredient`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_scan_reportsFailure_withoutSelectedImage`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_scan_mapsUnknownErrorsToTheGenericMessage`

**Remaining work.** None.

**Risks.** None identified. test_scan_storesNothingOnItsOwn asserts the central guarantee that a scan alone writes nothing to the pantry.

**Caveats.** Excluded items are hidden in release builds, so a user whose mushrooms were misclassified as household has no way to recover them from this screen — they would re-add by hand. That is a deliberate trade-off against a confirmation list cluttered with dishwashing tablets, and it is documented as such.

#### ✅ `CD-SCAN-09` — Add confirmed items to the pantry with per-item outcomes

**Priority:** P0 · **Integration:** `production`

*Confirmed items go into the pantry through the existing pantry rules, and the user is told exactly what was added, what was already there, and what could not be added.*

**Implementation evidence.** AddDetectedIngredientsUseCase is deliberately thin: it runs AddPantryItemUseCase once per confirmed draft and collects per-item outcomes, so a receipt of a dozen ingredients cannot be stopped dead by one duplicate. A draft with no usable quantity is reported as a failure rather than defaulted to a number the user never chose. AddDetectedIngredientsSummary reports addedNames, duplicateNames and failures with reasons, and renders one localised sentence via ListFormatter. ReceiptScannerViewModel removes accepted drafts so a second tap cannot re-add them, leaves rejected ones in place to be fixed, and closes the review sheet only on complete success; PantryView then reloads and shows the summary in an alert. This is the only path from a scan into the pantry — the scanner UI has no repository access of its own.

**Source files.** `FridgeFit/UseCases/AddDetectedIngredientsUseCase.swift:82`, `FridgeFit/UseCases/AddDetectedIngredientsUseCase.swift:32`, `FridgeFit/ViewModels/ReceiptScannerViewModel.swift:301`, `FridgeFit/Views/Pantry/PantryView.swift:97`

**Tests (9, all passing).**

- `FridgeFitTests/UseCases/AddDetectedIngredientsUseCaseTests.swift: test_addDetectedIngredients_storesItemsThroughPantryRepository`
- `FridgeFitTests/UseCases/AddDetectedIngredientsUseCaseTests.swift: test_addDetectedIngredients_respectsExistingDuplicateRule`
- `FridgeFitTests/UseCases/AddDetectedIngredientsUseCaseTests.swift: test_addDetectedIngredients_addsOthers_whenOneIsDuplicate`
- `FridgeFitTests/UseCases/AddDetectedIngredientsUseCaseTests.swift: test_addDetectedIngredients_reportsFailure_forUnusableQuantity`
- `FridgeFitTests/UseCases/AddDetectedIngredientsUseCaseTests.swift: test_addDetectedIngredients_reportsFailure_forBlankName`
- `FridgeFitTests/UseCases/AddDetectedIngredientsUseCaseTests.swift: test_addDetectedIngredients_reportsFailure_whenQuantityWasNeverDetected`
- `FridgeFitTests/UseCases/AddDetectedIngredientsUseCaseTests.swift: test_summary_userMessage_describesMixedOutcome`
- `FridgeFitTests/UseCases/AddDetectedIngredientsUseCaseTests.swift: test_summary_userMessage_whenNothingAdded`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_addSelectedToPantry_storesOnlyTickedItemsWithQuantities`

**Remaining work.** None.

**Risks.** The accepted-draft removal matches drafts to summary.addedNames by name string. If two drafts resolved to the same display name, both would be removed when only one was added. The canonical-name dedupe upstream makes this hard to reach, but the id is available and matching on it would be exact.

**Caveats.** Reusing AddPantryItemUseCase rather than writing a second insertion path is why scan-time and hand-entry validation can never diverge.

### Ingredient Substitution

#### ✅ `CD-SUBST-03` — Deterministic validation of substitution suggestions against the pantry

**Priority:** P0 · **Integration:** `production`

*Whether a suggested substitute is actually in the pantry, in sufficient quantity, and in a comparable unit is decided by the app from its own data — never by the LLM.*

**Implementation evidence.** SubstitutionSuggestionValidator is the single place allowed to decide pantry existence, sufficiency and unit compatibility. It drops structurally invalid candidates entirely (blank name or explanation) as distinct from marking them rejected, clamps any provider confidence into 0–1, parses suggestedUnit from a raw string and treats an unparseable one as no unit given, matches the pantry with the same Ingredient.matches(name:) rule used everywhere, and assigns one of five statuses: availableInPantry, notInPantry, insufficientQuantity, unsupportedUnit (when MeasurementUnit.convert cannot safely compare), or rejected. RawSubstitutionSuggestion and SubstitutionSuggestion are separate types so the untrusted and validated shapes cannot be mixed up, and the raw type deliberately has no pantry fields at all.

**Source files.** `FridgeFit/UseCases/SubstitutionSuggestionValidator.swift:21`, `FridgeFit/Domain/Models/RawSubstitutionSuggestion.swift:16`, `FridgeFit/Domain/Models/SubstitutionValidationStatus.swift:10`

**Tests (12, all passing).**

- `FridgeFitTests/UseCases/SubstitutionSuggestionValidatorTests.swift: test_validate_pantryIngredientDetected_exactMatch`
- `FridgeFitTests/UseCases/SubstitutionSuggestionValidatorTests.swift: test_validate_pantryIngredientDetected_caseInsensitiveAndTrimmed`
- `FridgeFitTests/UseCases/SubstitutionSuggestionValidatorTests.swift: test_validate_unknownIngredient_isNeverClaimedAsAvailable`
- `FridgeFitTests/UseCases/SubstitutionSuggestionValidatorTests.swift: test_validate_pantryQuantitySufficient`
- `FridgeFitTests/UseCases/SubstitutionSuggestionValidatorTests.swift: test_validate_pantryQuantityInsufficient_neverClaimsEnough`
- `FridgeFitTests/UseCases/SubstitutionSuggestionValidatorTests.swift: test_validate_noSuggestedQuantity_reportsPresenceOnly`
- `FridgeFitTests/UseCases/SubstitutionSuggestionValidatorTests.swift: test_validate_gramsToKilograms`
- `FridgeFitTests/UseCases/SubstitutionSuggestionValidatorTests.swift: test_validate_millilitersToLiters`
- `FridgeFitTests/UseCases/SubstitutionSuggestionValidatorTests.swift: test_validate_incompatibleUnitDimensions_isUnsupportedUnit`
- `FridgeFitTests/UseCases/SubstitutionSuggestionValidatorTests.swift: test_validate_blankIngredientName_isRejectedEntirely`
- `FridgeFitTests/UseCases/SubstitutionSuggestionValidatorTests.swift: test_validate_blankExplanation_isRejectedEntirely`
- `FridgeFitTests/UseCases/SubstitutionSuggestionValidatorTests.swift: test_validate_unparseableSuggestedUnit_isTreatedAsNoUnitGiven`

**Remaining work.** None.

**Risks.** None identified. test_validate_unknownIngredient_isNeverClaimedAsAvailable and test_validate_pantryQuantityInsufficient_neverClaimsEnough assert the two adversarial cases by name.

**Caveats.** The provider's own confidence value is carried through but is explicitly never used to decide availability — it is informational only, and the UI does not display it.

#### ✅ `CD-SUBST-04` — Deduplicate, rank, cap and cache substitution results

**Priority:** P1 · **Integration:** `production`

*The user sees a short, ranked, duplicate-free list, pantry-backed options first, and re-opening the same prompt against an unchanged pantry does not make another provider call.*

**Implementation evidence.** GetIngredientSubstitutionsUseCase validates every raw candidate, drops rejected and structurally invalid ones, deduplicates by lowercased trimmed name with first occurrence winning, sorts by an explicit status priority (availableInPantry, then insufficientQuantity, unsupportedUnit, notInPantry, rejected) and caps the result to three. Results are cached under a SubstitutionCacheKey of recipe id, normalised ingredient name and a hash of the pantry snapshot, so a pantry change invalidates the entry naturally with no expiry logic. The cache is checked before the provider call.

**Source files.** `FridgeFit/UseCases/GetIngredientSubstitutionsUseCase.swift:71`, `FridgeFit/UseCases/GetIngredientSubstitutionsUseCase.swift:44`, `FridgeFit/UseCases/SubstitutionCache.swift:25`

**Tests (10, all passing).**

- `FridgeFitTests/UseCases/GetIngredientSubstitutionsUseCaseTests.swift: test_execute_generatesRequest_withMissingIngredientContext`
- `FridgeFitTests/UseCases/GetIngredientSubstitutionsUseCaseTests.swift: test_execute_generatesRequest_forInsufficientIngredient`
- `FridgeFitTests/UseCases/GetIngredientSubstitutionsUseCaseTests.swift: test_execute_emptySuggestions_returnsEmptyArray`
- `FridgeFitTests/UseCases/GetIngredientSubstitutionsUseCaseTests.swift: test_execute_allSuggestionsRejected_returnsEmptyArray`
- `FridgeFitTests/UseCases/GetIngredientSubstitutionsUseCaseTests.swift: test_execute_duplicateSuggestions_areDeduplicated`
- `FridgeFitTests/UseCases/GetIngredientSubstitutionsUseCaseTests.swift: test_execute_prioritizesPantryAvailableSuggestions_first`
- `FridgeFitTests/UseCases/GetIngredientSubstitutionsUseCaseTests.swift: test_execute_capsResultToThreeSuggestions`
- `FridgeFitTests/UseCases/GetIngredientSubstitutionsUseCaseTests.swift: test_execute_providerFailure_propagatesError`
- `FridgeFitTests/UseCases/GetIngredientSubstitutionsUseCaseTests.swift: test_execute_secondCallWithUnchangedPantry_usesCacheAndSkipsProviderCall`
- `FridgeFitTests/UseCases/GetIngredientSubstitutionsUseCaseTests.swift: test_execute_pantryChangeBetweenCalls_invalidatesCacheAndCallsProviderAgain`

**Remaining work.** None.

**Risks.** The cache is unbounded and never evicts. Documented as acceptable for one-recipe-detail-at-a-time usage, and the process-lifetime scope limits growth, but it is a slow leak in a long session. The pantry snapshot hash relies on Hasher, whose seed is randomised per process — correct here precisely because the cache does not persist across launches, and the code says so.

**Caveats.** The cache instance is created once in ContentView and is not cleared on sign-out, so cached suggestions could in principle outlive a user switch within one app session. The pantry-snapshot component of the key makes a stale hit unlikely rather than impossible. Related to CD-AUTH-04.

### User Profile

#### ✅ `CD-PROFILE-01` — Show the signed-in account

**Priority:** P1 · **Integration:** `production`

*The Profile tab tells the user which account they are signed in as.*

**Implementation evidence.** ProfileView renders a person icon and 'Signed in as {email}' from authViewModel.user?.email, inside the Profile tab's NavigationStack with a navigation title.

**Source files.** `FridgeFit/Views/ProfileView.swift:15`, `FridgeFit/ContentView.swift:74`

**Tests.** None.

**Remaining work.** None.

**Risks.** A Google account without an email on the Firebase user would render nothing at all rather than a fallback identity, since the Text is inside an if-let with no else branch.

**Caveats.** Marked completed because the stated requirement is satisfied and the implementation is trivially inspectable. The Profile screen as a whole is 37 lines — an icon, one line of text and a Sign Out button — which is thin for a tab of the app. See CD-PROFILE-03 through CD-PROFILE-06.

### Testing & Infrastructure

#### ✅ `CD-INFRA-01` — Automated unit test suite

**Priority:** P0 · **Integration:** `production`

*Domain logic, use cases, parsers, validators and view models are covered by an automated test suite that runs locally.*

**Implementation evidence.** A FridgeFitTests target holds 23 XCTest classes with 240 test methods, organised to mirror the production tree (Data, Domain, UseCases, ViewModels, Support). Coverage is concentrated where the risk is: 25 cases on the normaliser, 19 on the line parser, 18 on the canonicaliser, 18 on the scanner view model, 16 on feasibility, 15 on pantry suggestions, 14 each on the quantity parser and the substitution validator. Shared fixtures live in Support/SampleReceipt.swift and Support/TestImage.swift. Every external dependency has a double — InMemoryPantryRepository, InMemoryRecipeRepository, MockReceiptTextRecognizer, MockReceiptIngredientInterpreter, MockRecipeSuggestionService, MockSubstitutionService — plus a StubURLProtocol for the HTTP client, so the whole suite runs with no network, no camera, no device and no live credentials.

**Source files.** `FridgeFitTests/`, `FridgeFit/Data/MockReceiptScanning.swift:16`, `FridgeFit/Data/InMemoryPantryRepository.swift:11`

**Tests (1, all passing).**

- `All 240 tests across 23 classes`

**Remaining work.** None for the suite's existence.

**Risks.** No code-coverage measurement was produced, so 240 tests is a count of cases rather than a measure of lines reached. The doubles live in the production target rather than the test target, which keeps them available to SwiftUI previews but also ships mock code in the app binary.

**Caveats.** The suite was executed in this audit; see the testExecution block for the result. The tests are unusually behavioural — many assert documented invariants by name, including the adversarial cases where a model contradicts the pantry.

#### ✅ `CD-INFRA-02` — Layered architecture with testable boundaries

**Priority:** P0 · **Integration:** `production`

*The app separates presentation, presentation state, domain logic and data access, with every external dependency behind a protocol.*

**Implementation evidence.** The separation holds throughout and is not merely nominal. Views contain no business logic (AddPantryItemView's comment — 'Just collects input' — is accurate: validation is in the use case). View models map results and own no rules (PantryViewModel delegates every decision; RecipeViewModel never computes feasibility). All twelve use cases are plain value types taking protocol dependencies by injection. Six protocols isolate every external system, and each has both a production adapter and a double. The one consistent exception is AuthViewModel, which calls the Auth.auth() singleton directly and is consequently the only untestable view model — the exception that demonstrates the rule.

**Source files.** `FridgeFit/UseCases/`, `FridgeFit/Domain/Protocols/`, `FridgeFit/ViewModels/`, `FridgeFit/ContentView.swift:19`

**Tests (1, all passing).**

- `Demonstrated by the suite: every use case and four of five view models are tested with doubles`

**Remaining work.** Bring AuthViewModel behind a protocol so it matches the rest of the codebase (tracked as CD-AUTH-09).

**Risks.** All dependency wiring happens in ContentView.init, which is 38 lines of construction. It works and is readable, but it couples the root view to every concrete type in the app and is the reason view models are not rebuilt on an account change (CD-AUTH-04).

**Caveats.** The trust boundary is the strongest architectural property here: every generative-model output enters as an untrusted Raw* value and must pass a deterministic validator before any view sees it. That pattern is applied consistently across all three AI features.

#### ✅ `CD-INFRA-03` — Secrets excluded from version control

**Priority:** P0 · **Integration:** `production`

*API keys and Firebase configuration are never committed to the repository.*

**Implementation evidence.** .gitignore excludes GoogleService-Info.plist and Secrets.xcconfig. Config.xcconfig is committed but contains no credential: it optionally includes Secrets.xcconfig with #include? so a fresh checkout still builds when the file is absent, and sets only a non-secret model identifier. Secrets.example.xcconfig documents the required key with a placeholder value and a link to obtain one. Info.plist references $(OPENROUTER_API_KEY) as a build-setting substitution rather than a literal. OpenRouterConfiguration.loadFromInfoPlist returns nil on an empty key so callers fall back to an explicit error rather than sending an empty credential. git ls-files confirms neither GoogleService-Info.plist nor Secrets.xcconfig is tracked.

**Source files.** `.gitignore`, `Config.xcconfig`, `Secrets.example.xcconfig`, `FridgeFit/Data/OpenRouterConfiguration.swift:24`

**Tests (1, all passing).**

- `FridgeFitTests/Data/OpenRouterSubstitutionServiceTests.swift: test_unconfiguredSubstitutionService_alwaysThrowsNotConfigured`

**Remaining work.** None.

**Risks.** The same arrangement is why substitutions are non-functional in a fresh clone (CD-SUBST-01) and why the app cannot authenticate without the Firebase config being supplied separately. Both are correct trade-offs that need to be stated in setup documentation — of which there is none, as the repository has no README.

**Caveats.** This audit deliberately did not read or report any credential value. Config.xcconfig was inspected with values redacted, and Secrets.xcconfig does not exist in the working tree.

---

## D. Partially completed features (6)

Core implementation exists and is reachable, but an important requirement, integration or configuration is missing.

### Authentication

#### 🟡 `CD-AUTH-06` — Registration input validation

**Priority:** P2 · **Integration:** `production`

*The registration form validates input before submitting, rather than relying on backend errors.*

**Implementation evidence.** RegisterView.validationError enforces a minimum password length of 6 and password/confirmation equality, and suppresses the message until the user has typed something. canSubmit additionally requires a non-empty email and no in-flight request.

**Source files.** `FridgeFit/RegisterView.swift:16`, `FridgeFit/RegisterView.swift:23`

**Tests.** None.

**Missing.** No email-format validation and no password-strength feedback beyond the 6-character floor. Validation lives in the View rather than in a use case, so it is the only rule in the app that cannot be unit tested without a UI test.

**Remaining work.** Add email-format validation; consider extracting the rules into a small testable type to match the pattern used everywhere else in this codebase.

**Risks.** Low.

**Caveats.** 6 characters matches Firebase's own default minimum, so the floor is not arbitrary.

### Recipe Management

#### 🟡 `CD-RECIPE-04` — Unit conversion for quantity comparison

**Priority:** P2 · **Integration:** `production`

*Pantry quantities are converted into the recipe's unit so amounts can be compared, without ever guessing an unsafe conversion.*

**Implementation evidence.** MeasurementUnit.convert handles identity plus the four exact same-dimension conversions (g<->kg, ml<->L) and returns nil for everything else, which callers translate into quantityUnverified / unsupportedUnit rather than a guess. Seven tests cover identity, all four conversions, cross-dimension and unsupported pairs.

**Source files.** `FridgeFit/Domain/Models/MeasurementUnit+Conversion.swift:18`, `FridgeFit/Domain/Models/MeasurementUnit.swift:10`

**Tests (7, all passing).**

- `FridgeFitTests/Domain/MeasurementUnitConversionTests.swift: test_convert_sameUnit_returnsQuantityUnchanged`
- `FridgeFitTests/Domain/MeasurementUnitConversionTests.swift: test_convert_gramsToKilograms`
- `FridgeFitTests/Domain/MeasurementUnitConversionTests.swift: test_convert_kilogramsToGrams`
- `FridgeFitTests/Domain/MeasurementUnitConversionTests.swift: test_convert_millilitersToLiters`
- `FridgeFitTests/Domain/MeasurementUnitConversionTests.swift: test_convert_litersToMilliliters`
- `FridgeFitTests/Domain/MeasurementUnitConversionTests.swift: test_convert_returnsNil_forIncompatibleDimensions`
- `FridgeFitTests/Domain/MeasurementUnitConversionTests.swift: test_convert_returnsNil_forUnsupportedUnitPairs`

**Missing.** MeasurementUnit offers eight units but only four participate in conversion. cups, tbsp, tsp and pcs can never be compared to anything but themselves, so a pantry entry of '2 cups' against a recipe needing '250 ml' is permanently 'Check amount'. Those four units are selectable in both the add and update forms and in the receipt review screen, so a user can readily create pantry items that feasibility can never evaluate.

**Remaining work.** Either add volume ratios for cup/tbsp/tsp (a cup is a defined volume; the ambiguity is ingredient density, not the unit), or restrict the unit pickers to the units the app can actually reason about, or label the unconvertible units in the picker.

**Risks.** This is a gap between what the UI invites the user to enter and what the domain can evaluate. It degrades gracefully and honestly, which is the right failure mode, but the degradation is silent until the user reaches a recipe.

**Caveats.** Failing closed is the correct design choice and is explicitly documented and tested. The gap is the unit set offered, not the conversion logic.

### Receipt Scanning

#### 🟡 `CD-SCAN-11` — Camera permission handling and usage description

**Priority:** P1 · **Integration:** `production`

*Camera access is requested correctly and the purpose string accurately describes why the app needs the camera.*

**Implementation evidence.** CameraAccess.request() checks UIImagePickerController.isSourceTypeAvailable first (returning .unavailable on a device with no camera, including the Simulator), then AVCaptureDevice.authorizationStatus, requesting on .notDetermined and treating .restricted as denied. Each outcome has an explanation and the scanner presents the camera only after .granted. NSCameraUsageDescription is present in Info.plist, so the app will not crash on first camera access.

**Source files.** `FridgeFit/Views/Scanner/CameraPicker.swift:88`, `FridgeFit/Views/Scanner/ReceiptScannerView.swift:210`, `FridgeFit/Info.plist`

**Tests.** None.

**Missing.** The purpose string is stale and describes the removed feature: NSCameraUsageDescription reads 'FridgeFit uses the camera to photograph the inside of your fridge so Apple Intelligence can identify ingredients on this device.' The fridge-photo scanner was replaced by receipt scanning in commit b79ee34, and the camera is now used only to photograph receipts. CameraAccess.denied carries the same stale wording ('needs camera access to photograph your fridge'), as does CameraPicker's own doc comment. No tests cover the permission logic.

**Remaining work.** Update NSCameraUsageDescription and CameraAccess.denied's explanation to describe receipt photography. Both are user-visible strings, one of them at App Store review time.

**Risks.** A purpose string that does not match actual camera use is a recognised App Store review rejection reason, and it misleads the user at the exact moment they are deciding whether to grant access.

**Caveats.** This is the clearest residue of the fridge-scan-to-receipt-scan migration. The permission logic itself is correct; only the wording is wrong. Fixing it means editing production files, which this audit does not do.

### Ingredient Substitution

#### 🟡 `CD-SUBST-01` — Find a substitute for an unavailable recipe ingredient

**Priority:** P1 · **Integration:** `production-code-present-but-unconfigured`

*On a recipe's detail screen, any ingredient that is missing, insufficient or unverifiable offers a Find Substitute action that returns usable alternatives.*

**Implementation evidence.** RecipeDetailView renders a SubstitutionSectionView beneath every ingredient whose availability is .missing, .insufficient or .quantityUnverified. The section has its own loading, results and error states and a Find Substitute button. SubstitutionViewModel keys loading, results and errors by RecipeIngredient.id so several ingredients on one recipe can be resolved independently, and surfaces a specific message when the provider returned nothing usable. SubstitutionSuggestionCard shows the app's own validation verdict, the on-hand amount, the explanation and any limitations.

**Source files.** `FridgeFit/Views/Recipes/RecipeDetailView.swift:56`, `FridgeFit/Views/Support/SubstitutionPresentation.swift:23`, `FridgeFit/ViewModels/SubstitutionViewModel.swift:28`

**Tests (4, all passing).**

- `FridgeFitTests/ViewModels/SubstitutionViewModelTests.swift: test_findSubstitutes_success_populatesSuggestions_andClearsLoading`
- `FridgeFitTests/ViewModels/SubstitutionViewModelTests.swift: test_findSubstitutes_failure_setsErrorMessage_forThatIngredientOnly`
- `FridgeFitTests/ViewModels/SubstitutionViewModelTests.swift: test_findSubstitutes_emptyResult_setsHumanReadableErrorMessage`
- `FridgeFitTests/ViewModels/SubstitutionViewModelTests.swift: test_findSubstitutes_tracksStatePerIngredient_independently`

**Missing.** The feature cannot return a suggestion in this checkout. ContentView builds the substitution service from OpenRouterConfiguration.loadFromInfoPlist(), which reads OPENROUTER_API_KEY from Info.plist; that value comes from $(OPENROUTER_API_KEY), which Config.xcconfig supplies only by optionally including Secrets.xcconfig. Secrets.xcconfig is gitignored and is NOT present in the working tree, so the key resolves empty, loadFromInfoPlist returns nil, and ContentView falls back to UnconfiguredSubstitutionService. Every Find Substitute tap therefore fails with SubstitutionServiceError.notConfigured.

**Remaining work.** Create Secrets.xcconfig from Secrets.example.xcconfig with a valid OpenRouter key, rebuild, and confirm the feature returns suggestions against the live provider.

**Risks.** A demonstration from a fresh clone of this repository will show this feature failing, not working. The failure is handled gracefully and the message names the fix, but the feature is non-functional until a key is supplied. This is a configuration gap, not a code defect.

**Caveats.** Falling back to an explicit UnconfiguredSubstitutionService rather than sending an empty Bearer token is the correct design, and the gitignored-secret arrangement is good practice (see CD-INFRA-03).

#### 🟡 `CD-SUBST-05` — Dietary restriction enforcement on substitutions

**Priority:** P1 · **Integration:** `production-but-inert`

*A suggested substitute that conflicts with the user's stated dietary restrictions is never presented as usable.*

**Implementation evidence.** The mechanism exists and is tested end to end. SubstitutionRequest carries dietaryRestrictions; SubstitutionPromptBuilder adds a 'Dietary restrictions to respect' line when the list is non-empty, and the system prompt instructs the model never to suggest a conflicting ingredient; SubstitutionSuggestionValidator.conflictsWithRestriction performs a deterministic case-insensitive substring check and marks a conflicting candidate .rejected, which GetIngredientSubstitutionsUseCase.validateAndRank then filters out so it can never reach the UI.

**Source files.** `FridgeFit/UseCases/SubstitutionSuggestionValidator.swift:114`, `FridgeFit/UseCases/GetIngredientSubstitutionsUseCase.swift:83`, `FridgeFit/Data/SubstitutionPromptBuilder.swift:62`, `FridgeFit/Domain/Models/SubstitutionRequest.swift:31`

**Tests (3, all passing).**

- `FridgeFitTests/UseCases/SubstitutionSuggestionValidatorTests.swift: test_validate_conflictingDietaryRestriction_isRejected`
- `FridgeFitTests/UseCases/SubstitutionSuggestionValidatorTests.swift: test_validate_nonConflictingDietaryRestriction_isUnaffected`
- `FridgeFitTests/UseCases/GetIngredientSubstitutionsUseCaseTests.swift: test_execute_allSuggestionsRejected_returnsEmptyArray`

**Missing.** The list is never populated in production. GetIngredientSubstitutionsUseCase.execute declares dietaryRestrictions: [String] = [], and its only production caller — SubstitutionViewModel.findSubstitutes — omits the argument entirely, so the default empty array is always used. A grep for dietaryRestrictions across the whole codebase finds it supplied non-empty only in test code. There is no dietary profile UI, no storage, and nothing to read a restriction from. The code documents this honestly as 'always empty until a future phase adds a real dietary/allergy profile'.

**Remaining work.** Build the dietary preferences profile (CD-PROFILE-03): a model, Firestore persistence, a Profile screen, and a read path from the view model into the use case. The substitution side then works with no further change.

**Risks.** The gap is user-facing and safety-adjacent. A user with a nut allergy has no way to tell FridgeFit, and the substitution feature will suggest peanut butter. The validator's substring check is also explicitly not an allergen database — it would match 'peanut' in 'Peanut Butter' but not 'groundnut', and it is documented as deliberately simple. Any user-facing allergy claim would need a far stronger mechanism than this.

**Caveats.** Building the enforcement mechanism before the data source is defensible sequencing, and the limitation is documented in the source rather than hidden. But as shipped, this requirement protects nobody.

### Testing & Infrastructure

#### 🟡 `CD-INFRA-08` — Accessibility support

**Priority:** P2 · **Integration:** `production`

*The app is usable with VoiceOver and respects the system's accessibility settings.*

**Implementation evidence.** Accessibility is addressed deliberately rather than incidentally. Pantry rows are accessibilityElement(children: .combine) with a composed label naming the item, category and quantity, plus a hint ('Double tap to update quantity'). Form fields carry explicit accessibilityLabels. Receipt review rows label the tick with its state and a hint naming the item, and the quantity field's label changes to say when the receipt stated no amount. The scanning indicator is combined and labelled. Decorative IconBadges are accessibilityHidden. Standard SwiftUI components (List, Form, Picker, ContentUnavailableView) are used throughout, which brings Dynamic Type and VoiceOver support by default.

**Source files.** `FridgeFit/Views/Pantry/PantryView.swift:69`, `FridgeFit/Views/Scanner/ReceiptItemReviewView.swift:170`, `FridgeFit/Views/Support/PantryPresentation.swift:30`, `FridgeFit/Views/Scanner/ReceiptScannerView.swift:145`

**Tests.** None.

**Missing.** No accessibility audit was run and no VoiceOver or Dynamic Type verification exists. Colour is used to carry feasibility and availability meaning (green/orange/red/blue), always paired with an SF Symbol and a text label, which is the right mitigation but is unverified for contrast. Nothing checks behaviour at the largest accessibility text sizes, where the receipt review row's fixed 110-point quantity field and three side-by-side controls are the most likely to break.

**Remaining work.** Run Xcode's Accessibility Inspector audit on each screen, test with VoiceOver, and check the largest Dynamic Type sizes — particularly ReceiptItemReviewView.

**Risks.** The receipt review row packs a text field and two pickers into one horizontal stack with a fixed-width frame; at large text sizes this is likely to clip or overflow.

**Caveats.** This is better accessibility work than most projects of this size contain. It is marked partial for lack of verification, not lack of effort.

---

## E. Not started (22)

No meaningful implementation evidence found. **This list is derived from the code, not from Notion** — it records what a reviewer would expect to exist and does not. A Notion requirement that was never implemented leaves no trace for this audit to find, so this section cannot be assumed complete.

### Authentication

#### ⬜ `CD-AUTH-07` — Password reset / forgot password

**Priority:** P1 · **Integration:** `none`

*A user who has forgotten their password can request a reset email and regain access to their account.*

**Implementation evidence.** No implementation found. A case-insensitive search for sendPasswordReset across all Swift sources returns nothing, and neither LoginView nor RegisterView offers a reset affordance.

**Source files.** —

**Tests.** None.

**Missing.** Entire feature: UI entry point, AuthViewModel method, Firebase sendPasswordReset(withEmail:) call, and success/failure messaging.

**Remaining work.** Add a 'Forgot password?' control to LoginView, an AuthViewModel.sendPasswordReset(email:) method wrapping Auth.auth().sendPasswordReset, and a confirmation state that does not disclose whether the address is registered.

**Risks.** Account recovery is a baseline expectation for any email/password product; without it a forgotten password is unrecoverable from inside the app.

**Caveats.** Whether this is in scope depends on the Notion Feature List, which could not be read.

#### ⬜ `CD-AUTH-08` — Email verification

**Priority:** P2 · **Integration:** `none`

*A newly registered email address is verified before the account is treated as fully established.*

**Implementation evidence.** No implementation found. Searches for sendEmailVerification and isEmailVerified return nothing; registration signs the user straight in.

**Source files.** —

**Tests.** None.

**Missing.** Verification send, verification state display, and any gating based on verification status.

**Remaining work.** Decide whether verification is required at all, then send on registration and surface the unverified state on Profile.

**Risks.** Unverified addresses make the password-reset path (CD-AUTH-07) less trustworthy.

**Caveats.** Legitimately optional for a coursework-scope product; listed because it is absent, not because it is necessarily required.

#### ⬜ `CD-AUTH-09` — Automated test coverage for authentication

**Priority:** P1 · **Integration:** `none`

*Authentication behaviour is covered by automated tests.*

**Implementation evidence.** No test file references AuthViewModel, LoginView or RegisterView. The 23 test classes cover use cases, parsers, validators, view models for Pantry/Recipe/Scanner/Substitution, and Firestore field mapping, but authentication is the one feature area with zero coverage.

**Source files.** —

**Tests.** None.

**Missing.** All authentication tests.

**Remaining work.** Introduce an auth-service protocol so AuthViewModel can be driven by a double, then test sign-in success, sign-in failure messaging, sign-up, sign-out and the loading flag.

**Risks.** Authentication is the gate on every other feature and is currently the least verified part of the app.

**Caveats.** This is the direct consequence of AuthViewModel depending on the Auth.auth() singleton; it is a design consequence, not an oversight in the test suite.

### Pantry Management

#### ⬜ `CD-PANTRY-08` — Expiry date and freshness tracking

**Priority:** P2 · **Integration:** `none`

*Pantry items carry an expiry or best-before date so the user can see what needs using up.*

**Implementation evidence.** No implementation found. PantryItem holds only id, ingredient, quantity and unit. A case-insensitive search for expir / bestBefore / useBy / shelfLife across all production Swift sources returns only an unrelated comment in SubstitutionCache.

**Source files.** `FridgeFit/Domain/Models/PantryItem.swift:9`

**Tests.** None.

**Missing.** Date field on PantryItem, Firestore field and migration for existing documents, form input, list sorting or badging, and any notification.

**Remaining work.** Add an optional expiryDate to PantryItem, extend the Firestore encode/decode pair and its mapping tests, surface it in the add/update forms and badge expiring rows in PantryView.

**Risks.** Adding a field to the Firestore schema requires the decoder to tolerate documents written before the change. The current decoder uses strict guard-let on every field, so any new required field would silently drop all existing pantry items. The field must be optional.

**Caveats.** Commonly expected of a pantry app, but its presence in the Notion Feature List could not be confirmed.

#### ⬜ `CD-PANTRY-09` — Pantry search, filter and sort controls

**Priority:** P2 · **Integration:** `none`

*The user can search the pantry by name and filter or sort it, for example by category.*

**Implementation evidence.** No implementation found. PantryView contains no .searchable modifier and no filter or sort state; a search across all Swift sources for searchable / searchText returns nothing. The only ordering is the Firestore query's fixed order(by: "ingredientName").

**Source files.** `FridgeFit/Views/Pantry/PantryView.swift:45`, `FridgeFit/Data/FirestorePantryRepository.swift:40`

**Tests.** None.

**Missing.** Search field, filter controls, sort options and the corresponding view-model state.

**Remaining work.** Add .searchable plus a category filter to PantryView, with the filtering logic in the view model so it can be tested.

**Risks.** Usability degrades as the pantry grows; a receipt scan can add ten items at once, so lists get long quickly.

**Caveats.** Not confirmed as a requirement.

#### ⬜ `CD-PANTRY-10` — Offline behaviour and cache configuration

**Priority:** P2 · **Integration:** `none`

*The pantry remains usable without a network connection, with a defined offline policy.*

**Implementation evidence.** No implementation found. Firestore is used via the default Firestore.firestore() instance with no FirestoreSettings, no explicit cache configuration and no network-state handling. PantryViewModel surfaces any failure as error.localizedDescription with no offline-specific messaging or retry.

**Source files.** `FridgeFit/Data/FirestorePantryRepository.swift:23`, `FridgeFit/ViewModels/PantryViewModel.swift:45`

**Tests.** None.

**Missing.** An explicit offline decision. The Firestore SDK provides some local caching by default, but nothing here configures, relies on, tests or documents it, so no offline guarantee can be claimed.

**Remaining work.** Decide the offline policy, configure FirestoreSettings deliberately, and give the UI an offline-aware message distinct from a generic failure.

**Risks.** A kitchen is exactly where connectivity is unreliable. Today a network failure produces a raw Firestore error string in an alert.

**Caveats.** Listed as not started because no deliberate offline work exists, not because the SDK provides nothing.

### Recipe Management

#### ⬜ `CD-RECIPE-05` — Remote recipe catalogue

**Priority:** P1 · **Integration:** `none`

*Recipes come from a remote backend or API rather than a fixed dataset compiled into the app, so the catalogue can grow without shipping a new build.*

**Implementation evidence.** No implementation found. The only RecipeRepository conformances are BundledRecipeRepository (10 hard-coded recipes) and InMemoryRecipeRepository (a test double). BundledRecipeRepository's own documentation states 'Phase 2 doesn't have a remote recipe API yet'. No networking code exists outside OpenRouterSubstitutionService.

**Source files.** `FridgeFit/Data/BundledRecipeRepository.swift:14`, `FridgeFit/Domain/Protocols/RecipeRepository.swift:14`

**Tests.** None.

**Missing.** The entire remote source: API choice, a RecipeRepository conformance, response models, error mapping, caching and pagination.

**Remaining work.** Choose a source (a recipe API, or Firestore as the recipe store), implement RecipeRepository against it, and inject it in ContentView. The protocol boundary means no use case or view changes.

**Risks.** A 10-recipe catalogue bounds how useful feasibility matching can be: most real pantries will not match any of the ten. This is the single biggest limitation on the product's core value proposition, independent of code quality.

**Caveats.** The architecture is genuinely ready for this — a one-line change in ContentView — so the cost is in the adapter, not in the app.

#### ⬜ `CD-RECIPE-06` — Recipe search and filtering

**Priority:** P2 · **Integration:** `none`

*The user can search recipes by name or ingredient and filter them, for example to show only makeable recipes.*

**Implementation evidence.** No implementation found. RecipeListView has no .searchable and no filter state; recipes render in the repository's fixed order with no way to narrow them.

**Source files.** `FridgeFit/Views/Recipes/RecipeListView.swift:28`

**Tests.** None.

**Missing.** Search field, filter controls and view-model support.

**Remaining work.** Add .searchable and a feasibility filter, with the predicate in RecipeViewModel so it is testable.

**Risks.** Low while the catalogue is 10 recipes; becomes necessary alongside CD-RECIPE-05.

**Caveats.** 'Show me only what I can make' is arguably the most valuable filter this app could offer, since the feasibility verdict is already computed for every recipe.

#### ⬜ `CD-RECIPE-07` — Recipe imagery

**Priority:** P2 · **Integration:** `none`

*Recipes display a photograph or image rather than a generic icon.*

**Implementation evidence.** No implementation found. Recipe carries an optional symbolName used as an SF Symbol, documented in the model as 'no photo pipeline in this phase'. The asset catalogue contains only AppIcon and AccentColor.

**Source files.** `FridgeFit/Domain/Models/Recipe.swift:24`, `FridgeFit/Views/Support/RecipePresentation.swift:34`

**Tests.** None.

**Missing.** Image URLs or assets, async loading, placeholder and failure states, and caching.

**Remaining work.** Add an image reference to Recipe and render with AsyncImage; most naturally delivered together with CD-RECIPE-05.

**Risks.** Purely presentational.

**Caveats.** SF Symbols are used consistently and legibly today, so the absence reads as a deliberate scope choice rather than an unfinished screen.

#### ⬜ `CD-RECIPE-08` — Favourites, saved recipes and cooking history

**Priority:** P2 · **Integration:** `none`

*The user can save or favourite recipes and see what they have cooked before.*

**Implementation evidence.** No implementation found. A search for favorite / favourite / markAsCooked across all production sources returns nothing. Firestore holds only the pantry subcollection.

**Source files.** —

**Tests.** None.

**Missing.** Domain model, Firestore collection and rules, use cases, and UI.

**Remaining work.** Add a users/{uid}/favourites subcollection with matching security rules, a repository and use case, and a toggle on RecipeDetailView.

**Risks.** None; purely additive.

**Caveats.** Not confirmed as a requirement.

#### ⬜ `CD-RECIPE-09` — Deduct ingredients from the pantry after cooking

**Priority:** P1 · **Integration:** `none`

*Marking a recipe as cooked subtracts the ingredients it used from the pantry, closing the loop between recipes and pantry state.*

**Implementation evidence.** No implementation found. No 'cook' or 'consume' action exists on RecipeDetailView, and no use case decrements pantry quantities. Quantities change only through UpdatePantryItemUseCase, driven by a manual form.

**Source files.** `FridgeFit/Views/Recipes/RecipeDetailView.swift:24`

**Tests.** None.

**Missing.** A ConsumeRecipeIngredientsUseCase, unit-aware subtraction, a decision about what to do with unconvertible units and with quantities that would go negative, and a UI action.

**Remaining work.** Add the use case and a 'Cooked this' action; reuse MeasurementUnit.convert and refuse to deduct where conversion returns nil, consistent with how the rest of the app fails closed.

**Risks.** This is what makes the pantry stay accurate over time. Without it, pantry quantities drift from reality the moment the user cooks anything, which in turn degrades every feasibility verdict and every AI suggestion. It is the highest-value missing feature found in this audit.

**Caveats.** Not confirmed as a requirement, but it is the natural completion of the pantry/recipe loop the rest of the app is built around.

### AI Recipe Suggestions

#### ⬜ `CD-AI-04` — Acting on a generated suggestion

**Priority:** P2 · **Integration:** `none`

*The user can do something with a suggestion they like — save it as a recipe, or add its missing ingredients to a shopping list.*

**Implementation evidence.** No implementation found. SuggestionRow in PantryRecipeIdeasView is display-only: name, time, availability labels and instructions, with no action. No shopping-list type exists anywhere in the codebase.

**Source files.** `FridgeFit/Views/Recipes/PantryRecipeIdeasView.swift:101`

**Tests.** None.

**Missing.** Any action on a suggestion, and the shopping-list or saved-recipe feature it would feed.

**Remaining work.** Decide the destination first (saved recipes per CD-RECIPE-08, or a shopping list), then add the action.

**Risks.** Suggestions are currently transient — not persisted, and regenerated on every sheet open — so a useful idea is lost as soon as the sheet closes.

**Caveats.** Not confirmed as a requirement.

### Ingredient Substitution

#### ⬜ `CD-SUBST-06` — Apply a substitution to the recipe

**Priority:** P2 · **Integration:** `none`

*The user can accept a substitution so the recipe's feasibility is recomputed with the substitute in place of the original ingredient.*

**Implementation evidence.** No implementation found. SubstitutionSuggestionCard is display-only — name, status, detail, explanation, limitations — with no accept action. Nothing in RecipeViewModel or EvaluateRecipeFeasibilityUseCase accepts a substitution, and the feasibility use case documents itself as doing 'no substitutions, just a deterministic comparison'.

**Source files.** `FridgeFit/Views/Support/SubstitutionPresentation.swift:70`, `FridgeFit/UseCases/EvaluateRecipeFeasibilityUseCase.swift:14`

**Tests.** None.

**Missing.** An accept action, a per-recipe substitution state, and a feasibility evaluation that can take substitutions into account.

**Remaining work.** Add an accepted-substitutions map keyed by recipe and ingredient, and extend EvaluateRecipeFeasibilityUseCase to consult it. Care is needed to keep the deterministic verdict explainable once an LLM suggestion can influence it.

**Risks.** Today a substitution is advice the user acts on in their head. Letting a model-sourced suggestion change a 'Not makeable' verdict to 'Makeable' would put LLM output into the one judgement the app currently derives entirely from its own data — a deliberate architectural line that should be crossed consciously, if at all.

**Caveats.** Not confirmed as a requirement. Arguably correct to leave as-is.

### User Profile

#### ⬜ `CD-PROFILE-03` — Dietary preferences and restrictions profile

**Priority:** P1 · **Integration:** `none`

*The user records dietary preferences, restrictions or allergies, which the rest of the app respects.*

**Implementation evidence.** No implementation found. ProfileView has no settings of any kind. No dietary model, no Firestore collection and no UI exists; the only trace anywhere in the codebase is the unpopulated dietaryRestrictions parameter threaded through the substitution path (see CD-SUBST-05).

**Source files.** `FridgeFit/Views/ProfileView.swift:12`, `FridgeFit/Domain/Models/SubstitutionRequest.swift:31`

**Tests.** None.

**Missing.** Domain model, Firestore persistence at users/{uid} with matching security rules, a Profile editing screen, and a read path into GetIngredientSubstitutionsUseCase.

**Remaining work.** Model the preferences, persist them per user, add the Profile UI, and pass them from SubstitutionViewModel into the use case. The substitution side already honours them.

**Risks.** This single absence is what makes CD-SUBST-05 inert, and it is the most load-bearing missing feature in the Profile area. It is also the only gap in this audit with a safety dimension: a user cannot tell the app about an allergy. Note that the existing keyword check is explicitly not an allergen database, so this should not be presented to users as allergy protection without a stronger mechanism.

**Caveats.** The downstream hook already exists and is tested, so the remaining work is the profile itself rather than the enforcement.

#### ⬜ `CD-PROFILE-04` — Editable display name and avatar

**Priority:** P2 · **Integration:** `none`

*The user can set a display name and profile photo.*

**Implementation evidence.** No implementation found. ProfileView shows a static SF Symbol and the email address. No reference to displayName, photoURL or createProfileChangeRequest exists anywhere in the codebase.

**Source files.** `FridgeFit/Views/ProfileView.swift:17`

**Tests.** None.

**Missing.** Profile editing UI and the Firebase profile-update calls.

**Remaining work.** Add an edit screen writing through Auth's profile change request, or store the fields in Firestore alongside the dietary profile.

**Risks.** None.

**Caveats.** Not confirmed as a requirement. Notably, a Google sign-in already supplies a display name and photo URL that the app currently discards.

#### ⬜ `CD-PROFILE-05` — Account management: change password, delete account

**Priority:** P1 · **Integration:** `none`

*The user can change their password and delete their account together with its data.*

**Implementation evidence.** No implementation found. Searches for updatePassword, reauthenticate and a user delete call return nothing. ProfileView's only action is Sign Out.

**Source files.** `FridgeFit/Views/ProfileView.swift:23`

**Tests.** None.

**Missing.** Change-password flow with reauthentication, account deletion, and cascade deletion of the user's Firestore pantry subcollection.

**Remaining work.** Add both flows. Account deletion needs a decision about the pantry data — Firestore does not delete subcollections with a parent document, so this needs either a client-side sweep or a Cloud Function.

**Risks.** Account deletion is a privacy expectation and, in several jurisdictions, a legal one for a consumer app that stores personal data. Leaving an orphaned pantry subcollection behind after deletion would be a data-retention problem.

**Caveats.** Scope depends on whether FridgeFit is intended to ship publicly, which the inaccessible Notion specification would clarify.

#### ⬜ `CD-PROFILE-06` — App settings and preferences

**Priority:** P2 · **Integration:** `none`

*The user can configure app behaviour — preferred units, appearance, notifications, or an Apple Intelligence status indicator.*

**Implementation evidence.** No implementation found. No settings screen, no UserDefaults usage and no preference model anywhere in the codebase.

**Source files.** `FridgeFit/Views/ProfileView.swift:12`

**Tests.** None.

**Missing.** Settings UI and a preference store.

**Remaining work.** Decide which settings matter. A visible Apple Intelligence availability indicator would be genuinely useful here: AppleIntelligenceAvailability already produces user-facing titles and explanations, but they are only ever shown inside a feature the user has already tried and found unavailable.

**Risks.** None.

**Caveats.** Not confirmed as a requirement. The availability-indicator idea is a recommendation, not a verified missing requirement.

### Testing & Infrastructure

#### ⬜ `CD-INFRA-05` — UI, integration and end-to-end tests

**Priority:** P1 · **Integration:** `none`

*Automated tests exercise real user journeys through the UI and real integrations, not only units behind doubles.*

**Implementation evidence.** No implementation found. There is no UI test target: the project defines exactly two targets, FridgeFit and FridgeFitTests, and a search for XCUIApplication across all Swift sources returns nothing. No Firebase Emulator Suite configuration or integration test exists. Every one of the 240 tests is a unit test running against doubles.

**Source files.** `FridgeFit.xcodeproj/project.pbxproj`

**Tests.** None.

**Missing.** A UI test target and journey tests (sign in -> add pantry item -> browse recipes -> open a recipe), plus emulator-backed integration tests for Firestore CRUD and rules.

**Remaining work.** Add a UI test target with two or three high-value journeys, and emulator tests for the four Firestore operations. These would close CD-PANTRY-06, CD-PANTRY-07 and part of CD-AUTH-09 at once.

**Risks.** This is the structural reason so much of this audit reads needs_verification. Excellent unit coverage proves each part behaves correctly in isolation; nothing proves the parts work together against real services. The scan-to-Firestore path (CD-SCAN-10) is the clearest casualty.

**Caveats.** Some of this cannot be automated — the Apple Intelligence paths need real hardware — but Firestore and authentication are both automatable today with the emulator suite.

#### ⬜ `CD-INFRA-06` — Continuous integration

**Priority:** P2 · **Integration:** `none`

*The test suite runs automatically on every push or pull request.*

**Implementation evidence.** No implementation found. The repository has no .github directory and no CI configuration of any kind (no Xcode Cloud workflow, Fastlane, Bitrise or similar). git history shows the feature-branch-and-merge discipline a CI pipeline would normally gate — six feature branches merged into main — but nothing ran automatically.

**Source files.** —

**Tests.** None.

**Missing.** A workflow that builds and tests on a macOS runner.

**Remaining work.** Add a GitHub Actions workflow running xcodebuild test on an iOS 26.1 simulator. Two prerequisites first: commit a shared Xcode scheme (CD-INFRA-07), and handle the gitignored GoogleService-Info.plist and Secrets.xcconfig, since the app target will not build without the former.

**Risks.** With 240 tests and no automation, a regression is caught only when someone remembers to run the suite locally.

**Caveats.** The secrets arrangement that is correct for a public repository (CD-INFRA-03) is exactly what makes CI setup non-trivial — the runner needs the Firebase config injected from a secret.

#### ⬜ `CD-INFRA-07` — Shared Xcode scheme for reproducible builds

**Priority:** P2 · **Integration:** `none`

*The build and test configuration is committed so any machine or CI runner builds the project identically.*

**Implementation evidence.** No shared scheme is committed. A search for *.xcscheme under FridgeFit.xcodeproj returns nothing; the only scheme data is xcuserdata/kai.xcuserdatad/xcschemes/xcschememanagement.plist, and xcuserdata/ is gitignored. The scheme used by this audit's test run was autocreated by Xcode. Separately, the working tree has an uncommitted change adding DEVELOPMENT_TEAM to both build configurations in project.pbxproj — a machine-specific signing identity sitting in a shared file.

**Source files.** `FridgeFit.xcodeproj/xcuserdata/`, `FridgeFit.xcodeproj/project.pbxproj`

**Tests.** None.

**Missing.** A shared FridgeFit.xcscheme under xcshareddata/xcschemes/, with the test target's membership recorded explicitly.

**Remaining work.** Mark the scheme Shared in Xcode and commit it. Decide whether the uncommitted DEVELOPMENT_TEAM change belongs in version control; a developer-specific team id in a shared pbxproj breaks other developers' builds.

**Risks.** Without a shared scheme, xcodebuild on another machine relies on autocreation, which may not include the test target. This is a prerequisite for CI.

**Caveats.** Autocreation worked on this machine, so the gap is reproducibility elsewhere rather than a broken build here.

#### ⬜ `CD-INFRA-09` — Localization

**Priority:** P2 · **Integration:** `none`

*User-facing text is localisable rather than hardcoded.*

**Implementation evidence.** No implementation found. No .lproj directories, no Localizable.strings and no String Catalog (.xcstrings) exist. Every user-facing string is an inline English literal, including all seven LocalizedError types' errorDescription values. Some locale awareness is present where it matters most — ListFormatter.localizedString for the scan summary, and Vision recognition languages preferring en-AU — but the strings themselves are fixed.

**Source files.** `FridgeFit/Domain/Errors/`, `FridgeFit/UseCases/AddDetectedIngredientsUseCase.swift:42`

**Tests.** None.

**Missing.** A String Catalog and extraction of all literals.

**Remaining work.** Add a String Catalog and migrate strings, starting with the error types since they are the most numerous and the most user-visible.

**Risks.** Low for an English-market product. Note that the domain is Australian-specific in several places by design — the canonicaliser's dialect table, the receipt parser's metadata words, the prompt's abbreviation list — so localisation would mean more than translating strings.

**Caveats.** Not confirmed as a requirement, and reasonable to defer.

#### ⬜ `CD-INFRA-10` — Analytics and crash reporting

**Priority:** P2 · **Integration:** `none`

*Production failures and usage are observable.*

**Implementation evidence.** No implementation found. Only FirebaseAuth, FirebaseCore and FirebaseFirestore are linked — no Crashlytics, no Analytics, no Performance Monitoring. OSLog is used well for diagnostics in VisionReceiptTextRecognizer, AppleReceiptIngredientInterpreter and AppleRecipeSuggestionService, but those logs stay on the device.

**Source files.** `FridgeFit.xcodeproj/project.pbxproj`, `FridgeFit/Data/VisionReceiptTextRecognizer.swift:59`

**Tests.** None.

**Missing.** Crash reporting and any usage telemetry.

**Remaining work.** Add Crashlytics if the app is to be distributed. Analytics is a product and privacy decision, not a technical one.

**Risks.** Without crash reporting, a device-specific failure in the Apple Intelligence paths — exactly the code this audit could not verify — would be invisible after release.

**Caveats.** ReceiptScanDiagnostics deliberately uses print rather than Logger, behind #if DEBUG, with the reasoning documented: a receipt records what someone bought, where and when, and the unified log persists on device and is collectable in a sysdiagnose. That is a thoughtful privacy decision and any future telemetry should preserve it.

---

## E2. Needs verification & blocked (15)

These have implementations that read correct on inspection. They are listed separately because **this audit could not establish their correctness**, and a report that folded them into *Completed* would be claiming evidence it does not have.

### Authentication

#### 🔍 `CD-AUTH-01` — Email & password registration · *Needs Verification*

**Priority:** P0 · **Integration:** `production`

*A new user can create a FridgeFit account with an email address and password, and is signed in immediately afterwards.*

**Implementation evidence.** RegisterView collects email, password and confirmation and calls AuthViewModel.signUp, which calls Auth.auth().createUser(withEmail:password:) and publishes the resulting user. The sheet dismisses itself only once isAuthenticated is true. Errors surface as error.localizedDescription in the form.

**Source files.** `FridgeFit/RegisterView.swift:61`, `FridgeFit/AuthViewModel.swift:47`

**Tests.** None.

**What is unverified.** No automated test of any kind covers AuthViewModel. No runtime evidence of a successful registration against the live Firebase project was produced in this audit.

**How to verify.** Add AuthViewModel unit tests behind an injectable auth abstraction (Auth.auth() is called as a global singleton today, so the type is not testable as written). Then confirm one real registration end to end.

**Risks.** AuthViewModel reaches Auth.auth() directly in init and in every method, which is why it has no tests. Making it testable is a small refactor of production code and therefore out of scope for this audit.

**Caveats.** GoogleService-Info.plist is gitignored, so a fresh clone cannot authenticate at all until the Firebase config is supplied.

#### 🔍 `CD-AUTH-02` — Email & password sign-in · *Needs Verification*

**Priority:** P0 · **Integration:** `production`

*A returning user signs in with email and password and lands on the authenticated app.*

**Implementation evidence.** LoginView gates its submit button on non-empty email and password and on !isLoading, shows a ProgressView while in flight, and renders authViewModel.errorMessage inline. AuthViewModel.signIn calls Auth.auth().signIn(withEmail:password:).

**Source files.** `FridgeFit/LoginView.swift:49`, `FridgeFit/AuthViewModel.swift:35`

**Tests.** None.

**What is unverified.** No tests; no executed runtime evidence.

**How to verify.** Same injectable-auth refactor as CD-AUTH-01, then a sign-in unit test and one manual confirmation.

**Risks.** Low implementation risk; the flow is conventional.

**Caveats.** Email format is not validated client-side; a malformed address produces a Firebase error string rather than inline guidance.

#### 🔍 `CD-AUTH-03` — Google Sign-In via Firebase Auth · *Needs Verification*

**Priority:** P1 · **Integration:** `production`

*The user can sign in with a Google account instead of email and password.*

**Implementation evidence.** GoogleSignInButton on LoginView calls AuthViewModel.signInWithGoogle, which resolves the key window's root view controller, presents GIDSignIn, extracts the ID token, builds a GoogleAuthProvider credential and signs in to Firebase. FridgeFitApp configures GIDConfiguration from the Firebase clientID at launch and forwards callback URLs via onOpenURL. The reversed-client URL scheme is registered in Info.plist.

**Source files.** `FridgeFit/LoginView.swift:69`, `FridgeFit/AuthViewModel.swift:59`, `FridgeFit/FridgeFitApp.swift:18`, `FridgeFit/Info.plist`

**Tests.** None.

**What is unverified.** No tests; no executed runtime evidence. The Google OAuth flow cannot be exercised without the gitignored GoogleService-Info.plist and a consenting Google account.

**How to verify.** Confirm one real Google sign-in on a device or simulator with the Firebase config in place.

**Risks.** The presenting-view-controller lookup uses first(where: isKeyWindow) on connectedScenes. This is the common pattern but can fail in multi-scene or iPad split-view contexts, in which case the user sees 'Unable to find a view to present Google Sign-In.'

**Caveats.** Explicit failure messages exist for both the missing-presenter and missing-ID-token cases, so neither fails silently.

#### 🔍 `CD-AUTH-04` — Session persistence and auth-state routing · *Needs Verification*

**Priority:** P0 · **Integration:** `production`

*A signed-in session survives app relaunch, and the root of the app switches between the login screen and the authenticated tabs automatically.*

**Implementation evidence.** AuthViewModel seeds user from Auth.auth().currentUser in init and registers addStateDidChangeListener, removing the handle in deinit. FridgeFitApp's WindowGroup renders ContentView or LoginView on isAuthenticated, so the switch is driven by Firebase's own state rather than by navigation.

**Source files.** `FridgeFit/AuthViewModel.swift:22`, `FridgeFit/FridgeFitApp.swift:26`

**Tests.** None.

**What is unverified.** No tests; relaunch persistence not demonstrated at runtime in this audit.

**How to verify.** Confirm relaunch persistence manually, and confirm the pantry re-scopes correctly after an account switch.

**Risks.** ContentView builds FirestorePantryRepository once in init. The repository reads Auth.auth().currentUser?.uid lazily on every call, so it does follow an account change; but ContentView's @StateObject view models are not rebuilt on sign-out/sign-in within one app session, so stale in-memory lists and the SubstitutionCache could outlive a user switch. This is a real, untested scenario.

**Caveats.** Worth explicitly testing: sign out, sign in as a different user, and confirm the Pantry tab shows the second user's data.

#### 🔍 `CD-AUTH-05` — Sign out · *Needs Verification*

**Priority:** P0 · **Integration:** `production`

*The user can sign out, which returns the app to the login screen and clears the Google session.*

**Implementation evidence.** ProfileView's destructive Sign Out button calls AuthViewModel.signOut, which calls Auth.auth().signOut(), GIDSignIn.sharedInstance.signOut() and clears user, causing the root Group to render LoginView.

**Source files.** `FridgeFit/Views/ProfileView.swift:23`, `FridgeFit/AuthViewModel.swift:90`

**Tests.** None.

**What is unverified.** No tests; no executed runtime evidence.

**How to verify.** Confirm manually, including the account-switch case described in CD-AUTH-04.

**Risks.** See CD-AUTH-04 regarding view-model and cache lifetime across a sign-out within one session.

**Caveats.** No confirmation prompt before signing out, which is a deliberate-looking choice rather than a defect.

### Pantry Management

#### 🔍 `CD-PANTRY-06` — Per-user Firestore persistence · *Needs Verification*

**Priority:** P0 · **Integration:** `production`

*Each user's pantry persists in Cloud Firestore, scoped to their own Firebase UID, and is never readable or writable by another account.*

**Implementation evidence.** FirestorePantryRepository resolves users/{uid}/pantry from an injectable userIDProvider that defaults to Auth.auth().currentUser?.uid, and throws PantryRepositoryError.notAuthenticated rather than ever falling back to an unscoped path. Reads are ordered by ingredientName. Creates write both createdAt and updatedAt as FieldValue.serverTimestamp(); updates deliberately omit createdAt so an edit cannot reset the creation time. Updates and deletes check document existence first and map to the domain's own itemNotFound / pantryItemNotFound errors. ContentView injects this repository into every pantry-touching view model, so this is the production path.

**Source files.** `FridgeFit/Data/FirestorePantryRepository.swift:32`, `FridgeFit/Data/FirestorePantryRepository.swift:74`, `FridgeFit/ContentView.swift:20`

**Tests (8, all passing).**

- `FridgeFitTests/Data/FirestorePantryRepositoryMappingTests.swift: test_decode_succeeds_withCompleteValidData`
- `FridgeFitTests/Data/FirestorePantryRepositoryMappingTests.swift: test_decode_fails_whenDocumentIDIsNotAUUID`
- `FridgeFitTests/Data/FirestorePantryRepositoryMappingTests.swift: test_decode_fails_whenCategoryIsUnrecognised`
- `FridgeFitTests/Data/FirestorePantryRepositoryMappingTests.swift: test_decode_fails_whenUnitIsUnrecognised`
- `FridgeFitTests/Data/FirestorePantryRepositoryMappingTests.swift: test_decode_fails_whenRequiredFieldIsMissing`
- `FridgeFitTests/Data/FirestorePantryRepositoryMappingTests.swift: test_encodeForCreate_includesAllFieldsAndBothTimestamps`
- `FridgeFitTests/Data/FirestorePantryRepositoryMappingTests.swift: test_encodeForUpdate_omitsCreatedAt_soItIsNeverOverwritten`
- `FridgeFitTests/Data/FirestorePantryRepositoryMappingTests.swift: test_decode_isInverseOf_encodeForCreate_forNonTimestampFields`

**What is unverified.** Only the pure encode/decode helpers are tested. No test exercises fetchAll, add, update or remove against Firestore — not against a live project, and not against the Firebase Emulator Suite. The eight tests prove the field mapping is correct and self-consistent; they prove nothing about whether a write reaches Firestore.

**How to verify.** Add Firebase Emulator Suite integration tests covering the four CRUD operations plus the notAuthenticated path, or record a documented manual end-to-end pass. firebase.json already exists, so emulator configuration is a short step.

**Risks.** This is the project's single most important unverified integration: every other feature's persistence runs through it. A decode that silently returns nil (the compactMap in fetchAll drops undecodable documents without surfacing anything) would present as an item quietly disappearing from the pantry.

**Caveats.** The injectable userIDProvider makes emulator testing straightforward — the seam already exists and is simply unused by the suite.

#### 🔍 `CD-PANTRY-07` — Firestore security rules scoping the pantry to its owner · *Needs Verification*

**Priority:** P0 · **Integration:** `production-rules-authored`

*Server-side rules guarantee a signed-in user can read and write only their own pantry, and everything else is denied.*

**Implementation evidence.** firestore.rules matches /users/{uid}/pantry/{pantryItemId} and allows read, write only when request.auth != null && request.auth.uid == uid, followed by a catch-all /{document=**} deny. firebase.json points the firestore.rules and firestore.indexes.json keys at those files.

**Source files.** `firestore.rules:8`, `firebase.json:2`

**Tests.** None.

**What is unverified.** No evidence the rules have ever been deployed to the Firebase project, and no rules unit tests. The repository contains the correct rules; it does not demonstrate that the live project enforces them.

**How to verify.** Run `firebase deploy --only firestore:rules` against the project and add @firebase/rules-unit-testing cases asserting that user A cannot read user B's pantry.

**Risks.** If the live project is still on default or test-mode rules, every user's pantry is readable by any authenticated client regardless of what this file says. The client-side uid scoping in FirestorePantryRepository is a correctness measure, not a security boundary.

**Caveats.** The rules themselves read correctly and deny by default, which is the right shape.

### AI Recipe Suggestions

#### 🔍 `CD-AI-01` — On-device recipe ideas generated from the pantry · *Needs Verification*

**Priority:** P1 · **Integration:** `production`

*The user gets recipe ideas generated from what is actually in their pantry, computed on-device with Apple Intelligence.*

**Implementation evidence.** AppleRecipeSuggestionService uses FoundationModels guided generation into @Generable GeneratedRecipeIdeas (max 5 recipes, 2–12 ingredients each, temperature 0.4), with session instructions that forbid hiding a missing ingredient and forbid the model asserting pantry contents. SuggestRecipesFromPantryUseCase reads the pantry, calls the service and validates the result. RecipeSuggestionViewModel guards against concurrent runs with a monotonic token so a superseded request cannot publish, and distinguishes an empty result from an error. PantryRecipeIdeasView is presented as a sheet from the Recipes toolbar and renders unavailable, loading, error, empty and populated states. Wired in ContentView.

**Source files.** `FridgeFit/Data/AppleRecipeSuggestionService.swift:90`, `FridgeFit/UseCases/SuggestRecipesFromPantryUseCase.swift:37`, `FridgeFit/ViewModels/RecipeSuggestionViewModel.swift:50`, `FridgeFit/Views/Recipes/PantryRecipeIdeasView.swift:15`, `FridgeFit/ContentView.swift:38`

**Tests (6, all passing).**

- `FridgeFitTests/UseCases/SuggestRecipesFromPantryUseCaseTests.swift: test_suggestRecipes_mapsStructuredResultOntoSuggestions`
- `FridgeFitTests/UseCases/SuggestRecipesFromPantryUseCaseTests.swift: test_suggestRecipes_sendsRealPantryToService`
- `FridgeFitTests/UseCases/SuggestRecipesFromPantryUseCaseTests.swift: test_suggestRecipes_returnsEmpty_forEmptyPantry`
- `FridgeFitTests/UseCases/SuggestRecipesFromPantryUseCaseTests.swift: test_loadSuggestions_exposesSuggestions`
- `FridgeFitTests/UseCases/SuggestRecipesFromPantryUseCaseTests.swift: test_loadSuggestions_reportsEmptyResult`
- `FridgeFitTests/UseCases/SuggestRecipesFromPantryUseCaseTests.swift: test_loadSuggestions_setsUserFacingError_whenServiceThrows`

**What is unverified.** Every test runs against MockRecipeSuggestionService. AppleRecipeSuggestionService itself — the @Generable schema, the SystemLanguageModel call, the availability mapping and the GenerationError mapping — has no test and was not executed in this audit. The iOS Simulator provides no system language model, so this code path cannot run there at all.

**How to verify.** Run the feature on an Apple Intelligence-capable device with Apple Intelligence enabled, and record what the model actually returns for a representative pantry. Judge usefulness, latency and refusal behaviour from that evidence, not from the prompt.

**Risks.** Device and OS gated: requires hardware eligible for Apple Intelligence (iPhone 15 Pro or later, or an M-series iPad/Mac), iOS 26.x, the feature enabled in Settings, and the model assets downloaded. On any other device the feature is permanently unavailable. The app handles this correctly (see CD-AI-03) but the capability is not universally available to users.

**Caveats.** Prompt quality cannot be assessed statically. The instructions are well targeted at the known failure mode, but whether the model follows them is an empirical question this audit did not answer.

### Receipt Scanning

#### 🔍 `CD-SCAN-01` — Capture or choose a receipt photo · *Needs Verification*

**Priority:** P0 · **Integration:** `production`

*The user photographs a grocery receipt with the camera or picks an existing photo from their library.*

**Implementation evidence.** ReceiptScannerView offers Take Photo and Choose from Library. The camera path resolves permission through CameraAccess.request() before presenting, distinguishing granted, denied and unavailable (no camera, e.g. Simulator) and showing an explanation rather than a black viewfinder. CameraPicker wraps UIImagePickerController and calls onFailure when a capture yields no usable image. The library path uses PhotosPicker, loading bytes off the main actor and reporting a load failure through the scanner's normal error surface. Both funnel into ReceiptScannerViewModel.selectImage, which cancels any in-flight scan so results cannot describe the previous photo.

**Source files.** `FridgeFit/Views/Scanner/ReceiptScannerView.swift:150`, `FridgeFit/Views/Scanner/CameraPicker.swift:29`, `FridgeFit/Views/Scanner/CameraPicker.swift:88`, `FridgeFit/ViewModels/ReceiptScannerViewModel.swift:118`

**Tests (1, all passing).**

- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift: test_selectingANewImage_discardsTheInFlightScan`

**What is unverified.** No automated coverage of CameraPicker, CameraAccess or the PhotosPicker path — all three are UIKit/PhotoKit integration points with no test double. Camera capture cannot be exercised on the Simulator.

**How to verify.** Confirm on a physical device: capture, permission-denied, retake, and library selection including a HEIC photo and a non-image item.

**Risks.** Scanning requires selectedImage.cgImage to be non-nil. Some library images (notably certain HEIC or CIImage-backed representations) have no backing CGImage, which would surface as 'That photo couldn't be read' for a photo the user can plainly see. Untested.

**Caveats.** Permission is resolved before presentation, which is the correct order and avoids the common black-viewfinder bug.

#### 🔍 `CD-SCAN-02` — On-device OCR of the receipt with row stitching · *Needs Verification*

**Priority:** P0 · **Integration:** `production`

*Vision reads the receipt's text on-device, in reading order, reassembling the description and price columns into single lines.*

**Implementation evidence.** VisionReceiptTextRecognizer configures RecognizeTextRequest at .accurate with usesLanguageCorrection = false (deliberate, and the reasoning is documented: correction rewrites CHKN and CAPS toward real dictionary words and the interpreter then faithfully reads the wrong product), minimumTextHeightFraction lowered to 0.008 so small lines on a whole-receipt photo are not silently skipped, and recognitionLanguages asked of the request rather than hardcoded because forcing an unsupported identifier makes Vision throw. Full-resolution CGImage, no downsampling. Observations are sorted by descending midY (Vision's origin is bottom-left) and grouped into rows by vertical-centre proximity relative to row height, then ordered left-to-right and joined; a row's confidence is its least confident fragment, and rows below 0.3 are dropped. Image orientation is bridged from UIImage.Orientation so camera captures are not read sideways.

**Source files.** `FridgeFit/Data/VisionReceiptTextRecognizer.swift:66`, `FridgeFit/Data/VisionReceiptTextRecognizer.swift:111`, `FridgeFit/ViewModels/ReceiptScannerViewModel.swift:342`

**Tests.** None.

**What is unverified.** VisionReceiptTextRecognizer has no tests at all. Every scan test uses MockReceiptTextRecognizer with pre-written lines, so the row-stitching geometry, the confidence floor, the language selection and the orientation bridge are entirely unexercised.

**How to verify.** Add tests for the row-grouping function against synthetic observations (the geometry is pure and testable once the Vision types are constructed), and run the real recogniser against a set of photographed receipts to measure line recovery.

**Risks.** Row stitching compares each fragment only against the most recent row, so fragments arriving out of expected order could start a spurious new row. The rowGroupingTolerance of 0.6 and confidence floor of 0.3 are unvalidated magic numbers — plausible, but no evidence supports them. OCR quality is the first link in the chain: a line lost here is invisible to the user, which is the exact failure mode the rest of the pipeline is designed to avoid.

**Caveats.** The design decisions here are unusually well reasoned and documented. The gap is empirical validation, not design.

#### 🔍 `CD-SCAN-05` — Apple Intelligence interpretation of receipt lines · *Needs Verification*

**Priority:** P0 · **Integration:** `production`

*The on-device language model reads each cleaned receipt line and says what was purchased, what kind of purchase it is, and its canonical ingredient name — seeing only text, never the photo.*

**Implementation evidence.** AppleReceiptIngredientInterpreter sends ReceiptLineItems (text only; the photo never reaches the model) to SystemLanguageModel via guided generation into @Generable GeneratedReceiptInterpretation. The schema is designed around three decisions: no Optional properties (a not-stated quantity is 0 plus a notStated unit sentinel), enums rather than free strings for classification, category and unit so the model can only emit values the app understands, and originalText echoed back so each interpretation can be matched to the line it came from. Lines go in batches of 12 with a fresh session each, capped at 84 lines per receipt, at temperature 0.1 because creativity here means invented groceries. GenerationError is collapsed to actionable ReceiptScanErrors with details sent to the log rather than the screen. The prompt builder's instructions require one entry per line in order, forbid adding products, cover Australian abbreviations (CHKN, CAPS, MUSH, AVO, BNLS, W/MEAL, ATL), define all six classifications, make 'unknown' a first-class answer over a plausible guess, and forbid estimating or converting quantities.

**Source files.** `FridgeFit/Data/AppleReceiptIngredientInterpreter.swift:79`, `FridgeFit/Data/AppleReceiptIngredientInterpreter.swift:125`, `FridgeFit/Data/GeneratedReceiptInterpretation.swift:28`, `FridgeFit/Data/ReceiptInterpretationPromptBuilder.swift:24`

**Tests (11, all passing).**

- `FridgeFitTests/Data/ReceiptInterpretationPromptBuilderTests.swift: test_makePrompt_includesEveryProductLine`
- `FridgeFitTests/Data/ReceiptInterpretationPromptBuilderTests.swift: test_makePrompt_statesTheExpectedNumberOfEntries`
- `FridgeFitTests/Data/ReceiptInterpretationPromptBuilderTests.swift: test_makePrompt_usesSingularWordingForOneLine`
- `FridgeFitTests/Data/ReceiptInterpretationPromptBuilderTests.swift: test_makePrompt_asksForTheLineToBeEchoedBack`
- `FridgeFitTests/Data/ReceiptInterpretationPromptBuilderTests.swift: test_makePrompt_returnsNil_whenThereAreNoLines`
- `FridgeFitTests/Data/ReceiptInterpretationPromptBuilderTests.swift: test_instructions_forbidInventingProducts`
- `FridgeFitTests/Data/ReceiptInterpretationPromptBuilderTests.swift: test_instructions_preferUnknownOverGuessing`
- `FridgeFitTests/Data/ReceiptInterpretationPromptBuilderTests.swift: test_instructions_coverAustralianAbbreviations`
- `FridgeFitTests/Data/ReceiptInterpretationPromptBuilderTests.swift: test_instructions_defineEveryClassification`
- `FridgeFitTests/Data/ReceiptInterpretationPromptBuilderTests.swift: test_instructions_forbidInventingOrConvertingQuantities`
- `FridgeFitTests/Data/ReceiptInterpretationPromptBuilderTests.swift: test_instructions_describeCanonicalNaming`

**What is unverified.** The 11 tests cover the prompt and instruction text; none covers the interpreter. The @Generable schema, the SystemLanguageModel call, the availability mapping, the GenerationError mapping and the batching loop were not executed, and cannot be on the Simulator.

**How to verify.** Run real scans on an Apple Intelligence-capable device across several receipts and store formats. Measure how often the model echoes originalText exactly (the normaliser discards items it cannot match, so a paraphrasing model silently loses products), how often it returns one entry per line, and how it classifies ambiguous items such as milk and stock.

**Risks.** Same device and OS gating as CD-AI-01. The architecture's main defence — echo matching — depends on the model copying each line back character for character, which is precisely the instruction a model is most likely to drift on. The normaliser's tolerant containment fallback mitigates this, but the real rate is unmeasured.

**Caveats.** Asserting prompt content in tests is an unusual and genuinely useful choice: it guards the instructions that carry the safety properties against accidental edits.

#### 🚧 `CD-SCAN-10` — End-to-end validation: photograph a receipt through to Firestore · *Blocked*

**Priority:** P0 · **Integration:** `production`

*A real receipt, photographed on a real device, is read, interpreted, confirmed and persisted to the signed-in user's Firestore pantry.*

**Implementation evidence.** Every stage of this path exists in production code and the handoffs are consistent on inspection: ReceiptScannerView -> ReceiptScannerViewModel -> ScanReceiptUseCase (OCR -> parse -> interpret -> normalise -> pantry reconciliation) -> ReceiptItemReviewView -> AddDetectedIngredientsUseCase -> AddPantryItemUseCase -> FirestorePantryRepository. ScanReceiptUseCase is covered end to end by 12 tests, but with mock OCR, a mock interpreter and an in-memory pantry at both ends.

**Source files.** `FridgeFit/UseCases/ScanReceiptUseCase.swift:58`, `FridgeFit/ViewModels/ReceiptScannerViewModel.swift:149`, `FridgeFit/Data/FirestorePantryRepository.swift:46`

**Tests (10, all passing).**

- `FridgeFitTests/UseCases/ScanReceiptUseCaseTests.swift: test_execute_turnsAReceiptPhotoIntoPantryCandidates`
- `FridgeFitTests/UseCases/ScanReceiptUseCaseTests.swift: test_execute_extractsQuantitiesOnlyWhereTheReceiptStatesThem`
- `FridgeFitTests/UseCases/ScanReceiptUseCaseTests.swift: test_execute_sendsOnlyCleanedProductLinesToTheInterpreter`
- `FridgeFitTests/UseCases/ScanReceiptUseCaseTests.swift: test_execute_flagsCandidatesAlreadyInThePantry`
- `FridgeFitTests/UseCases/ScanReceiptUseCaseTests.swift: test_execute_throwsNoTextRecognized_whenOCRFindsNothing`
- `FridgeFitTests/UseCases/ScanReceiptUseCaseTests.swift: test_execute_throwsNoProductLines_whenEveryLineIsReceiptFurniture`
- `FridgeFitTests/UseCases/ScanReceiptUseCaseTests.swift: test_execute_throwsNoFoodItems_whenNothingOnTheReceiptIsAnIngredient`
- `FridgeFitTests/UseCases/ScanReceiptUseCaseTests.swift: test_execute_propagatesOCRFailure`
- `FridgeFitTests/UseCases/ScanReceiptUseCaseTests.swift: test_execute_propagatesInterpretationFailure`
- `FridgeFitTests/UseCases/ScanReceiptUseCaseTests.swift: test_execute_isCancellable`

**What is unverified.** Runtime evidence. Three independent prerequisites are unmet in this audit environment simultaneously: a physical device with Apple Intelligence enabled (the Simulator has no system language model), a real camera, and a live Firebase project with the rules deployed. No part of this path has been observed executing against real services.

**How to verify.** Perform and record one documented end-to-end pass on a capable device: photograph a real grocery receipt, confirm the detected items, and verify in the Firebase console that the expected documents appear under users/{uid}/pantry with correct fields and server timestamps.

**Risks.** This is the project's headline feature and the most consequential unverified claim in the report. Unit tests prove every stage is individually correct against doubles; they cannot prove the real OCR output is good enough to parse, that the real model echoes lines faithfully enough to match, or that the Firestore write lands.

**Blocked by.**

- Apple Intelligence-capable physical device running iOS 26.x with the feature enabled
- Live Firebase project credentials (GoogleService-Info.plist is gitignored)
- Deployed Firestore security rules (CD-PANTRY-07)

**Caveats.** Marked blocked rather than needs_verification because the blocker is specific, external and nameable — device hardware plus live credentials — not merely absent effort.

### Ingredient Substitution

#### 🔍 `CD-SUBST-02` — OpenRouter substitution provider · *Needs Verification*

**Priority:** P1 · **Integration:** `production`

*Substitution candidates come from a remote LLM via OpenRouter's OpenAI-compatible chat completions API, with every failure mode mapped to a message written for the user.*

**Implementation evidence.** OpenRouterSubstitutionService POSTs to https://openrouter.ai/api/v1/chat/completions with a 20-second timeout, a Bearer token and optional attribution headers. SubstitutionPromptBuilder is the single place prompt text is constructed; its system prompt restricts the model to culinary substitutions, requires 1–3 ranked suggestions, demands explicit limitations, pins an exact JSON schema and — the important rule — forbids the model from claiming the user has an ingredient or stating a pantry quantity. The response path maps 429 to .rateLimited, non-2xx to .providerUnavailable, URLError.timedOut to .timeout, other URLErrors to .network, and undecodable bodies to .malformedResponse. SubstitutionResponseParser defensively strips a markdown code fence and takes the substring between the first { and last }, tolerating stray prose, but never attempts to repair malformed JSON.

**Source files.** `FridgeFit/Data/OpenRouterSubstitutionService.swift:27`, `FridgeFit/Data/SubstitutionPromptBuilder.swift:29`, `FridgeFit/Data/SubstitutionResponseParser.swift:21`, `FridgeFit/Domain/Errors/SubstitutionServiceError.swift:11`

**Tests (13, all passing).**

- `FridgeFitTests/Data/OpenRouterSubstitutionServiceTests.swift: test_suggestSubstitutions_successfulResponse_decodesRawSuggestions_andSendsAuthHeader`
- `FridgeFitTests/Data/OpenRouterSubstitutionServiceTests.swift: test_suggestSubstitutions_rateLimited_throwsRateLimited`
- `FridgeFitTests/Data/OpenRouterSubstitutionServiceTests.swift: test_suggestSubstitutions_serverError_throwsProviderUnavailable`
- `FridgeFitTests/Data/OpenRouterSubstitutionServiceTests.swift: test_suggestSubstitutions_malformedBody_throwsMalformedResponse`
- `FridgeFitTests/Data/OpenRouterSubstitutionServiceTests.swift: test_suggestSubstitutions_timeout_throwsTimeout`
- `FridgeFitTests/Data/OpenRouterSubstitutionServiceTests.swift: test_suggestSubstitutions_networkError_throwsNetwork`
- `FridgeFitTests/Data/OpenRouterSubstitutionServiceTests.swift: test_unconfiguredSubstitutionService_alwaysThrowsNotConfigured`
- `FridgeFitTests/Data/SubstitutionResponseParserTests.swift: test_parseSuggestions_decodesCleanJSON`
- `FridgeFitTests/Data/SubstitutionResponseParserTests.swift: test_parseSuggestions_toleratesMarkdownCodeFence`
- `FridgeFitTests/Data/SubstitutionResponseParserTests.swift: test_parseSuggestions_toleratesSurroundingProse`
- `FridgeFitTests/Data/SubstitutionResponseParserTests.swift: test_parseSuggestions_malformedJSON_throwsMalformedResponse`
- `FridgeFitTests/Data/SubstitutionResponseParserTests.swift: test_parseSuggestions_validJSON_wrongShape_throwsMalformedResponse`
- `FridgeFitTests/Data/SubstitutionResponseParserTests.swift: test_parseSuggestions_emptySuggestionsArray_returnsEmpty`

**What is unverified.** The seven service tests run against a StubURLProtocol — excellent coverage of the request shape and every error branch, with no network and no quota consumed, but by construction they say nothing about the live provider. The default model (a free-tier Gemma variant) was never called, so real-world latency, refusal rate and JSON-schema compliance are unmeasured.

**How to verify.** With a key configured (CD-SUBST-01), make a handful of real requests and record latency, how often the model honours the JSON-only instruction, and how often it tries to assert pantry availability despite the prompt.

**Risks.** Free-tier OpenRouter models are rate-limited and can be deprecated or withdrawn; the default model string is a hardcoded fallback that will eventually go stale. This is also the only feature that sends data off-device — recipe title, target ingredient and the full pantry ingredient list, which is personal data, though SubstitutionRequest deliberately carries no ids and nothing about the Firebase user.

**Caveats.** Testing a real HTTP client against a stubbed URLProtocol is the right technique and is applied well here. The gap is live validation, not test quality.

### User Profile

#### 🔍 `CD-PROFILE-02` — Sign out from Profile · *Needs Verification*

**Priority:** P0 · **Integration:** `production`

*The Profile tab provides the sign-out action.*

**Implementation evidence.** A destructive-role Sign Out button calling authViewModel.signOut().

**Source files.** `FridgeFit/Views/ProfileView.swift:23`

**Tests.** None.

**What is unverified.** No tests; no executed runtime evidence. Tracked separately from CD-AUTH-05 because the UI placement and the auth behaviour are different concerns.

**How to verify.** Covered by verifying CD-AUTH-05.

**Risks.** See CD-AUTH-04 on view-model and cache lifetime across a sign-out within one app session.

**Caveats.** No confirmation prompt.

### Testing & Infrastructure

#### 🔍 `CD-INFRA-04` — Firestore rules and indexes under version control and deployed · *Needs Verification*

**Priority:** P0 · **Integration:** `production-config-present`

*Backend configuration is versioned alongside the app and matches what the live project enforces.*

**Implementation evidence.** firebase.json, firestore.rules and firestore.indexes.json are all tracked in git. The rules were added deliberately in commit 172a3b0 ('chore(firestore): add security rules scoping pantry to the signed-in user'). firestore.indexes.json is empty, which is consistent with the only query being a single-field order(by: "ingredientName") that Firestore indexes automatically.

**Source files.** `firebase.json`, `firestore.rules`, `firestore.indexes.json`

**Tests.** None.

**What is unverified.** No evidence of deployment. Having the rules in the repository is not the same as the live project enforcing them. See CD-PANTRY-07.

**How to verify.** Deploy and record it; add rules unit tests.

**Risks.** See CD-PANTRY-07 — the security consequence if the live project is still on test-mode rules.

**Caveats.** Versioning backend configuration alongside the app is good practice and is done correctly here.

---

## F. Requirements traceability matrix

All 65 code-derived requirements. IDs are `CD-` prefixed because they are **code-derived, not Notion IDs**. Full evidence for each row is in sections C–E2 above.

| Requirement | Module | Status | Evidence (primary file) | Tests | Remaining work | Priority |
|---|---|---|---|---:|---|---|
| `CD-AUTH-01` Email & password registration | Auth | 🔍 Needs Verification | `FridgeFit/RegisterView.swift:61` | 0 | Add AuthViewModel unit tests behind an injectable auth abstraction (Auth.auth() is called as a global singleton today, so the type is not testable… | P0 |
| `CD-AUTH-02` Email & password sign-in | Auth | 🔍 Needs Verification | `FridgeFit/LoginView.swift:49` | 0 | Same injectable-auth refactor as CD-AUTH-01, then a sign-in unit test and one manual confirmation. | P0 |
| `CD-AUTH-03` Google Sign-In via Firebase Auth | Auth | 🔍 Needs Verification | `FridgeFit/LoginView.swift:69` | 0 | Confirm one real Google sign-in on a device or simulator with the Firebase config in place. | P1 |
| `CD-AUTH-04` Session persistence and auth-state routing | Auth | 🔍 Needs Verification | `FridgeFit/AuthViewModel.swift:22` | 0 | Confirm relaunch persistence manually, and confirm the pantry re-scopes correctly after an account switch. | P0 |
| `CD-AUTH-05` Sign out | Auth | 🔍 Needs Verification | `FridgeFit/Views/ProfileView.swift:23` | 0 | Confirm manually, including the account-switch case described in CD-AUTH-04. | P0 |
| `CD-AUTH-06` Registration input validation | Auth | 🟡 Partially Completed | `FridgeFit/RegisterView.swift:16` | 0 | Add email-format validation; consider extracting the rules into a small testable type to match the pattern used everywhere else in this codebase. | P2 |
| `CD-AUTH-07` Password reset / forgot password | Auth | ⬜ Not Started | — | 0 | Add a 'Forgot password?' control to LoginView, an AuthViewModel.sendPasswordReset(email:) method wrapping Auth.auth().sendPasswordReset, and a… | P1 |
| `CD-AUTH-08` Email verification | Auth | ⬜ Not Started | — | 0 | Decide whether verification is required at all, then send on registration and surface the unverified state on Profile. | P2 |
| `CD-AUTH-09` Automated test coverage for authentication | Auth | ⬜ Not Started | — | 0 | Introduce an auth-service protocol so AuthViewModel can be driven by a double, then test sign-in success, sign-in failure messaging, sign-up,… | P1 |
| `CD-PANTRY-01` View the pantry | Pantry | ✅ Completed | `FridgeFit/Views/Pantry/PantryView.swift:19` | 1 | None | P0 |
| `CD-PANTRY-02` Add a pantry item with validation | Pantry | ✅ Completed | `FridgeFit/UseCases/AddPantryItemUseCase.swift:34` | 5 | None | P0 |
| `CD-PANTRY-03` Duplicate prevention with guided recovery | Pantry | ✅ Completed | `FridgeFit/UseCases/AddPantryItemUseCase.swift:42` | 4 | None | P1 |
| `CD-PANTRY-04` Update an item's quantity and unit | Pantry | ✅ Completed | `FridgeFit/UseCases/UpdatePantryItemUseCase.swift:22` | 5 | None | P0 |
| `CD-PANTRY-05` Remove a pantry item | Pantry | ✅ Completed | `FridgeFit/UseCases/RemovePantryItemUseCase.swift:22` | 4 | None | P0 |
| `CD-PANTRY-06` Per-user Firestore persistence | Pantry | 🔍 Needs Verification | `FridgeFit/Data/FirestorePantryRepository.swift:32` | 8 | Add Firebase Emulator Suite integration tests covering the four CRUD operations plus the notAuthenticated path, or record a documented manual… | P0 |
| `CD-PANTRY-07` Firestore security rules scoping the pantry to its owner | Pantry | 🔍 Needs Verification | `firestore.rules:8` | 0 | Run `firebase deploy --only firestore:rules` against the project and add @firebase/rules-unit-testing cases asserting that user A cannot read user… | P0 |
| `CD-PANTRY-08` Expiry date and freshness tracking | Pantry | ⬜ Not Started | `FridgeFit/Domain/Models/PantryItem.swift:9` | 0 | Add an optional expiryDate to PantryItem, extend the Firestore encode/decode pair and its mapping tests, surface it in the add/update forms and… | P2 |
| `CD-PANTRY-09` Pantry search, filter and sort controls | Pantry | ⬜ Not Started | `FridgeFit/Views/Pantry/PantryView.swift:45` | 0 | Add .searchable plus a category filter to PantryView, with the filtering logic in the view model so it can be tested. | P2 |
| `CD-PANTRY-10` Offline behaviour and cache configuration | Pantry | ⬜ Not Started | `FridgeFit/Data/FirestorePantryRepository.swift:23` | 0 | Decide the offline policy, configure FirestoreSettings deliberately, and give the UI an offline-aware message distinct from a generic failure. | P2 |
| `CD-RECIPE-01` Browse recipes | Recipes | ✅ Completed | `FridgeFit/Views/Recipes/RecipeListView.swift:28` | 4 | None | P0 |
| `CD-RECIPE-02` Recipe detail with ingredients and instructions | Recipes | ✅ Completed | `FridgeFit/Views/Recipes/RecipeDetailView.swift:24` | 2 | None | P0 |
| `CD-RECIPE-03` Recipe feasibility evaluation against the pantry | Recipes | ✅ Completed | `FridgeFit/UseCases/EvaluateRecipeFeasibilityUseCase.swift:28` | 17 | None | P0 |
| `CD-RECIPE-04` Unit conversion for quantity comparison | Recipes | 🟡 Partially Completed | `FridgeFit/Domain/Models/MeasurementUnit+Conversion.swift:18` | 7 | Either add volume ratios for cup/tbsp/tsp (a cup is a defined volume; the ambiguity is ingredient density, not the unit), or restrict the unit… | P2 |
| `CD-RECIPE-05` Remote recipe catalogue | Recipes | ⬜ Not Started | `FridgeFit/Data/BundledRecipeRepository.swift:14` | 0 | Choose a source (a recipe API, or Firestore as the recipe store), implement RecipeRepository against it, and inject it in ContentView. The… | P1 |
| `CD-RECIPE-06` Recipe search and filtering | Recipes | ⬜ Not Started | `FridgeFit/Views/Recipes/RecipeListView.swift:28` | 0 | Add .searchable and a feasibility filter, with the predicate in RecipeViewModel so it is testable. | P2 |
| `CD-RECIPE-07` Recipe imagery | Recipes | ⬜ Not Started | `FridgeFit/Domain/Models/Recipe.swift:24` | 0 | Add an image reference to Recipe and render with AsyncImage; most naturally delivered together with CD-RECIPE-05. | P2 |
| `CD-RECIPE-08` Favourites, saved recipes and cooking history | Recipes | ⬜ Not Started | — | 0 | Add a users/{uid}/favourites subcollection with matching security rules, a repository and use case, and a toggle on RecipeDetailView. | P2 |
| `CD-RECIPE-09` Deduct ingredients from the pantry after cooking | Recipes | ⬜ Not Started | `FridgeFit/Views/Recipes/RecipeDetailView.swift:24` | 0 | Add the use case and a 'Cooked this' action; reuse MeasurementUnit.convert and refuse to deduct where conversion returns nil, consistent with how… | P1 |
| `CD-AI-01` On-device recipe ideas generated from the pantry | AI Suggestions | 🔍 Needs Verification | `FridgeFit/Data/AppleRecipeSuggestionService.swift:90` | 6 | Run the feature on an Apple Intelligence-capable device with Apple Intelligence enabled, and record what the model actually returns for a… | P1 |
| `CD-AI-02` Pantry-authoritative availability split on suggestions | AI Suggestions | ✅ Completed | `FridgeFit/UseCases/SuggestRecipesFromPantryUseCase.swift:65` | 7 | None | P0 |
| `CD-AI-03` Apple Intelligence unavailable-state handling | AI Suggestions | ✅ Completed | `FridgeFit/Domain/Models/AppleIntelligenceAvailability.swift:30` | 5 | None | P0 |
| `CD-AI-04` Acting on a generated suggestion | AI Suggestions | ⬜ Not Started | `FridgeFit/Views/Recipes/PantryRecipeIdeasView.swift:101` | 0 | Decide the destination first (saved recipes per CD-RECIPE-08, or a shopping list), then add the action. | P2 |
| `CD-SCAN-01` Capture or choose a receipt photo | Scanner | 🔍 Needs Verification | `FridgeFit/Views/Scanner/ReceiptScannerView.swift:150` | 1 | Confirm on a physical device: capture, permission-denied, retake, and library selection including a HEIC photo and a non-image item. | P0 |
| `CD-SCAN-02` On-device OCR of the receipt with row stitching | Scanner | 🔍 Needs Verification | `FridgeFit/Data/VisionReceiptTextRecognizer.swift:66` | 0 | Add tests for the row-grouping function against synthetic observations (the geometry is pure and testable once the Vision types are constructed),… | P0 |
| `CD-SCAN-03` Deterministic receipt line parsing | Scanner | ✅ Completed | `FridgeFit/Data/ReceiptLineParser.swift:71` | 19 | None | P0 |
| `CD-SCAN-04` Deterministic quantity extraction from receipt text | Scanner | ✅ Completed | `FridgeFit/Data/ReceiptQuantityParser.swift:44` | 14 | None | P0 |
| `CD-SCAN-05` Apple Intelligence interpretation of receipt lines | Scanner | 🔍 Needs Verification | `FridgeFit/Data/AppleReceiptIngredientInterpreter.swift:79` | 11 | Run real scans on an Apple Intelligence-capable device across several receipts and store formats. Measure how often the model echoes originalText… | P0 |
| `CD-SCAN-06` Deterministic normalisation and anti-hallucination of model output | Scanner | ✅ Completed | `FridgeFit/UseCases/ReceiptItemNormalizer.swift:53` | 25 | None | P0 |
| `CD-SCAN-07` Ingredient name canonicalisation | Scanner | ✅ Completed | `FridgeFit/UseCases/IngredientCanonicalizer.swift:172` | 18 | None | P1 |
| `CD-SCAN-08` Review and correct detected items before saving | Scanner | ✅ Completed | `FridgeFit/Views/Scanner/ReceiptItemReviewView.swift:24` | 15 | None | P0 |
| `CD-SCAN-09` Add confirmed items to the pantry with per-item outcomes | Scanner | ✅ Completed | `FridgeFit/UseCases/AddDetectedIngredientsUseCase.swift:82` | 9 | None | P0 |
| `CD-SCAN-10` End-to-end validation: photograph a receipt through to Firestore | Scanner | 🚧 Blocked | `FridgeFit/UseCases/ScanReceiptUseCase.swift:58` | 10 | Perform and record one documented end-to-end pass on a capable device: photograph a real grocery receipt, confirm the detected items, and verify… | P0 |
| `CD-SCAN-11` Camera permission handling and usage description | Scanner | 🟡 Partially Completed | `FridgeFit/Views/Scanner/CameraPicker.swift:88` | 0 | Update NSCameraUsageDescription and CameraAccess.denied's explanation to describe receipt photography. Both are user-visible strings, one of them… | P1 |
| `CD-SUBST-01` Find a substitute for an unavailable recipe ingredient | Substitution | 🟡 Partially Completed | `FridgeFit/Views/Recipes/RecipeDetailView.swift:56` | 4 | Create Secrets.xcconfig from Secrets.example.xcconfig with a valid OpenRouter key, rebuild, and confirm the feature returns suggestions against… | P1 |
| `CD-SUBST-02` OpenRouter substitution provider | Substitution | 🔍 Needs Verification | `FridgeFit/Data/OpenRouterSubstitutionService.swift:27` | 13 | With a key configured (CD-SUBST-01), make a handful of real requests and record latency, how often the model honours the JSON-only instruction,… | P1 |
| `CD-SUBST-03` Deterministic validation of substitution suggestions against the pantry | Substitution | ✅ Completed | `FridgeFit/UseCases/SubstitutionSuggestionValidator.swift:21` | 12 | None | P0 |
| `CD-SUBST-04` Deduplicate, rank, cap and cache substitution results | Substitution | ✅ Completed | `FridgeFit/UseCases/GetIngredientSubstitutionsUseCase.swift:71` | 10 | None | P1 |
| `CD-SUBST-05` Dietary restriction enforcement on substitutions | Substitution | 🟡 Partially Completed | `FridgeFit/UseCases/SubstitutionSuggestionValidator.swift:114` | 3 | Build the dietary preferences profile (CD-PROFILE-03): a model, Firestore persistence, a Profile screen, and a read path from the view model into… | P1 |
| `CD-SUBST-06` Apply a substitution to the recipe | Substitution | ⬜ Not Started | `FridgeFit/Views/Support/SubstitutionPresentation.swift:70` | 0 | Add an accepted-substitutions map keyed by recipe and ingredient, and extend EvaluateRecipeFeasibilityUseCase to consult it. Care is needed to… | P2 |
| `CD-PROFILE-01` Show the signed-in account | Profile | ✅ Completed | `FridgeFit/Views/ProfileView.swift:15` | 0 | None | P1 |
| `CD-PROFILE-02` Sign out from Profile | Profile | 🔍 Needs Verification | `FridgeFit/Views/ProfileView.swift:23` | 0 | Covered by verifying CD-AUTH-05. | P0 |
| `CD-PROFILE-03` Dietary preferences and restrictions profile | Profile | ⬜ Not Started | `FridgeFit/Views/ProfileView.swift:12` | 0 | Model the preferences, persist them per user, add the Profile UI, and pass them from SubstitutionViewModel into the use case. The substitution… | P1 |
| `CD-PROFILE-04` Editable display name and avatar | Profile | ⬜ Not Started | `FridgeFit/Views/ProfileView.swift:17` | 0 | Add an edit screen writing through Auth's profile change request, or store the fields in Firestore alongside the dietary profile. | P2 |
| `CD-PROFILE-05` Account management: change password, delete account | Profile | ⬜ Not Started | `FridgeFit/Views/ProfileView.swift:23` | 0 | Add both flows. Account deletion needs a decision about the pantry data — Firestore does not delete subcollections with a parent document, so this… | P1 |
| `CD-PROFILE-06` App settings and preferences | Profile | ⬜ Not Started | `FridgeFit/Views/ProfileView.swift:12` | 0 | Decide which settings matter. A visible Apple Intelligence availability indicator would be genuinely useful here: AppleIntelligenceAvailability… | P2 |
| `CD-INFRA-01` Automated unit test suite | Infrastructure | ✅ Completed | `FridgeFitTests/` | 1 | None | P0 |
| `CD-INFRA-02` Layered architecture with testable boundaries | Infrastructure | ✅ Completed | `FridgeFit/UseCases/` | 1 | None | P0 |
| `CD-INFRA-03` Secrets excluded from version control | Infrastructure | ✅ Completed | `.gitignore` | 1 | None | P0 |
| `CD-INFRA-04` Firestore rules and indexes under version control and deployed | Infrastructure | 🔍 Needs Verification | `firebase.json` | 0 | Deploy and record it; add rules unit tests. | P0 |
| `CD-INFRA-05` UI, integration and end-to-end tests | Infrastructure | ⬜ Not Started | `FridgeFit.xcodeproj/project.pbxproj` | 0 | Add a UI test target with two or three high-value journeys, and emulator tests for the four Firestore operations. These would close CD-PANTRY-06,… | P1 |
| `CD-INFRA-06` Continuous integration | Infrastructure | ⬜ Not Started | — | 0 | Add a GitHub Actions workflow running xcodebuild test on an iOS 26.1 simulator. Two prerequisites first: commit a shared Xcode scheme… | P2 |
| `CD-INFRA-07` Shared Xcode scheme for reproducible builds | Infrastructure | ⬜ Not Started | `FridgeFit.xcodeproj/xcuserdata/` | 0 | Mark the scheme Shared in Xcode and commit it. Decide whether the uncommitted DEVELOPMENT_TEAM change belongs in version control; a… | P2 |
| `CD-INFRA-08` Accessibility support | Infrastructure | 🟡 Partially Completed | `FridgeFit/Views/Pantry/PantryView.swift:69` | 0 | Run Xcode's Accessibility Inspector audit on each screen, test with VoiceOver, and check the largest Dynamic Type sizes — particularly… | P2 |
| `CD-INFRA-09` Localization | Infrastructure | ⬜ Not Started | `FridgeFit/Domain/Errors/` | 0 | Add a String Catalog and migrate strings, starting with the error types since they are the most numerous and the most user-visible. | P2 |
| `CD-INFRA-10` Analytics and crash reporting | Infrastructure | ⬜ Not Started | `FridgeFit.xcodeproj/project.pbxproj` | 0 | Add Crashlytics if the app is to be distributed. Analytics is a product and privacy decision, not a technical one. | P2 |

---

## G. Architecture as discovered

SwiftUI + MVVM over an explicit Domain / Use Case / Repository separation. Views hold no business logic; view models hold no decisions; use cases own every rule; protocols isolate every external dependency so each one has a test double.

```
┌──────────────────────────────────────────────────────────────────────┐
│  PRESENTATION  ·  SwiftUI                                            │
│  FridgeFitApp → LoginView | ContentView (TabView: Pantry/Recipes/     │
│  Profile, one NavigationStack each) · 16 view files                   │
└───────────────────────────────┬──────────────────────────────────────┘
┌───────────────────────────────┴──────────────────────────────────────┐
│  VIEW MODELS  ·  MVVM, @MainActor ObservableObject                   │
│  Auth · Pantry · Recipe · RecipeSuggestion · ReceiptScanner ·        │
│  Substitution        — map results to state, own no rules            │
└───────────────────────────────┬──────────────────────────────────────┘
┌───────────────────────────────┴──────────────────────────────────────┐
│  USE CASES  ·  12 value types — every rule lives here                │
│  AddPantryItem · UpdatePantryItem · RemovePantryItem ·               │
│  EvaluateRecipeFeasibility · ScanReceipt · ReceiptItemNormalizer ·   │
│  IngredientCanonicalizer · AddDetectedIngredients ·                  │
│  SuggestRecipesFromPantry · GetIngredientSubstitutions ·             │
│  SubstitutionSuggestionValidator · SubstitutionCache                 │
└───────────────────────────────┬──────────────────────────────────────┘
┌───────────────────────────────┴──────────────────────────────────────┐
│  DOMAIN  ·  21 models · 6 protocols · 7 LocalizedError types          │
│  ╔═══════════════ TRUST BOUNDARY ═══════════════════════════════╗    │
│  ║ Raw* types carry NO pantry claims. A deterministic validator ║    │
│  ║ decides availability from the real pantry — never the model. ║    │
│  ╚═══════════════════════════════════════════════════════════════╝    │
│  PantryRepository · RecipeRepository · RecipeSuggestionService ·     │
│  ReceiptTextRecognizer · ReceiptIngredientInterpreter ·              │
│  SubstitutionService          ← the six seams                        │
└───────────────────────────────┬──────────────────────────────────────┘
┌───────────────────────────────┴──────────────────────────────────────┐
│  DATA  ·  one adapter + one double per protocol                      │
│  Firestore │ Vision OCR │ FoundationModels ×2 │ OpenRouter           │
└───┬─────────────┬──────────────────┬────────────────────┬───────────┘
    │             │                  │                    │
 Firebase    Apple Vision    Apple Foundation        OpenRouter
 Auth +      (on-device      Models (on-device,      (remote LLM —
 Firestore    OCR)            text-only)              only off-device
 (remote)                                             AI call)
```

### Layers

| Layer | What is there | Evidence |
|---|---|---|
| **Presentation (SwiftUI)** | 16 view files across Pantry, Recipes, Scanner, Profile, Support. Root is FridgeFitApp -> LoginView | ContentView (3-tab TabView, one NavigationStack per tab). | `FridgeFit/FridgeFitApp.swift:23`, `FridgeFit/ContentView.swift:58`, `FridgeFit/Views/` |
| **View Models (MVVM, @MainActor ObservableObject)** | 5 view models: Auth, Pantry, Recipe, RecipeSuggestion, ReceiptScanner, Substitution. Each maps use-case results to renderable state and nothing more. | `FridgeFit/ViewModels/`, `FridgeFit/AuthViewModel.swift:13` |
| **Use Cases (Domain logic)** | 12 use-case / policy types. All validation, feasibility, canonicalisation, normalisation, dedupe and ranking lives here. | `FridgeFit/UseCases/` |
| **Domain (Models, Protocols, Errors)** | 21 models, 6 protocols, 7 LocalizedError types. Protocols are the seam: PantryRepository, RecipeRepository, RecipeSuggestionService, ReceiptTextRecognizer, ReceiptIngredientInterpreter, SubstitutionService. | `FridgeFit/Domain/` |
| **Data (Adapters)** | Firestore, Vision, FoundationModels and OpenRouter adapters, each behind a domain protocol, each paired with an in-memory or mock double used by previews and tests. | `FridgeFit/Data/` |

### External dependencies

| Dependency | Usage | Integration | Evidence |
|---|---|---|---|
| **Firebase Authentication** | Email/password and Google credential sign-in, auth-state listener, sign out.<br>*firebase-ios-sdk >= 11.0.0 (FirebaseAuth, FirebaseCore, FirebaseFirestore)* | `production` | `FridgeFit/AuthViewModel.swift:40`, `FridgeFit/AuthViewModel.swift:52`, `FridgeFit/AuthViewModel.swift:83` |
| **Cloud Firestore** | Per-user pantry at users/{uid}/pantry/{itemId}; ordered read, create, existence-checked update and delete; server timestamps. | `production` | `FridgeFit/Data/FirestorePantryRepository.swift:36`, `firestore.rules:8` |
| **Google Sign-In (GoogleSignIn-iOS >= 7.0.0)** | Interactive Google sign-in, exchanged for a Firebase GoogleAuthProvider credential. URL scheme registered in Info.plist. | `production` | `FridgeFit/AuthViewModel.swift:74`, `FridgeFit/FridgeFitApp.swift:33` |
| **Apple Vision (RecognizeTextRequest)** | On-device receipt OCR at .accurate, language correction deliberately off, lowered minimumTextHeightFraction, observations stitched back into receipt rows. | `production` | `FridgeFit/Data/VisionReceiptTextRecognizer.swift:70`, `FridgeFit/Data/VisionReceiptTextRecognizer.swift:111` |
| **Apple Foundation Models (SystemLanguageModel)** | Two on-device features via guided generation: receipt line interpretation (batches of 12, temperature 0.1) and pantry recipe ideas (temperature 0.4). Text in, text out; the receipt photo never reaches the model. | `production` | `FridgeFit/Data/AppleReceiptIngredientInterpreter.swift:105`, `FridgeFit/Data/AppleRecipeSuggestionService.swift:113`, `FridgeFit/Data/GeneratedReceiptInterpretation.swift:28` |
| **OpenRouter (chat completions)** | Remote LLM for ingredient substitutions. The only off-device network call besides Firebase. | `production-code-present-but-unconfigured-in-this-checkout` | `FridgeFit/Data/OpenRouterSubstitutionService.swift:16`, `FridgeFit/Data/OpenRouterConfiguration.swift:24`, `FridgeFit/ContentView.swift:47` |

### The trust boundary

No generative model is permitted to assert pantry state. Every model output enters the app as an untrusted Raw* value and must pass a deterministic validator before any view sees it.

This is applied consistently across all three AI features:

| Feature | Untrusted input type | Deterministic validator | Adversarial test |
|---|---|---|---|
| Receipt scanning | `RawInterpretedReceiptItem` | `ReceiptItemNormalizer` — discards any item whose echoed line was never sent | `test_normalize_dropsItemsThatEchoALineNeverSent` |
| Pantry recipe ideas | `RawRecipeSuggestion` | `SuggestRecipesFromPantryUseCase` — recomputes the available/missing split | `test_suggestRecipes_marksIngredientMissing_whenPantryDisagrees` |
| Substitutions | `RawSubstitutionSuggestion` | `SubstitutionSuggestionValidator` — sole authority on pantry presence, sufficiency, units | `test_validate_unknownIngredient_isNeverClaimedAsAvailable` |

Evidence: `FridgeFit/Domain/Models/RawInterpretedReceiptItem.swift:30`, `FridgeFit/UseCases/ReceiptItemNormalizer.swift:61`, `FridgeFit/UseCases/SubstitutionSuggestionValidator.swift:21`, `FridgeFit/UseCases/SuggestRecipesFromPantryUseCase.swift:65`

### Build configuration

| Setting | Value | Note |
|---|---|---|
| `IPHONEOS_DEPLOYMENT_TARGET` | `26.1` | iOS 26.1 only — a deliberate consequence of using `FoundationModels`. |
| `SWIFT_VERSION` | `5.0` | With `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which is why the concurrency diagnostics are warnings and not errors. |
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | `MainActor` | Every class in the target gets an isolated deinit — see `ReceiptScannerViewModel`'s deinit comment. |
| `SWIFT_APPROACHABLE_CONCURRENCY` | `YES` | |
| `TARGETED_DEVICE_FAMILY` | `1,2` | iPhone and iPad. |
| Targets | `FridgeFit`, `FridgeFitTests` | No UI test target. |
| Shared scheme | **None committed** | `xcuserdata/` is gitignored; the audit's run used an autocreated scheme. |

---

## H. Testing and quality

### The test run was real

```
$ xcodebuild test -project FridgeFit.xcodeproj -scheme FridgeFit -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.1' CODE_SIGNING_ALLOWED=NO

** TEST SUCCEEDED **
   240 passed · 0 failed · 0 skipped
   2.42 s of test execution across 240 cases
```

**Toolchain.** Xcode 26.1 (17B55), iOS Simulator 26.1 · **Destination.** iPhone 17 Pro (iOS 26.1) simulator

The full suite was executed, not merely counted: xcodebuild reported ** TEST SUCCEEDED ** with 240 'Test case ... passed' lines, zero failures and zero skips. The 240 figure matches the static count of `func test_` methods across 23 XCTest classes. The suite uses XCTest exclusively; no swift-testing (@Test) macros are present. The whole suite runs in under three seconds because every external dependency is behind a double.

Slowest cases (all deliberate — they exercise cancellation and task supersession with real delays):

- `ReceiptScannerViewModelTests.test_cancelScan_leavesNoResults (0.503s)`
- `ReceiptScannerViewModelTests.test_selectingANewImage_discardsTheInFlightScan (0.470s)`
- `ReceiptScannerViewModelTests.test_scan_isIgnoredWhileAScanIsAlreadyRunning (0.220s)`

### ⚠️ What a green suite does not prove

All 240 tests run against test doubles. The run involved no live Firebase project, no live OpenRouter request, no camera and no Apple Intelligence system language model (the Simulator provides none). A green suite here says the domain logic is correct; it says nothing about the four production integrations.

| Integration | Tested against | Real integration exercised? |
|---|---|---|
| Cloud Firestore | Pure `encode`/`decode` functions, 8 tests | ❌ No CRUD test, no emulator |
| Firebase Auth | Nothing | ❌ Zero coverage |
| Apple Vision OCR | `MockReceiptTextRecognizer` | ❌ `VisionReceiptTextRecognizer` has no tests |
| Apple Foundation Models | `MockReceiptIngredientInterpreter`, `MockRecipeSuggestionService` | ❌ No system language model on a simulator |
| OpenRouter | `StubURLProtocol`, 7 tests covering every error branch | ❌ No live request |

### Coverage distribution

Concentrated where the risk is, not spread evenly:

| Test class | Cases | What it protects |
|---|---:|---|
| `ReceiptItemNormalizerTests` | 25 | Anti-hallucination, echo matching, dedupe, quantity resolution |
| `ReceiptLineParserTests` | 19 | Metadata filtering, price splitting, substring collisions (CASHEWS/CASH) |
| `IngredientCanonicalizerTests` | 18 | Synonym resolution, compound protection, keeping unrelated foods apart |
| `ReceiptScannerViewModelTests` | 18 | Scan state machine, cancellation, draft editing, 'stores nothing on its own' |
| `EvaluateRecipeFeasibilityUseCaseTests` | 16 | Every feasibility status boundary, both conversion directions, fail-closed |
| `SuggestRecipesFromPantryUseCaseTests` | 15 | Pantry-authoritative availability split |
| `ReceiptQuantityParserTests` | 14 | Weight/volume/count extraction, 'nil is a real answer' |
| `SubstitutionSuggestionValidatorTests` | 14 | Pantry presence, sufficiency, unit compatibility, dietary rejection |
| `ReceiptInterpretationPromptBuilderTests` | 11 | The prompt instructions that carry the safety properties |
| `GetIngredientSubstitutionsUseCaseTests` | 10 | Dedupe, ranking, cap, cache invalidation |
| `ScanReceiptUseCaseTests` | 12 | Pipeline sequencing and the three distinct 'nothing found' outcomes |
| `AddDetectedIngredientsUseCaseTests` | 8 | Per-item scan→pantry outcomes |
| `FirestorePantryRepositoryMappingTests` | 8 | Firestore field mapping, including the encode/decode round trip |
| `PantryViewModelTests` | 8 | Pantry presentation state and guided duplicate recovery |
| `OpenRouterSubstitutionServiceTests` | 7 | Request shape and every HTTP/network error branch |
| `MeasurementUnitConversionTests` | 7 | The four safe conversions and every unsafe pair |
| `AddPantryItemUseCaseTests` | 6 | Name/quantity validation and duplicate rejection |
| `SubstitutionResponseParserTests` | 6 | Tolerating code fences and prose without repairing bad JSON |
| `RecipeViewModelTests` | 5 | Recipe loading and feasibility caching |
| `RecipeRepositoryTests` | 4 | Bundled dataset integrity |
| `SubstitutionViewModelTests` | 4 | Per-ingredient independent state |
| `UpdatePantryItemUseCaseTests` | 3 | Quantity update rules |
| `RemovePantryItemUseCaseTests` | 2 | Removal and the already-gone case |
| **Total** | **240** | |

### Untested production code

| Type | Why it matters |
|---|---|
| `AuthViewModel` | Gates every other feature. Untestable as written — calls the `Auth.auth()` singleton directly. |
| `VisionReceiptTextRecognizer` | First link in the scan chain. Row-stitching geometry, the 0.6 grouping tolerance and the 0.3 confidence floor are all unexercised magic numbers. |
| `AppleReceiptIngredientInterpreter` | The `@Generable` schema, availability mapping and `GenerationError` mapping. Cannot run on a simulator. |
| `AppleRecipeSuggestionService` | Same. |
| `FirestorePantryRepository` CRUD | Only the pure mapping helpers are covered. |
| `CameraPicker` / `CameraAccess` | UIKit and AVFoundation integration with no double. |
| `ProfileView`, `LoginView`, `RegisterView` | No UI tests exist at all. |

### Build warnings

**17 warning lines (11 unique messages)** in FridgeFit sources.

Swift concurrency: 'call to main actor-isolated X in a synchronous nonisolated context'. A consequence of the target building with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor while SWIFT_VERSION is still 5.0, so these are warnings today and would be errors under Swift 6 language mode.

Locations:

- `FridgeFit/Data/VisionReceiptTextRecognizer.swift:116`
- `FridgeFit/Domain/Models/ReceiptItemDraft.swift:49`
- `FridgeFit/UseCases/IngredientCanonicalizer.swift:203`
- `FridgeFit/ViewModels/PantryViewModel.swift:32`
- `FridgeFit/ViewModels/RecipeViewModel.swift:27`
- `FridgeFit/ViewModels/RecipeViewModel.swift:28`
- `FridgeFitTests/UseCases/ScanReceiptUseCaseTests.swift:13`
- `FridgeFitTests/UseCases/ScanReceiptUseCaseTests.swift:14`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift:15`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift:16`
- `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift:33`

### Quality findings

Specific defects and inconsistencies found by inspection. Severity is this auditor's judgement of user impact.

#### 🔴 High (2)

- **Substitutions are non-functional in a fresh checkout** — Secrets.xcconfig is absent, so OPENROUTER_API_KEY resolves empty, loadFromInfoPlist returns nil, and ContentView wires UnconfiguredSubstitutionService. Every Find Substitute tap fails with .notConfigured.  
  Evidence: `FridgeFit/ContentView.swift:47`, `Config.xcconfig`, `FridgeFit/Data/OpenRouterConfiguration.swift:24` · Requirement: `CD-SUBST-01`
- **Dietary restriction enforcement is built, tested and permanently inert** — dietaryRestrictions defaults to [] and SubstitutionViewModel.findSubstitutes never passes it. A grep across the codebase finds it supplied non-empty only in test code.  
  Evidence: `FridgeFit/UseCases/GetIngredientSubstitutionsUseCase.swift:35`, `FridgeFit/ViewModels/SubstitutionViewModel.swift:35` · Requirement: `CD-SUBST-05`

#### 🟠 Medium (4)

- **Camera usage description describes a removed feature** — NSCameraUsageDescription still says the camera is used to photograph the inside of the fridge. The fridge-photo scanner was replaced by receipt scanning in commit b79ee34. CameraAccess.denied carries the same stale wording.  
  Evidence: `FridgeFit/Info.plist`, `FridgeFit/Views/Scanner/CameraPicker.swift:108` · Requirement: `CD-SCAN-11`
- **Canonical ingredient identity is computed then discarded at the pantry boundary** — IngredientCanonicalizer resolves 'CAPS RED', 'Red Capsicum' and 'Bell Pepper' to one identity, and ReceiptIngredientCandidate carries it, but PantryItem does not. Pantry duplicate detection and recipe matching both fall back to exact-after-normalisation display names.  
  Evidence: `FridgeFit/Domain/Models/PantryItem.swift:9`, `FridgeFit/UseCases/AddPantryItemUseCase.swift:42`, `FridgeFit/UseCases/EvaluateRecipeFeasibilityUseCase.swift:36` · Requirement: `CD-PANTRY-03`
- **Eight selectable units, four convertible** — cups, tbsp, tsp and pcs are offered in every unit picker but can never be compared to anything else, so such pantry items are permanently 'Check amount' against a recipe in grams.  
  Evidence: `FridgeFit/Domain/Models/MeasurementUnit+Conversion.swift:22`, `FridgeFit/Views/Pantry/AddPantryItemView.swift:41` · Requirement: `CD-RECIPE-04`
- **17 Swift concurrency warnings (11 unique) in the test build** — All of the form 'call to main actor-isolated X in a synchronous nonisolated context'. Warnings today because SWIFT_VERSION is 5.0 while SWIFT_DEFAULT_ACTOR_ISOLATION is MainActor; errors under Swift 6 language mode. ReceiptScannerViewModel's deinit comment documents a related runtime abort already hit in this target.  
  Evidence: `FridgeFit/Data/VisionReceiptTextRecognizer.swift:116`, `FridgeFit/ViewModels/ReceiptScannerViewModel.swift:97` · Requirement: `CD-INFRA-01`

#### 🔵 Low (6)

- **Account switching within one session is untested** — ContentView builds every view model and the SubstitutionCache once in init; they are not rebuilt on sign-out and sign-in. The Firestore repository re-reads the UID per call, so persistence follows the user, but in-memory lists and the cache may not.  
  Evidence: `FridgeFit/ContentView.swift:19`, `FridgeFit/UseCases/SubstitutionCache.swift:25` · Requirement: `CD-AUTH-04`
- **Multi-row pantry deletion spawns concurrent tasks** — removeItems(at:) starts one unstructured Task per offset, each reloading the list on completion. The end state is correct because operations are id-scoped, but the intermediate list can flicker and the reloads are redundant.  
  Evidence: `FridgeFit/Views/Pantry/PantryView.swift:157` · Requirement: `CD-PANTRY-05`
- **Updating an untouched quantity can write back a rounded value** — UpdatePantryItemView seeds its field by splitting item.formattedQuantity, which MeasurementUnit.formatted has already rounded to one decimal place.  
  Evidence: `FridgeFit/Views/Pantry/UpdatePantryItemView.swift:22`, `FridgeFit/Domain/Models/MeasurementUnit.swift:24` · Requirement: `CD-PANTRY-04`
- **Accepted scan drafts are matched by name rather than id** — addSelectedToPantry removes drafts by comparing names against summary.addedNames. Two drafts with the same display name would both be removed when one was added. The id is available and would be exact.  
  Evidence: `FridgeFit/ViewModels/ReceiptScannerViewModel.swift:313` · Requirement: `CD-SCAN-09`
- **Mock and in-memory doubles ship in the production target** — MockReceiptScanning, MockSubstitutionService, MockRecipeSuggestionService, InMemoryPantryRepository and InMemoryRecipeRepository live in FridgeFit/Data rather than the test target. This keeps them available to SwiftUI previews but includes them in the app binary.  
  Evidence: `FridgeFit/Data/MockReceiptScanning.swift:16`, `FridgeFit/Data/MockSubstitutionService.swift:15` · Requirement: `CD-INFRA-01`
- **Machine-specific signing identity in an uncommitted pbxproj change** — The working tree adds DEVELOPMENT_TEAM to both build configurations. A developer-specific team id in a shared project file breaks other developers' and CI builds.  
  Evidence: `FridgeFit.xcodeproj/project.pbxproj` · Requirement: `CD-INFRA-07`

### What the codebase does notably well

Recorded because an audit that lists only gaps misrepresents the work.

#### ✅ Generative model output is never trusted with pantry state

All three AI features follow the same pattern: model output enters as an untrusted Raw* type carrying no pantry claims, and a deterministic validator decides availability from the real pantry. ReceiptItemNormalizer discards any item whose echoed line was never sent — the hard stop on invented groceries. SubstitutionSuggestionValidator is the only type permitted to decide pantry existence, sufficiency and unit compatibility. SuggestRecipesFromPantryUseCase recomputes the available/missing split rather than asking for it. Each has a test asserting the adversarial case by name.

Evidence: `FridgeFit/UseCases/ReceiptItemNormalizer.swift:61`, `FridgeFit/UseCases/SubstitutionSuggestionValidator.swift:21`, `FridgeFit/UseCases/SuggestRecipesFromPantryUseCase.swift:65`

#### ✅ 'Not known' is modelled as a real answer rather than defaulted

A receipt line with no quantity yields nil, not '1 pcs', and the UI says 'Quantity not detected'. An unconvertible unit pair yields quantityUnverified rather than a guessed comparison. An unrecognised Apple Intelligence unavailability reason fails closed. The removed confidence badge is documented as having measured nothing and given the user nothing to act on.

Evidence: `FridgeFit/Domain/Models/ReceiptQuantity.swift:8`, `FridgeFit/Domain/Models/MeasurementUnit+Conversion.swift:9`, `FridgeFit/Views/Support/ScannerPresentation.swift:8`

#### ✅ Tests assert documented invariants, not just code paths

240 tests, all passing, weighted toward the riskiest logic. Several assert properties rather than behaviour — that the interpreter only ever receives cleaned text, that a scan stores nothing on its own, that availability is checked before any OCR work, and that the prompt still forbids inventing products. Asserting prompt content is unusual and guards the instructions carrying the safety properties against accidental edits.

Evidence: `FridgeFitTests/UseCases/ScanReceiptUseCaseTests.swift:73`, `FridgeFitTests/ViewModels/ReceiptScannerViewModelTests.swift`, `FridgeFitTests/Data/ReceiptInterpretationPromptBuilderTests.swift`

#### ✅ Privacy decisions are deliberate and documented

ReceiptScanDiagnostics uses print behind #if DEBUG rather than Logger, with the reasoning stated: a receipt records what someone bought, where and when, and the unified log persists on device and is collectable in a sysdiagnose. SubstitutionRequest carries no ids and nothing about the Firebase user. The receipt photo never reaches the language model, and the scanner screen tells the user so.

Evidence: `FridgeFit/Data/ReceiptScanDiagnostics.swift:11`, `FridgeFit/Domain/Models/SubstitutionRequest.swift:17`, `FridgeFit/Views/Scanner/ReceiptScannerView.swift:94`

#### ✅ Non-obvious decisions carry their reasoning in the source

usesLanguageCorrection = false is explained by what it would break (correction rewrites CHKN toward a real word and the interpreter then faithfully reads the wrong product). The parser's weak-filter asymmetry is argued from which error the user can see. The nonisolated deinit on ReceiptScannerViewModel documents a specific runtime abort. This is why the audit could assess intent, not just behaviour.

Evidence: `FridgeFit/Data/VisionReceiptTextRecognizer.swift:18`, `FridgeFit/Data/ReceiptLineParser.swift:10`, `FridgeFit/ViewModels/ReceiptScannerViewModel.swift:78`

### Remaining quality risks, ranked

1. **The scan-to-Firestore path has never been observed working** (`CD-SCAN-10`). The headline feature, blocked on three simultaneous prerequisites.
2. **Firestore CRUD is unverified** (`CD-PANTRY-06`). Every feature's persistence runs through it; `fetchAll` silently drops undecodable documents.
3. **The security rules may not be deployed** (`CD-PANTRY-07`). If the live project is on test-mode rules, client-side UID scoping is not a security boundary.
4. **Authentication has zero test coverage** (`CD-AUTH-09`), including the untested account-switch scenario.
5. **Two features are hardware-gated** (`CD-AI-01`, `CD-SCAN-05`) and permanently unavailable on ineligible devices.
6. **Substitutions fail in a fresh clone** (`CD-SUBST-01`) and dietary restrictions protect nobody (`CD-SUBST-05`).

---

## I. Remaining development roadmap

Grouped by priority, ordered for execution. Each task is marked as a **verified missing requirement** (absence confirmed in the code) or a **recommendation** (the auditor's suggestion — its presence in the specification could not be confirmed).

### P0 — Critical — blocks essential functionality or a truthful completeness claim

#### 1. Obtain the Notion Feature List and re-run the requirement mapping  ·  *✔︎ verified missing*

| | |
|---|---|
| **Requirements** | `ALL` |
| **Work required** | Export the Notion Feature List to Markdown or CSV and commit it to docs/, or configure a Notion integration token. Then re-map every Notion requirement onto this audit's CD-* records. |
| **Components** | `docs/` |
| **Acceptance criteria** | Every Notion requirement has a status, evidence and remaining-work entry, and the overall completion percentage is computable and stated with its method. |
| **Dependencies** | Access to the Notion workspace |
| **Effort** | 0.5 day |
| **Effort assumption** | Assumes the export is straightforward and the list is comparable in size to this 65-item baseline. Re-mapping, not re-auditing — the code evidence is already gathered. |

**Why this matters.** Until this is done, no statement about overall project completion can be made honestly, and any Notion requirement with zero implementation is invisible to this report by construction.

#### 2. Deploy and test the Firestore security rules  ·  *✔︎ verified missing*

| | |
|---|---|
| **Requirements** | `CD-PANTRY-07`, `CD-INFRA-04` |
| **Work required** | Run firebase deploy --only firestore:rules against the live project. Add @firebase/rules-unit-testing cases asserting that user A cannot read or write user B's pantry and that unauthenticated access is denied. |
| **Components** | `firestore.rules`, `firebase.json` |
| **Acceptance criteria** | Rules are confirmed live in the Firebase console, and automated rules tests pass for the cross-user denial and unauthenticated-denial cases. |
| **Dependencies** | Firebase project access; Firebase CLI |
| **Effort** | 0.5 day |
| **Effort assumption** | Rules are already written and correct; this is deployment plus a small test harness. |

**Why this matters.** If the live project is still on test-mode rules, every user's pantry is readable by any authenticated client. The client-side uid scoping is a correctness measure, not a security boundary.

#### 3. Verify Firestore pantry CRUD against the Firebase Emulator Suite  ·  *✔︎ verified missing*

| | |
|---|---|
| **Requirements** | `CD-PANTRY-06`, `CD-INFRA-05` |
| **Work required** | Configure the emulator in firebase.json and add integration tests covering fetchAll, add, update and remove, plus the notAuthenticated path. Inject a fixed UID through the existing userIDProvider seam. |
| **Components** | `FridgeFit/Data/FirestorePantryRepository.swift`, `FridgeFitTests/`, `firebase.json` |
| **Acceptance criteria** | Automated tests create, read, update and delete a pantry item against the emulator and assert the stored field shape, including both server timestamps. |
| **Dependencies** | Firebase CLI with emulator support |
| **Effort** | 1–2 days |
| **Effort assumption** | Assumes first-time emulator setup for this project. The injectable userIDProvider already exists, so no production change is needed. |

**Why this matters.** Every feature's persistence runs through this repository and only its pure mapping functions are tested. fetchAll silently compactMaps away any undecodable document, which would present to a user as an item quietly vanishing.

#### 4. Run one documented end-to-end receipt scan on capable hardware  ·  *✔︎ verified missing*

| | |
|---|---|
| **Requirements** | `CD-SCAN-10`, `CD-SCAN-02`, `CD-SCAN-05`, `CD-AI-01` |
| **Work required** | On an Apple Intelligence-capable device running iOS 26.x with the feature enabled and the Firebase config in place, photograph several real grocery receipts from different retailers. Record OCR line recovery, how often the model echoes originalText exactly enough to be matched, classification accuracy on ambiguous items such as milk and stock, and confirm the resulting documents in the Firebase console. Repeat for Pantry Ideas. |
| **Components** | `FridgeFit/Data/VisionReceiptTextRecognizer.swift`, `FridgeFit/Data/AppleReceiptIngredientInterpreter.swift`, `FridgeFit/Data/AppleRecipeSuggestionService.swift` |
| **Acceptance criteria** | A written record exists of at least three real receipts scanned end to end, with per-stage observations and the Firestore documents verified. The rowGroupingTolerance and minimumLineConfidence values are either validated or adjusted against that evidence. |
| **Dependencies** | iPhone 15 Pro or later (or M-series iPad) with Apple Intelligence enabled and model assets downloaded; Live Firebase credentials |
| **Effort** | 1 day |
| **Effort assumption** | Assumes a capable device is available. Mostly measurement and note-taking rather than coding, unless the evidence shows the tuning constants need changing. |

**Why this matters.** This is the project's headline feature and its single largest unverified claim. The 240 green unit tests prove each stage is correct against doubles; none of them touch real OCR, a real model, or a real database.

#### 5. Fix the stale camera usage description  ·  *✔︎ verified missing*

| | |
|---|---|
| **Requirements** | `CD-SCAN-11` |
| **Work required** | Rewrite NSCameraUsageDescription to describe photographing a grocery receipt, and update CameraAccess.denied's explanation and CameraPicker's doc comment to match. |
| **Components** | `FridgeFit/Info.plist`, `FridgeFit/Views/Scanner/CameraPicker.swift` |
| **Acceptance criteria** | Both user-visible strings describe receipt photography; no reference to photographing a fridge remains. |
| **Dependencies** | None |
| **Effort** | 15 minutes |
| **Effort assumption** | Two string edits. |

**Why this matters.** A purpose string that does not match actual camera use is a recognised App Store review rejection reason, and it misleads the user at the moment they decide whether to grant access. Cheapest high-value fix in this report.

### P1 — Important for MVP completion

#### 6. Configure OpenRouter credentials and validate substitutions live  ·  *✔︎ verified missing*

| | |
|---|---|
| **Requirements** | `CD-SUBST-01`, `CD-SUBST-02` |
| **Work required** | Create Secrets.xcconfig from Secrets.example.xcconfig with a valid key. Make a handful of real requests and record latency, JSON-schema compliance and whether the model attempts to assert pantry availability despite the prompt forbidding it. Confirm the hardcoded default model identifier is still available. |
| **Components** | `Secrets.xcconfig (local, gitignored)`, `FridgeFit/Data/OpenRouterConfiguration.swift` |
| **Acceptance criteria** | Find Substitute returns validated suggestions on a real recipe, and the observed behaviour is recorded. The default model string is confirmed live or updated. |
| **Dependencies** | An OpenRouter API key |
| **Effort** | 0.5 day |
| **Effort assumption** | Configuration plus observation. No code change expected unless the default model has been withdrawn. |

**Why this matters.** A demonstration from a fresh clone currently shows this feature failing with 'Substitution suggestions aren't set up yet'. The failure is graceful and names the fix, but the feature is non-functional until a key exists.

#### 7. Build the dietary preferences profile  ·  *✔︎ verified missing*

| | |
|---|---|
| **Requirements** | `CD-PROFILE-03`, `CD-SUBST-05` |
| **Work required** | Add a dietary preferences model, persist it per user in Firestore with matching security rules, add the Profile editing UI, and pass the values from SubstitutionViewModel into GetIngredientSubstitutionsUseCase. |
| **Components** | `FridgeFit/Views/ProfileView.swift`, `FridgeFit/ViewModels/SubstitutionViewModel.swift`, `firestore.rules` |
| **Acceptance criteria** | A saved restriction survives relaunch, appears in the substitution prompt, and a conflicting suggestion is filtered out before reaching the UI. Any user-facing wording avoids implying allergen-grade protection. |
| **Dependencies** | P0 task 2 (rules) so the new collection is covered |
| **Effort** | 2–3 days |
| **Effort assumption** | Assumes a simple tag list rather than a structured allergen taxonomy. The enforcement mechanism already exists and is tested, so the work is the profile and the wiring. |

**Why this matters.** This single absence makes CD-SUBST-05 inert: the enforcement path is built and tested but the list is always empty, so a user with a nut allergy has no way to tell FridgeFit and the feature will suggest peanut butter. Note that the existing keyword check is explicitly not an allergen database.

#### 8. Make authentication testable and test it  ·  *✔︎ verified missing*

| | |
|---|---|
| **Requirements** | `CD-AUTH-09`, `CD-AUTH-01`, `CD-AUTH-02`, `CD-AUTH-04`, `CD-AUTH-05` |
| **Work required** | Introduce an auth-service protocol so AuthViewModel stops calling the Auth.auth() singleton directly, then test sign-in success, failure messaging, sign-up, sign-out and the loading flag. Explicitly test the account-switch scenario: sign out, sign in as a different user, confirm the Pantry tab shows the second user's data and the SubstitutionCache does not serve stale entries. |
| **Components** | `FridgeFit/AuthViewModel.swift`, `FridgeFit/ContentView.swift`, `FridgeFitTests/` |
| **Acceptance criteria** | AuthViewModel is covered by unit tests behind a double, and the account-switch scenario is verified. |
| **Dependencies** | None |
| **Effort** | 1–2 days |
| **Effort assumption** | Small production refactor plus tests. Touching production code, so out of scope for this audit but straightforward. |

**Why this matters.** Authentication gates every other feature and is the only feature area with zero test coverage. The account-switch case is a genuine untested risk: ContentView's @StateObject view models and the substitution cache are built once per app session and are not rebuilt on a user change.

#### 9. Add a password reset flow  ·  *✔︎ verified missing*

| | |
|---|---|
| **Requirements** | `CD-AUTH-07` |
| **Work required** | Add a 'Forgot password?' control to LoginView and an AuthViewModel.sendPasswordReset(email:) method wrapping Auth.auth().sendPasswordReset, with a confirmation state that does not disclose whether the address is registered. |
| **Components** | `FridgeFit/LoginView.swift`, `FridgeFit/AuthViewModel.swift` |
| **Acceptance criteria** | A reset email arrives for a registered address, and the UI response is identical for a registered and an unregistered address. |
| **Dependencies** | P1 task 8, so the new method lands behind the testable abstraction |
| **Effort** | 0.5 day |
| **Effort assumption** | One Firebase call plus UI. |

**Why this matters.** Account recovery is a baseline expectation for email/password sign-in. Today a forgotten password is unrecoverable from inside the app.

#### 10. Replace the bundled recipe dataset with a real catalogue  ·  *✔︎ verified missing*

| | |
|---|---|
| **Requirements** | `CD-RECIPE-05` |
| **Work required** | Choose a source (a recipe API, or Firestore as the recipe store), implement RecipeRepository against it with response models, error mapping and caching, and inject it in ContentView. |
| **Components** | `FridgeFit/Domain/Protocols/RecipeRepository.swift`, `FridgeFit/Data/`, `FridgeFit/ContentView.swift` |
| **Acceptance criteria** | The recipe list is served from the remote source with loading and failure states, and feasibility still evaluates correctly against it. |
| **Dependencies** | A chosen recipe data source |
| **Effort** | 3–5 days |
| **Effort assumption** | Dominated by the adapter and data modelling. The RecipeRepository protocol means no use case or view changes — injection in ContentView is one line. |

**Why this matters.** Ten hard-coded recipes bound how useful feasibility matching can be: most real pantries will not match any of them. This is the biggest limitation on the product's core value proposition, independent of code quality.

#### 11. Close the pantry loop: deduct ingredients after cooking  ·  *💡 recommendation*

| | |
|---|---|
| **Requirements** | `CD-RECIPE-09` |
| **Work required** | Add a ConsumeRecipeIngredientsUseCase with unit-aware subtraction, refusing to deduct where MeasurementUnit.convert returns nil (consistent with how the rest of the app fails closed), plus a 'Cooked this' action on RecipeDetailView. |
| **Components** | `FridgeFit/UseCases/`, `FridgeFit/Views/Recipes/RecipeDetailView.swift` |
| **Acceptance criteria** | Marking a recipe cooked decrements the right pantry quantities, never below zero, and leaves unconvertible units untouched with an explanation. |
| **Dependencies** | None |
| **Effort** | 2 days |
| **Effort assumption** | Follows the established use-case pattern and reuses existing conversion logic. |

**Why this matters.** Without this, pantry quantities drift from reality the moment the user cooks anything, which degrades every feasibility verdict and every AI suggestion. It is the natural completion of the pantry/recipe loop the whole app is built around. Flagged as a recommendation because its presence in the Notion specification could not be confirmed.

#### 12. Add UI journey tests and a shared scheme, then CI  ·  *✔︎ verified missing*

| | |
|---|---|
| **Requirements** | `CD-INFRA-05`, `CD-INFRA-07`, `CD-INFRA-06` |
| **Work required** | Commit a shared FridgeFit.xcscheme under xcshareddata/xcschemes/ and resolve whether the uncommitted DEVELOPMENT_TEAM change belongs in version control. Add a UI test target with two or three high-value journeys. Add a GitHub Actions workflow running xcodebuild test on an iOS 26.1 simulator, injecting GoogleService-Info.plist from a repository secret. |
| **Components** | `FridgeFit.xcodeproj/xcshareddata/`, `.github/workflows/`, `a new UI test target` |
| **Acceptance criteria** | A clean clone plus the injected secrets builds and runs the full suite from the command line, and the workflow runs on every push. |
| **Dependencies** | A decision on how CI receives the gitignored Firebase config |
| **Effort** | 2–3 days |
| **Effort assumption** | Scheme and workflow are quick; the UI test target and journeys are most of the time. Assumes the secrets-injection approach is settled first. |

**Why this matters.** With 240 tests and no automation, a regression is caught only when someone remembers to run the suite. The absence of integration tests is the structural reason so much of this audit reads 'needs verification'.

### P2 — Enhancements and future improvements

#### 13. Resolve the Swift 6 concurrency warnings  ·  *💡 recommendation*

| | |
|---|---|
| **Requirements** | `CD-INFRA-01` |
| **Work required** | Address the 11 'call to main actor-isolated X in a synchronous nonisolated context' warnings, then consider moving SWIFT_VERSION from 5.0 to 6.0. |
| **Components** | `FridgeFit/Data/VisionReceiptTextRecognizer.swift:116`, `FridgeFit/Domain/Models/ReceiptItemDraft.swift:49`, `FridgeFit/UseCases/IngredientCanonicalizer.swift:203`, `FridgeFit/ViewModels/`, `FridgeFitTests/` |
| **Acceptance criteria** | The build is warning-free, and the decision on Swift 6 language mode is recorded. |
| **Dependencies** | None |
| **Effort** | 1 day |
| **Effort assumption** | Mostly annotation changes; some may need a type's isolation reconsidered. |

**Why this matters.** These are warnings today only because SWIFT_VERSION is 5.0 while SWIFT_DEFAULT_ACTOR_ISOLATION is MainActor. Under Swift 6 language mode they become errors. ReceiptScannerViewModel's deinit comment documents a related runtime abort already encountered in this target, so this is not purely cosmetic.

#### 14. Unify ingredient identity across scan, pantry and recipes  ·  *💡 recommendation*

| | |
|---|---|
| **Requirements** | `CD-PANTRY-03`, `CD-RECIPE-03`, `CD-SCAN-07` |
| **Work required** | Carry canonicalName onto PantryItem and use it for duplicate detection and recipe ingredient matching, instead of discarding it at the pantry boundary. |
| **Components** | `FridgeFit/Domain/Models/PantryItem.swift`, `FridgeFit/UseCases/AddPantryItemUseCase.swift`, `FridgeFit/UseCases/EvaluateRecipeFeasibilityUseCase.swift`, `FridgeFit/Data/FirestorePantryRepository.swift` |
| **Acceptance criteria** | A hand-typed 'Bell Pepper' and a scanned 'Red Capsicum' are recognised as one ingredient, and a pantry 'Chicken' satisfies a recipe's 'Chicken Breast'. Existing Firestore documents without the field still decode. |
| **Dependencies** | P0 task 3, so the schema change is covered by emulator tests |
| **Effort** | 2–3 days |
| **Effort assumption** | Includes a Firestore schema addition that must be optional in the decoder, and a careful review of which merges become possible. |

**Why this matters.** IngredientCanonicalizer is 297 well-tested lines that resolve 'CAPS RED', 'Red Capsicum' and 'Bell Pepper' to one identity — and that work is used only for scan-time dedupe, then thrown away. The pantry and recipe matcher both fall back to exact-after-normalisation name comparison. Note the risk: a wrong merge is harder for a user to notice than a missed one, which is why the canonicaliser's own descriptor list is deliberately conservative.

#### 15. Decide the unit-conversion story  ·  *✔︎ verified missing*

| | |
|---|---|
| **Requirements** | `CD-RECIPE-04` |
| **Work required** | Either add volume ratios for cup/tbsp/tsp, or restrict the unit pickers to the units the app can reason about, or label the unconvertible units at the point of selection. |
| **Components** | `FridgeFit/Domain/Models/MeasurementUnit+Conversion.swift`, `FridgeFit/Views/Pantry/AddPantryItemView.swift`, `FridgeFit/Views/Scanner/ReceiptItemReviewView.swift` |
| **Acceptance criteria** | A user cannot unknowingly create a pantry item in a unit that feasibility can never evaluate. |
| **Dependencies** | None |
| **Effort** | 0.5–1 day |
| **Effort assumption** | Depends on the option chosen; restricting the pickers is the cheapest. |

**Why this matters.** MeasurementUnit offers eight units but only four convert. The UI invites the user to pick cups, tbsp, tsp or pcs, and any pantry item in those units is permanently 'Check amount' against a recipe in grams. Failing closed is the right behaviour; the gap is the unit set offered.

#### 16. Verify accessibility  ·  *✔︎ verified missing*

| | |
|---|---|
| **Requirements** | `CD-INFRA-08` |
| **Work required** | Run Xcode's Accessibility Inspector audit on every screen, test with VoiceOver, and check the largest Dynamic Type sizes — particularly ReceiptItemReviewView, whose row packs a fixed 110-point quantity field and two pickers into one horizontal stack. |
| **Components** | `FridgeFit/Views/` |
| **Acceptance criteria** | The audit is clean, each screen is navigable with VoiceOver, and no layout clips at the largest accessibility text sizes. |
| **Dependencies** | None |
| **Effort** | 1 day |
| **Effort assumption** | Verification plus likely small layout fixes in the receipt review row. |

**Why this matters.** The accessibility work already present is deliberate and better than typical for a project this size — composed labels, hints, hidden decorative icons, colour always paired with a symbol and text. It is unverified rather than absent, so this is confirmation work.

#### 17. Write setup documentation  ·  *💡 recommendation*

| | |
|---|---|
| **Requirements** | `CD-INFRA-03` |
| **Work required** | Add a README covering the Firebase configuration step, the Secrets.xcconfig step, the iOS 26.1 and Apple Intelligence device requirements, and how to run the tests. |
| **Components** | `README.md` |
| **Acceptance criteria** | Someone with a fresh clone can build, run and test the project from the README alone. |
| **Dependencies** | None |
| **Effort** | 0.5 day |
| **Effort assumption** | Documentation only. |

**Why this matters.** The repository has no README. Two required files are gitignored by design and two features are hardware-gated, so a fresh clone fails in several non-obvious ways with no written guidance.

#### 18. Remaining deferred scope  ·  *💡 recommendation*

| | |
|---|---|
| **Requirements** | `CD-PANTRY-08`, `CD-PANTRY-09`, `CD-PANTRY-10`, `CD-RECIPE-06`, `CD-RECIPE-07`, `CD-RECIPE-08`, `CD-AI-04`, `CD-SUBST-06`, `CD-PROFILE-04`, `CD-PROFILE-05`, `CD-PROFILE-06`, `CD-AUTH-06`, `CD-AUTH-08`, `CD-INFRA-09`, `CD-INFRA-10` |
| **Work required** | Expiry tracking, pantry and recipe search/filter, an explicit offline policy, recipe imagery, favourites, acting on an AI suggestion, applying a substitution, profile editing, account management, app settings, email-format validation, email verification, localisation, and crash reporting. |
| **Components** | `Various` |
| **Acceptance criteria** | Per requirement; see the traceability matrix. |
| **Dependencies** | Prioritisation against the Notion Feature List, which is the blocker on sequencing any of these |
| **Effort** | Not estimated |
| **Effort assumption** | Deliberately not estimated: without the specification there is no basis for deciding which of these are requirements and which are suggestions, and estimating them would imply a scope decision that is not the auditor's to make. |

**Why this matters.** Grouped because their priority cannot be established from the code alone. Two are worth singling out: account deletion (CD-PROFILE-05) carries a privacy and in some jurisdictions a legal expectation, and would need a plan for the orphaned Firestore subcollection; and crash reporting (CD-INFRA-10) matters precisely because the Apple Intelligence paths this audit could not verify would fail invisibly after release.

---

## J. Next steps

### Top five development tasks

1. Obtain the Notion Feature List and re-run the requirement mapping — nothing about overall completeness can be stated honestly until this is done.
2. Deploy the Firestore security rules and add cross-user denial tests.
3. Verify Firestore pantry CRUD against the Firebase Emulator Suite.
4. Configure OpenRouter credentials so Find Substitute works at all, and validate it live.
5. Build the dietary preferences profile, which is what makes the already-tested substitution restriction logic do anything.

### Most important validation activities

1. One documented end-to-end receipt scan on Apple Intelligence-capable hardware, through to verified Firestore documents (CD-SCAN-10) — the project's largest unverified claim.
2. One documented Pantry Ideas generation on the same hardware, judging usefulness and latency from real model output rather than from the prompt (CD-AI-01).
3. Manual authentication verification: registration, sign-in, Google sign-in, relaunch persistence, sign-out, and the untested account-switch scenario (CD-AUTH-01 through CD-AUTH-05).
4. Confirmation that the live Firebase project enforces the committed rules rather than test-mode defaults (CD-PANTRY-07).
5. Live OpenRouter requests measuring latency, JSON compliance and whether the model respects the instruction never to assert pantry availability (CD-SUBST-02).

### Before this project can be declared complete

Three things block a credible completion claim, in order. First, the specification: 65 code-derived requirements are a provisional baseline, and a requirement nobody implemented leaves no code trace to find. Second, integration evidence: 240 passing unit tests cover domain logic thoroughly and cover the four production integrations not at all. Third, device evidence: the two Apple Intelligence features and the camera cannot run on a simulator, so the app's headline capability has not been observed working by this audit.

---

## Appendix: assumptions and limitations

### Assumptions made in this audit

| # | Assumption | Consequence if wrong |
|---|---|---|
| 1 | The code-derived requirement baseline approximates the Notion Feature List closely enough to be a useful starting point for discussion. | Status counts and the roadmap would need re-deriving. The per-file code evidence remains valid regardless. |
| 2 | Priority assignments (P0/P1/P2) reflect what a reviewer of this codebase would reasonably prioritise. | Notion's own priorities take precedence; the roadmap ordering would change. |
| 3 | `main` at `65d2b60` is the current state of the work. | Unmerged branches would contain unaudited implementations. `git branch -a` showed no other local branches. |
| 4 | The absence of a feature in the source means it was never implemented, not that it was removed. | Git history was reviewed and showed one deliberate removal — the fridge-photo scanner, replaced by receipt scanning in `b79ee34` — whose residue is recorded as `CD-SCAN-11`. |
| 5 | `#if DEBUG` code (`ReceiptScanDiagnostics`, the excluded-items disclosure group) is excluded from release behaviour. | Verified by reading the conditionals; not verified by inspecting a release binary. |
| 6 | The live Firebase project's configuration matches `firestore.rules` as committed. | This is explicitly *not* assumed — it is recorded as unverified in `CD-PANTRY-07`, because the consequence of being wrong is a security one. |

### What this audit did not do

- **Did not modify any Swift production or test code.** No feature was implemented. The only files created are the three in `docs/`.
- **Did not read or report any credential.** `Config.xcconfig` was inspected with values redacted; `Secrets.xcconfig` does not exist in the working tree; `GoogleService-Info.plist` was confirmed present on disk and gitignored, and its contents were not read or reproduced. No Firebase project id, API key, OAuth client id or token appears in any of the three output files.
- **Did not invent requirements, test results, screenshots or dates.** Every test figure comes from the `xcodebuild` run recorded above. Every implementation claim cites a file and line.
- **Did not commit, push or deploy anything.**

### Missing source material

| Material | Impact |
|---|---|
| Notion Feature List | **Severe.** No authoritative requirements, IDs, acceptance criteria or priorities. No spec-relative completion figure. The *Not Started* section cannot be assumed complete. |
| Apple Intelligence-capable device | Two features (`CD-AI-01`, `CD-SCAN-05`) and the end-to-end scan (`CD-SCAN-10`) unverifiable. |
| Live Firebase credentials | Auth (`CD-AUTH-01`–`05`) and Firestore CRUD (`CD-PANTRY-06`) unverifiable. |
| `Secrets.xcconfig` / OpenRouter key | Substitutions non-functional in this checkout (`CD-SUBST-01`). |
| Firebase console access | Cannot confirm the rules are deployed (`CD-PANTRY-07`). |
| Physical camera | Capture path unverifiable (`CD-SCAN-01`). |
| README / setup docs | None exist; the repository's setup requirements had to be reconstructed from build files. |

---

*Generated 2026-10-11 from `docs/fridgefit-feature-audit.json`. The JSON dataset, this Markdown audit and `docs/fridgefit-feature-progress.html` are all produced from the same source of truth and present the same figures.*
