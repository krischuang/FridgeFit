# Core Data vs SwiftData vs Firebase — Backend Decision

**Decision:** **Option B — SwiftData behind the existing repository protocols,
with the Firebase implementations kept whole and selectable.**

**Confidence:** High on the SwiftData-over-Core-Data choice; high on
"behind the existing protocols"; deliberate NO on synchronisation (§6).

---

## 1. What the rubric actually requires

> "Native persistence using Core Data, SwiftData, or CloudKit. **These are
> alternatives, not three mandatory simultaneous implementations.**"

**[Verified]** against the audit: the project currently satisfies none of the
three (`PERSISTENCE_ARCHITECTURE_AUDIT.md` §0).

Two consequences follow, and both cut *against* over-building:

1. Implementing **one** native store, well, scores full marks. Implementing two
   scores the same marks and multiplies the regression surface.
2. Nothing in the rubric requires the native store to be the *only* store, or to
   synchronise with anything. "Native persistence" is a capability to
   demonstrate, not an exclusivity requirement.

---

## 2. The options

| | Option | One-line description |
|---|---|---|
| **A** | Replace Firebase with SwiftData | Rip out the three Firestore business repositories; SwiftData becomes the only store |
| **B** | SwiftData behind protocols | Add SwiftData implementations of the protocols that already exist; keep Firebase whole; choose at the composition root |
| **C** | Core Data behind protocols | As B, with Core Data instead of SwiftData |
| **D** | SwiftData local + Firebase sync | B, plus a bidirectional synchronisation layer |
| **E** | Something better | Assessed in §5 |

---

## 3. Weighted decision matrix

Weights are set by what the assessment and the project actually reward.
"Regression risk" carries 20 because the audit verified a green 1,114-test suite
and a working WebRTC/CoreML feature set — breaking those costs more marks
elsewhere than persistence can win. Scores are 1 (worst) to 5 (best).

| Criterion | Weight | **A** replace | **B** SwiftData adapter | **C** Core Data adapter | **D** + sync |
|---|---:|:---:|:---:|:---:|:---:|
| Assessment compliance | 25 | 5 | 5 | 5 | 5 |
| Regression risk to working features | 20 | 1 | 5 | 5 | 2 |
| Implementation complexity | 15 | 2 | 4 | 2 | 1 |
| Reversibility to Firebase | 10 | 1 | 5 | 5 | 3 |
| Testing complexity | 10 | 3 | 5 | 4 | 2 |
| Live-demo reliability | 10 | 4 | 5 | 4 | 3 |
| Offline capability | 5 | 5 | 4 | 4 | 5 |
| Multi-device support | 5 | 1 | 3 | 3 | 5 |
| **Weighted total (max 500)** | | **285** | **470** | **420** | **310** |
| **Normalised** | | **57%** | **94%** | **84%** | **62%** |

### Why each score

**A — Replace Firebase (285 / 57%).** Scores full compliance and the best
offline story, and is rejected anyway. Regression risk is 1 because the pantry
is reached by the receipt scanner, the camera review sheet, recipe feasibility,
substitutions and recommendations; the Firestore repositories are also the
things `firestore.rules` exists to protect, and three mapping test suites exist
to cover. Reversibility is 1 — deleting the Firebase adapters is the one change
this audit's brief explicitly wants to avoid. It also throws away multi-device
support, which the remote-camera feature's whole premise depends on.

**B — SwiftData behind protocols (470 / 94%).** Additive. The protocols already
exist and are domain-shaped (`PERSISTENCE_ARCHITECTURE_AUDIT.md` §3.2); the
domain models are already framework-free (§3.1); the backend is already chosen
in a composition root (§2.2). Nothing is deleted, so the Firebase adapters, the
security rules and the mapping tests all keep working. Regression risk is 5
because existing code paths are literally unmodified — new types are added
alongside. Loses a point on complexity only for the `ModelContainer` lifecycle,
and on multi-device because the SwiftData mode is single-device by definition.

**C — Core Data behind protocols (420 / 84%).** Identical architecture, identical
compliance, identical reversibility — and materially more work for no extra
marks. Complexity is 2 against SwiftData's 4 because Core Data needs an
`.xcdatamodeld` editor file, `NSManagedObject` subclasses or codegen, explicit
`NSPersistentContainer` setup, context-merge policy, and `NSFetchRequest` +
`NSPredicate` string-keyed predicates that the compiler cannot check. SwiftData
expresses the same model in annotated Swift types with `#Predicate` macros that
are type-checked. **This is the entire basis of the choice: same score, less
code, fewer ways to be wrong.**

**D — SwiftData + Firebase sync (310 / 62%).** Full compliance, best
multi-device — and the worst risk profile in the table. A correct bidirectional
sync needs stable identity, tombstones, conflict resolution, idempotent replay,
and sign-out/account-switch handling. Every one of those is a way to lose or
duplicate a user's data live in front of a marker. It earns **no additional
rubric marks** over B. Rejected on §6 grounds.

---

## 4. SwiftData compatibility verification

Not assumed — checked against this project's actual settings.

| Requirement | Project value | **[Verified]** verdict |
|---|---|---|
| SwiftData needs iOS 17+ | `IPHONEOS_DEPLOYMENT_TARGET = 26.0` | **Clear by nine major versions.** No `@available` guards, no back-deployment branch |
| Xcode 16+ | Xcode 26.1 (17B55) | Satisfied |
| Swift language mode | `SWIFT_VERSION = 5.0` | Swift 5 mode — SwiftData macros work; Swift 6 strict concurrency is *not* enforced, so no data-race errors will block the work |
| Default isolation | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` | **Important — see §4.1** |
| Approachable concurrency | `SWIFT_APPROACHABLE_CONCURRENCY = YES` | Source of the existing 17 warnings; unrelated to SwiftData |

### 4.1 The isolation detail that decides the implementation shape

`ModelContext` is **not** `Sendable`. How a SwiftData repository must be written
therefore depends on the isolation of the protocol it conforms to — and this
project's three relevant protocols differ:

**[Verified]** from the protocol declarations:

```swift
protocol PantryRepository: AnyObject            // Domain/Protocols/PantryRepository.swift:12
protocol InventoryEventRepository: AnyObject    // Domain/Protocols/InventoryEventRepository.swift:15
nonisolated protocol SavedRecipeRepository: RecipeRepository  // SavedRecipeRepository.swift:24
```

- `PantryRepository` and `InventoryEventRepository` are **not** `nonisolated`.
  Under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` their conformances are
  MainActor-isolated. A SwiftData implementation can therefore hold
  `container.mainContext` directly and needs **no actor plumbing at all**. This
  is the simplest possible correct implementation, and it matches how
  `InventoryStore` (`@MainActor`, `ViewModels/InventoryStore.swift:36`) already
  calls them.

- `SavedRecipeRepository` **is** declared `nonisolated`. A SwiftData conformance
  to it could not hold `mainContext`; it would need `@ModelActor` and its own
  background context.

**Consequence for the plan:** scope the SwiftData work to **PantryItem and
InventoryEvent**. Both are MainActor-friendly, both are the entities the demo
and the relational model actually need, and together they avoid introducing an
actor hierarchy for no marks. Saved recipes stay Firebase-only — which is also
consistent with that feature currently being switched off
(`PERSISTENCE_ARCHITECTURE_AUDIT.md` §5, item 3).

This is a **[Verified]** constraint read from the source, not a style preference.

---

## 5. Option E — is there something better?

Three alternatives were considered and rejected:

**CloudKit + SwiftData (`.automatic` cloud configuration).** Tempting: it is a
rubric-named native option and gives multi-device sync nearly free. Rejected
because SwiftData's CloudKit integration imposes model constraints — every
property must be optional or defaulted, and `@Attribute(.unique)` is not
supported with CloudKit. That directly conflicts with the uniqueness constraint
proposed in `DATA_MODEL_AND_RELATIONSHIPS.md`, and it would put a second cloud
sync system beside Firebase, competing for the same data. It also needs a paid
account's iCloud container, which is an availability risk on demo day.

**A generic `Repository<T>` protocol with a SwiftData backing.** Rejected on the
brief's own instruction and on merit: the existing protocols carry domain
meaning that a generic CRUD interface would erase. `InventoryEventRepository`
being append-only with no `update` is information; `Repository<InventoryEvent>`
would throw it away.

**Keep Firestore and add a local SwiftData *cache*.** Rejected: a cache is a sync
problem wearing a smaller hat (§6), and a cache that is only ever written-through
is harder to demonstrate as "native persistence" than a store that genuinely
owns its data.

So the refined recommendation is **B, plus two narrow additions** that cost
little and buy real marks:

1. A by-predicate read on `PantryRepository`, so "meaningful domain predicates
   and queries" has somewhere honest to live
   (`RECOMMENDED_ADAPTER_ARCHITECTURE.md` §4).
2. A third entity, `IngredientRecognitionRecord`, which makes the relational
   schema genuinely multi-entity **and** persists something the app currently
   throws away (`DATA_MODEL_AND_RELATIONSHIPS.md` §2).

---

## 6. Synchronisation: explicitly out of scope

Required by the brief to be justified rather than assumed. The justification is
that **it earns nothing and risks a lot**:

- The rubric asks for native persistence. It does not ask for sync.
- The app has **no real-time requirement in its business data** — **[Verified]**,
  the three business repositories use zero snapshot listeners
  (`PERSISTENCE_ARCHITECTURE_AUDIT.md` §4.2).
- Each mode has a single, unambiguous source of truth: in SwiftData mode the
  local store; in Firebase mode Firestore. No reconciliation question exists
  because the two are never live at once.
- **Switching adapters does not migrate data, and this audit set never claims it
  does.** Switching backend shows a different store's contents. That must be
  stated plainly in the presentation rather than glossed over.

See `FIREBASE_COMPATIBILITY_AND_ROLLBACK.md` §4 for the one-way import path, if
one is ever wanted.

---

## 7. Summary

| Question | Answer |
|---|---|
| SwiftData or Core Data? | **SwiftData** — same marks, markedly less code, type-checked predicates, deployment target clears it by nine versions |
| Replace Firebase? | **No** — additive adapters, nothing deleted |
| Dual adapter justified? | **Yes**, but only because the protocols and the composition root already exist. It is roughly a day of work, not a refactor |
| Synchronisation? | **No** — no marks, high risk, no real-time requirement in business data |
| Which entities? | **PantryItem, InventoryEvent, + IngredientRecognitionRecord.** Not saved recipes — `nonisolated` protocol, feature currently gated off |
