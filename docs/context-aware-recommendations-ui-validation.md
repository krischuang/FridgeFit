# Outstanding UI validation — context-aware recommendations

**Status:** outstanding. Merged into local `main` at `7609667` on 2026-10-15
with this validation accepted as a post-merge task rather than a merge
blocker.

**Why it is outstanding.** The feature was verified by a clean build, 964
automated tests, a dietary-label audit, and headless SwiftUI render tests.
It was *not* verified by interactive use. `FridgeFitApp` gates
`ContentView` behind `authViewModel.isAuthenticated`, so the Recipes tab
cannot be reached without signing in, and this project has no UI test
target (`FridgeFit` and `FridgeFitTests` only — no `XCUIApplication`
anywhere). Nobody has yet tapped through the flow.

Nothing below is a known defect. These are checks that have not been run.

## What *was* verified, so you know where the gap starts

| Verified | How |
|---|---|
| App builds, installs, launches without crashing | Installed and launched on iPhone 17 / iOS 26.1 |
| Exactly one `NavigationStack` owns the Recipes tab | `ContentView` L112; `RecipeRecommendationsView` and `RecipeDetailView` open none; `CookingContextFormView`'s stack is inside a `.sheet`, a separate presentation context — the pattern `PantryRecipeIdeasView` already uses |
| Every new view's body evaluates against real data | `RecommendationViewRenderingTests` — 12 `ImageRenderer` tests, including the richest possible row and `FlowLayout` wrapping at a narrow width |
| Ranking, explanations, expiry rules, session feedback | 106 unit tests under `FridgeFitTests/Recommendation/` |

The residual risk is therefore narrow: **runtime navigation chrome and
gesture handling**, which rendering cannot exercise.

## The manual pass

Sign in, open the **Recipes** tab, then:

- [ ] **1. Entry point.** A ✨ "Recommended" item sits in the toolbar beside
      💡 "Pantry Ideas".
- [ ] **2. Opens as a push.** Tapping it slides in with a back chevron
      (*not* a modal), titled "Recommended", with **one** navigation bar.
- [ ] **3. Results and explanations.** Ranked rows show readiness,
      "N% of essentials", and reason chips. Confirm
      *"Uses an ingredient expiring soon"* appears **only** for an item
      genuinely near expiry, and that an already-expired item instead shows
      the red *"past its date — replace before cooking"* caution.
- [ ] **4. Unverified amounts read honestly.** With a pantry item whose unit
      can't convert to the recipe's (e.g. stock in grams vs. millilitres),
      the row says "Check your amount of …" and **not** "Ready".
- [ ] **5. Preferences round-trip.** Toolbar ⚙︎ opens a sheet with its own
      bar. Set a 15-minute limit → Apply → list re-ranks and the header
      reads "… · preferences applied".
- [ ] **6. Allergen filters are not offered.** Reopen preferences: Gluten
      Free and Nut Free appear under "Not matched by FridgeFit", are not
      tappable, and explain why. (See `DietaryRestriction.assessmentBasis`.)
- [ ] **7. Detail navigation.** Tap a recommendation → the existing recipe
      detail opens with one bar → **back returns to the ranked list with the
      same order and session state intact**.
- [ ] **8. Session feedback.** Swipe right → Save (bookmark appears).
      Swipe left → Skip (row disappears). Swipe left → "Not for me" (dialog
      with four reasons; list re-ranks; row stays visible).
- [ ] **9. New session.** "Start a new session" restores skipped rows and
      clears badges.
- [ ] **10. Live pantry.** Add an item in Pantry or Kitchen, return, pull to
      refresh, confirm readiness updates.
- [ ] **11. Dynamic Type.** Repeat step 3 at the largest accessibility text
      size; reason chips wrap without clipping and the row stays legible.
- [ ] **12. Regression spot-check.** Recipe browsing, Pantry Ideas, Pantry
      and Kitchen tabs still behave as before.

## If something fails

Steps 2, 7 and 11 are the ones most likely to surface a real problem, and
each has an obvious first suspect:

- **Two navigation bars (2 or 7)** → something gained a `NavigationStack`
  of its own. Grep `FridgeFit/Views/Recipes/` — only
  `CookingContextFormView` should have one, and only because it is a sheet.
- **Back loses the list or re-ranks it (7)** → `RecipeRecommendationsView`
  regenerates on `.task` only when `!viewModel.hasRun`; check that guard.
- **Chips clip (11)** → `FlowLayout` in `RecommendationPresentation.swift`.

## Also worth doing before any release

- No UI test target exists. Adding one and automating steps 1–9 would close
  this gap permanently; it was deliberately not added as part of the merge
  to avoid changing the Xcode project on the way in.
- A signed-in device run against live Firestore, rather than the in-memory
  repositories the tests use.
