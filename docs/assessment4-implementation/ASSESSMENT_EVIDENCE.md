# Assessment 4 — Evidence, Scoring and Readiness

Scored conservatively against the marking breakdown supplied with the
implementation brief. Where a mark depends on something outside the
repository, it says so rather than guessing.

> **Still unresolved:** no assessment brief or rubric file exists in this
> repository. The breakdown below is the one supplied in the task
> description; it has not been checked against a source document. Adding the
> real brief to the repo remains the highest-leverage non-code action.

---

## 1. Scoreboard

| Criterion | Max | Before | After | Verifiable from code? |
|---|---:|---:|---:|---|
| Problem Formulation, Evidence & Competitor Analysis | 2 | — | — | No |
| App Store Readiness & HIG Compliance | 4 | 2.0 | **3.0** | Mostly |
| App Store Presence & Marketing Collateral | 4 | — | — | No |
| Software Architecture, Platform Integration & Persistence | 4 | 2.0 | **3.5–4.0** | Yes |
| Automated Testing & Code Quality | 3 | 2.0 | **3.0** | Yes |
| Live Tutorial Presentation | 10 | — | — | No — delivery |
| Team Collaboration, Git Workflow & Reflective Report | 3 | — | — | Partly |
| **Code-verifiable subtotal** | **11** | **6.0** | **9.5–10.0** | |

**19 of the 30 marks are earned outside the code**: presentation delivery (10),
marketing collateral (4), problem/competitor evidence (2), and team
collaboration plus reflections (3). No persistence work touches them.

---

## 2. Architecture, Platform Integration & Persistence — 3.5–4.0 / 4

| Requirement | State | Evidence |
|---|---|---|
| Native persistence | **Met** | SwiftData is the default backend; 697 lines under `Data/SwiftData/` |
| Multi-entity relational schema | **Met** | 2 `@Model` entities, one-to-many, `.nullify`, unique ids |
| Meaningful predicates and queries | **Met** | `fetch(id:)`, `fetchExpiring(before:)` with compound predicate + two-key sort; limited, sorted event fetch |
| Working CRUD | **Met** | Contract suite runs the same assertions against two implementations |
| Data survives restart | **Met** | `SwiftDataPersistenceRetentionTests` — real file, second container |
| MVVM + Use Case + Repository | **Met** | Pre-existing, preserved unchanged |
| Framework-independent domain models | **Met** | `@Model` types confined to `Data/SwiftData/`; domain remains plain structs |
| Correct dependency injection | **Met** | `AppDependencies` is the only backend construction site (grep-verified) |
| Advanced platform capability | **Met twice** | CoreML (`YOLO11n`, `FridgeFitIngredients`) and Foundation Models |
| Firebase preserved and selectable | **Met** | Untouched adapters; one-line switch; emulator rules suite passing |

**Why not a flat 4.0.** Two honest reservations. The schema has two entities —
enough for "multi-entity relational", and every column is load-bearing, but a
marker expecting a richer graph may read it as thin. And in SwiftData mode the
local store is device-scoped: `ownerID` keeps accounts apart on one device, but
it is not the security boundary Firestore rules provide. Both are stated in the
documentation rather than hidden, which is the right posture, but neither is
worth claiming full marks over unprompted.

---

## 3. Automated Testing & Code Quality — 3.0 / 3

| Requirement | State | Evidence |
|---|---|---|
| ≥5 domain unit tests with mock repositories | **Far exceeded** | 1,204 tests |
| Tests actually pass | **Met** | `Executed 1204 tests … 0 failures`, exit 0 |
| Zero build warnings | **Met** | Clean build: 0 errors, 0 compiler warnings (was 382) |
| Tests prove real persistence | **Met** | Retention tests reopen a real file through a second container |
| Repository contract consistency | **Met** | One suite, two implementations |
| No weakened or deleted tests | **Met** | Baseline 1,114 → 1,204; same 4 pre-existing skips |

This is the criterion with the least doubt attached: every sub-requirement is
backed by a command whose output is recorded in
[`IMPLEMENTATION_REPORT.md`](IMPLEMENTATION_REPORT.md) §2.

---

## 4. App Store Readiness & HIG Compliance — 3.0 / 4

| Item | State | Note |
|---|---|---|
| Privacy manifest | **Fixed** | `PrivacyInfo.xcprivacy` added and verified inside the built `.app` |
| Permission handling | **Good** | `NSCameraUsageDescription` is specific and honest; `PhotosPicker` correctly needs none |
| Production error handling | **Strong** | 14 `LocalizedError` types; features degrade with an explanation rather than crashing |
| Loading and error states | **Good** | Per-screen `isLoading`, scoped error messages, explained unavailable states |
| App stability | **Good** | No force-unwraps added; storage failures surface as domain errors |
| Zero warnings | **Met** | §3 |
| Secrets hygiene | **Good** | Keys via gitignored `Secrets.xcconfig` |
| Accessibility | **Partial** | 34 `accessibilityLabel`, 79 accessibility modifiers; the add/edit form was unlabelled and is now covered |
| **Dark Mode** | **Not verified** | Uses semantic colours and a `KitchenTheme`, but was not visually checked |
| **Dynamic Type** | **Not verified** | No `dynamicTypeSize` usage; fixed tile widths (`frame(width: 116)`) are a plausible truncation risk at large sizes |
| **Localization** | **Absent** | All copy is inline English. Out of scope — large, and not required unless the brief says so |

**Correction to the audit.** It reported "2 `accessibilityLabel` call sites",
which was wrong — an artifact of a grep whose alternation let `.accessibility`
absorb `.accessibilityLabel`. The real figures are 34 labels and 79 modifiers.
Accessibility was already reasonable with specific gaps, not nearly absent.

**To reach 4.0:** verify Dark Mode and Dynamic Type on device or in the
simulator's accessibility inspector, and label the remaining unlabelled view
files (`RecipeListView`, `RecipeDetailView`, `RecipeRecommendationsView`,
`CameraModeView`, `ProfileView`). Neither was done here; both are small.

---

## 5. Live demonstration plan

Not yet rehearsed — **the app was not launched during this work.** Everything
below is backed by an automated test of the same behaviour, which is why the
sequence is worth trusting enough to rehearse, not worth claiming as performed.

| # | Action | Proves | Automated equivalent |
|---|---|---|---|
| 1 | Launch (SwiftData is the default — no argument needed) | Native persistence is the running configuration | `test_compiledDefaultIsSwiftData` |
| 2 | Kitchen → add "Greek Yogurt", 2 pcs, Fridge, expires in 2 days | Use case → protocol → SwiftData | `test_add_thenFetchAll_roundTripsEveryField` |
| 3 | Add "greek yogurt" again → duplicate refused | A domain error, case-insensitively matched | `test_confirmingTheSameIngredientTwice_doesNotCreateASecondRow` |
| 4 | **Terminate from Xcode** (not background) | Sets up the only proof that matters | — |
| 5 | **Turn Wi-Fi off, relaunch** — the item is still there | Data is on the device, not a cloud cache | `test_pantryItemSurvivesTheStoreBeingClosedAndReopened` |
| 6 | Record using 1 pc → amount drops, activity shows "Used 1 pcs" | Two entities written in one operation | `test_appendingAnEvent_linksItToItsItem` |
| 7 | Finish the item → it leaves the pantry, **history remains** | The `.nullify` delete rule | `test_deletingAnItem_keepsItsHistory` |
| 8 | "Use First" ordered by expiry | A real `#Predicate` + two-key sort | `test_fetchExpiring_excludesUndatedItems_andOrdersSoonestFirst` |
| 9 | Scheme → `-persistence firebase`, relaunch → the cloud pantry | The Firebase adapter is alive and the stores are separate | *None — see below* |

**Rules.** Step 5 is the demonstration; if time collapses, do 1, 2, 4, 5, 7.
Turn Wi-Fi off **visibly** — it converts "it persisted" into "it persisted
*locally*" and answers the obvious challenge before it is asked. Step 9 is the
only networked step, so it goes last.

**Never say "switching modes syncs the data."** It does not. Say: *two separate
stores, one protocol, selected at the composition root.*

> Step 9 has no automated backing — constructing Firestore inside the test host
> aborts it. **Rehearse step 9 at least once before the day.**

---

## 6. Technical portion of the group presentation (~90 seconds)

> "FridgeFit was built on Firebase. For this assessment we added native
> persistence — and the interesting part is what we *didn't* have to change.
>
> The app already had repository protocols and domain models that were plain
> Swift structs with no framework imports. So adding SwiftData meant writing new
> implementations of protocols that already existed. Thirty thousand lines of
> views, view models and use cases are untouched — not refactored, untouched.
>
> One delete rule is load-bearing. Finishing a carton of milk removes the pantry
> item and then writes the event saying it was finished. If events cascaded from
> items, that delete would erase the record of the thing that just happened — so
> the rule is nullify, and the history outlives the food.
>
> We deliberately did **not** build synchronisation. The rubric asks for native
> persistence, not sync, and we checked: the pantry code uses zero snapshot
> listeners, so there was no real-time behaviour to preserve. What *does* need
> real time is the remote camera, where two phones negotiate a WebRTC
> connection. A local database cannot do that, so it stayed on Firebase.
>
> [demo steps 1–7]
>
> That survived a terminate and a relaunch with Wi-Fi off. It's on the device."

**Engineering hurdle, if asked for one** — the most defensible is the warning
baseline: the audit measured 17 warnings from an incremental build; a clean
build of untouched code emitted 382. The cause was a half-finished concurrency
migration, and the diagnostic step that proved it was an experiment that made
things *worse*. It shows measurement before action, which is the thing being
assessed.

---

## 7. Outstanding — what 30/30 would still require

### Code (small, not done here)
1. Verify Dark Mode and Dynamic Type; fix any truncation at large sizes.
2. Accessibility labels on the five remaining unlabelled view files.
3. Rehearse demo step 9 (`-persistence firebase`) at least once.
4. Run once on a physical device.

### Not in this repository at all — **19 marks**
5. **Marketing collateral (4):** App Store screenshots, description, keywords,
   promotional text, app preview.
6. **Problem formulation and competitor analysis (2):** evidence of the problem,
   named competitors, differentiation.
7. **Team collaboration and reflections (3):** Contribution Matrix, git
   contribution evidence, group and individual reflective reports.
8. **Presentation (10):** slides, speaking split across all members, rehearsal
   to time.
9. **The Required Document (PDF)** assembling the above.

> None of items 5–9 exists in the repository, and **none was fabricated**. No
> contribution, reflection or authorship has been invented for any group member.

### Decisions for the team
10. Deploy `firestore.rules` before the demo? It would switch saved recipes on,
    changing behaviour during assessment week — sequence it deliberately.
11. Keep `.swiftData` as the compiled default? Recommended: the graded build
    then demonstrates the graded feature on launch.

---

## 8. Git

| | |
|---|---|
| Implementation branch | `feat/swiftdata-persistence` |
| Cut from | `docs/assessment4-persistence-audit` (preserved, 9 commits) |
| Pushed | **No** |
| Firebase deployed | **No** |
| Co-author trailers | **None** |
| Authorship | Single author; nothing attributed to anyone else |
