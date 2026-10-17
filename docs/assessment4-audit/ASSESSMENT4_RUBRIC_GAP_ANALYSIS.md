# Assessment 4 — Rubric Gap Analysis

**Reviewer stance:** strict tutor. Marks are withheld where a requirement is
named and unmet, even when the surrounding work is strong.

---

## 0. A warning about this document's authority

> **[Verified]** **No assessment brief, rubric, or marking guide exists in this
> repository.** A search for `*assess*`, `*rubric*`, `*criteri*` and `*marking*`
> returned only unrelated Python dependencies.

Every criterion and weighting below is transcribed from the task description
supplied to the auditor. **None of it has been checked against a source
document.** Before acting on these numbers:

1. Add the real brief to the repository.
2. Re-check the weightings — particularly the 9 marks grouped here as
   "product, marketing, collaboration, documentation", which are opaque.
3. Confirm whether the "advanced platform capability" requirement names
   specific technologies or accepts any.

Treat the estimates as **a calibrated argument, not a predicted mark.**

---

## 1. Scoreboard

Marks shown as *verifiable from the codebase* vs *not*.

| # | Criterion | Max | Current (est.) | After plan (est.) | Verifiable from code? |
|---|---|---:|---:|---:|---|
| 1 | Software Architecture, Platform Integration & Persistence | 4 | **2.0** | **4.0** | Yes |
| 2 | Automated Testing & Code Quality | 3 | **2.0** | **3.0** | Yes |
| 3 | App Store Readiness & HIG Compliance | 4 | **2.0** | **3.5** | Mostly |
| 4 | Live Tutorial Presentation | 10 | **—** | **—** | No — delivery |
| 5 | Product, marketing, collaboration, documentation | 9 | **—** | **—** | Partly |
| | **Code-verifiable subtotal** | **11** | **6.0** | **10.5** | |

**The honest headline: the plan moves roughly 4.5 of the 11 code-verifiable
marks.** The other 19 marks are earned by presenting and by non-code artefacts,
and no amount of persistence refactoring touches them. §6 covers that.

---

## 2. Criterion 1 — Architecture, Platform Integration & Persistence (4)

### Current: **2.0 / 4**

| Sub-requirement | State | Evidence |
|---|---|---|
| Native persistence (Core Data / SwiftData / CloudKit) | **FAIL** | **[Verified]** zero matches for `import SwiftData`, `import CoreData`, `@Model`, `NSManagedObject`, `CloudKit` across the repository |
| MVVM | **PASS** | 15 view models in `ViewModels/`, all `ObservableObject`; views hold no business logic |
| Use Case layer | **PASS** | 30 files in `UseCases/`; real validation, e.g. `AddPantryItemUseCase.swift:58-67` |
| Repository pattern | **PASS** | 4 protocols in `Domain/Protocols/`, each with ≥2 implementations |
| Protocol-based abstractions | **PASS** | Domain-shaped, not generic CRUD; `InventoryEventRepository` is append-only by design (`:20-21`) |
| ≥4 business operations with domain errors | **PASS** | 4 inventory use cases + 13 error types in `Domain/Errors/` |
| Multi-entity relational schema | **FAIL** | No schema exists. Firestore collections are not relational and enforce no referential integrity |
| Meaningful domain predicates/queries | **FAIL** | **[Verified]** three use cases find one item by fetching the whole collection and scanning client-side (`RecordIngredientUseUseCase.swift:49`, `RecordFoodOutcomeUseCase.swift:76,99`) |
| Clean layer separation | **PASS** | One unused `import FirebaseAuth` (`Views/ProfileView.swift:6`) is the only breach, and it is dead |
| Advanced platform capability | **PASS, twice** | CoreML (`YOLO11n.mlpackage`, `FridgeFitIngredients.mlpackage`) **and** Foundation Models (`AppleReceiptIngredientInterpreter.swift`) |

**Why 2.0 and not 3.0.** The architecture is genuinely good — better than this
rubric is written to detect. But three sub-requirements fail, and they are not
peripheral: native persistence, a relational schema, and domain predicates are
the *persistence half* of a criterion whose title is half persistence. A strict
marker reading "native persistence using Core Data, SwiftData, or CloudKit" and
finding none cannot award above half, however good the layering is.

**Why not 1.0.** Six sub-requirements pass on real evidence, and the advanced
capability requirement is satisfied twice over with working CoreML and
Foundation Models integrations.

### After the plan: **4.0 / 4**

Requires P0-1, P0-3 (native persistence + composition root), P1-1 (predicates),
and the relational schema in `DATA_MODEL_AND_RELATIONSHIPS.md`.

**Remaining risk:** a marker who expects native persistence to be *the* store
rather than *a selectable* store. Mitigation: ship with `.swiftData` as the
compiled default, so the graded build demonstrates the graded feature on launch,
and present the Firebase adapter as deliberate architecture rather than as a
leftover.

---

## 3. Criterion 2 — Automated Testing & Code Quality (3)

### Current: **2.0 / 3**

| Sub-requirement | State | Evidence |
|---|---|---|
| ≥5 domain unit tests with mock repositories | **PASS, far exceeded** | **[Verified]** 1,114 test functions in 85 classes; `InMemoryPantryRepository` and `FailingPantryRepository` are the doubles |
| Tests actually pass | **PASS** | **[Verified] executed:** `Executed 1114 tests, with 4 tests skipped and 0 failures` in 55.4s |
| Xcode 16+ compatibility | **PASS** | Xcode 26.1 (17B55) |
| **Clean build, zero warnings/errors** | **FAIL** | **[Verified] executed:** 0 errors but **17 warnings** — 3 in the app target, 14 in tests |
| Tests prove persistence | **FAIL** | No test touches a database; there is none to touch |
| Code quality | **STRONG** | Doc comments explain *why*, not *what*; see `InventoryEvent.swift:58-68` on why finished items leave the pantry |

**Why 2.0.** Test quantity and quality are excellent and the suite is genuinely
green. Two things hold it back: "zero warnings" is an explicit, checkable
requirement that currently fails, and no test demonstrates persistence — the
criterion's whole point in a persistence assessment.

The 17 warnings are all one diagnostic class, from
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` meeting MainActor types in
default-argument expressions:

```
FridgeFit/Data/OnlineRecipePreferencesStore.swift:47:50
FridgeFit/ViewModels/PantryViewModel.swift:32:47
FridgeFit/ViewModels/RecipeViewModel.swift:56:46, 57:46
+ 14 across 4 test files
```

### After the plan: **3.0 / 3**

Requires P0-2 (warnings → 0) and P2-1/2/3 (contract, integration, relaunch
tests).

**Remaining risk:** low. P0-2 is mechanical and independently verifiable by
re-running the build.

---

## 4. Criterion 3 — App Store Readiness & HIG Compliance (4)

### Current: **2.0 / 4**

| Sub-requirement | State | Evidence |
|---|---|---|
| Production error handling | **PASS, strong** | 13 `LocalizedError` types with user-facing messages; features degrade with an explanation rather than crashing (`AppleIntelligenceAvailability`, `UnconfiguredOnlineRecipeService`) |
| Privacy — usage descriptions | **PASS** | `NSCameraUsageDescription` present and well written (`Info.plist:14-15`). `PhotosPicker` correctly needs none |
| Privacy — secrets hygiene | **PASS** | API keys via gitignored `Secrets.xcconfig`; `Config.xcconfig` documents it |
| Privacy — data boundaries | **PASS** | `firestore.rules` scopes everything to `users/{uid}`; the receipt scanner keeps the photo on-device |
| **Privacy manifest** | **FAIL** | **[Verified]** no `PrivacyInfo.xcprivacy` anywhere. Required for submission; the app uses `UserDefaults` (a declared-reason API) and third-party SDKs |
| **Accessibility** | **FAIL** | **[Verified]** **2** `accessibilityLabel` call sites across 30,863 lines. Detection overlays, ingredient tiles and camera controls are unlabelled |
| **Localization** | **FAIL** | **[Verified]** no `.strings`/`.xcstrings`; all copy is inline English |
| HIG — navigation | **PASS** | One `NavigationStack` per tab, documented at `ContentView.swift:146-148` |
| Signing configuration | **PASS** | Per-developer via `Secrets.xcconfig`, nothing committed |

**Why 2.0.** Error handling, privacy boundaries and secret hygiene are better
than typical student work. But "App Store–Ready" is the criterion's name, and an
app with no privacy manifest **cannot be submitted** — that is a hard gate, not
a deduction. Two accessibility labels in a 30,000-line app is not partial
compliance.

### After the plan: **3.5 / 4**

P3 adds the privacy manifest (**S**) and accessibility labels on the main flows
(**M**). Full localization is **L** and is deliberately out of scope — hence 3.5
rather than 4.0. **This is the one criterion the plan does not fully close, and
that is stated rather than papered over.**

---

## 5. Criterion 4 — Live Tutorial Presentation (10)

**Not assessable from the repository.** Ten marks — a third of the total — are
earned by what happens in the room.

What the codebase *can* contribute:

| Readiness factor | Current | After |
|---|---|---|
| Can demonstrate native persistence | **No — impossible today** | Yes, incl. terminate-and-relaunch |
| Can demonstrate a relational query | No | Yes (two, `DATA_MODEL_AND_RELATIONSHIPS.md` §5) |
| Can show a green test suite live | **Yes** — 1114 tests in 55s | Yes |
| Can explain architecture from a diagram | Partially — `docs/` is extensive but has no architecture diagram | Yes |
| Has a real technical-hurdle story | Yes — detection tuning is documented across 7 files in `docs/` | Yes |
| Demo failure risk | Medium — Firestore needs network and auth | **Lower** — SwiftData mode needs neither |

Worth noting: **SwiftData mode makes the demo more robust**, because it removes
the network and sign-in from the critical path. That is a presentation-marks
argument for the change, independent of the persistence marks.

See `PRESENTATION_EVIDENCE_PLAN.md`.

---

## 6. Criterion 5 — Product, marketing, collaboration, documentation (9)

**Largely not assessable from the repository**, and not addressable by
persistence work. Partial observations:

| Element | Observation |
|---|---|
| Technical documentation | **[Verified] strong** — 17 files in `docs/`, including genuine experimental write-ups (`hybrid-stage1/2/3-results.md`, `detection-confidence-filtering.md`) |
| Architecture documentation | **[Verified] absent** until this audit set. `README.md` covers setup, not architecture |
| Collaboration evidence | Git history shows feature branches and `--no-ff` merges; contributor split not assessed |
| Marketing / product artefacts | None in the repository. Likely external |

**Action outside this audit's scope:** confirm where the marketing, product and
collaboration deliverables live. **9 marks — the second-largest block — are not
in this repository at all.**

---

## 7. Requirements that persistence work cannot satisfy

Stated explicitly, as the brief requires:

1. **Presentation delivery (10).** Rehearsal, timing, division of speaking.
2. **Marketing and product artefacts (part of 9).** Not in the repository.
3. **Collaboration evidence (part of 9).** Commit distribution across the team.
4. **Localization (part of criterion 3).** **L** effort, out of scope.
5. **Full accessibility sweep.** The plan covers main flows, not the camera
   overlays.
6. **The missing brief.** The single highest-leverage non-code action is to
   obtain the actual rubric and re-run §1.

---

## 8. Verified facts vs assumptions

**[Verified] — executed or read during this audit**

- No SwiftData / Core Data / CloudKit anywhere (grep).
- Build: 0 errors, 17 warnings (xcodebuild).
- Tests: 1114 executed, 0 failures, 4 skipped (xcodebuild).
- 1,114 test functions, 85 `XCTestCase` classes, 0 Swift Testing.
- No `PrivacyInfo.xcprivacy`; 2 `accessibilityLabel`; no localization.
- Deployment target 26.0; Swift 5 mode; Xcode 26.1.
- Firebase in 9 app files; snapshot listeners only in remote-camera code.
- `ProfileView`'s `import FirebaseAuth` is unused.
- No assessment brief in the repository.

**[Assumption] — not verified**

- All mark weightings (no source document).
- That a marker weights native persistence as heavily as §2 assumes.
- `firestore-tests/` passes — **not run**.
- Current marks for criteria 4 and 5 — unknowable from code.
- That the demo runs on a simulator rather than a device.
