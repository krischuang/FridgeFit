# SwiftData Implementation — Report and Evidence

**Branch:** `feat/swiftdata-persistence`
**Baseline:** `main` at `34a9b85`
**Toolchain:** Xcode 26.1 (17B55), iOS deployment target 26.0, Swift 5 mode
**Nothing pushed. No Firebase resource deployed or modified.**

Every number below came from a command that was run. Where something was
*not* executed, it says so.

---

## 1. What was built

| Area | Files | Lines |
|---|---:|---:|
| SwiftData persistence layer (`Data/SwiftData/`) | 6 | 697 |
| Composition root + configuration | 2 | 188 |
| New test files | 6 | 1,506 |
| **Total diff vs `main`** | **101 changed** | **+2,912 / −141** |

The app target's existing ~30,800 lines of views, view models, use cases and
domain models are untouched except for the three wiring changes in §3.

---

## 2. Build and test evidence

### 2.1 Clean build — **0 errors, 0 compiler warnings**

```bash
xcodebuild clean -scheme FridgeFit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild build-for-testing -scheme FridgeFit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

→ `EXIT=0`, `: error:` × 0, `: warning:` × 0

The only remaining lines matching "warning" in the log are two from
`appintentsmetadataprocessor` ("Metadata extraction skipped. No
AppIntents.framework dependency found"). That is a build-tool notice about an
Apple framework the app does not use — not a source diagnostic, and not
attributable to any file.

### 2.2 Full test suite — **1,204 passed, 0 failed, 4 skipped**

```bash
xcodebuild test-without-building -scheme FridgeFit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

→ `EXIT=0`, `Test Suite 'All tests' passed`
→ `Executed 1204 tests, with 4 tests skipped and 0 failures (0 unexpected) in 48.526 seconds`

The 4 skips are the same four that were skipped before this work began —
`HybridRecognitionEvaluationTests`, the gated model-evaluation harness. No test
was deleted, weakened or newly skipped.

| | Baseline | Now | Δ |
|---|---:|---:|---:|
| Tests executed | 1,114 | **1,204** | **+90** |
| Failures | 0 | **0** | — |
| Skipped | 4 | **4** | — |

### 2.3 Firestore emulator rules suite — **60 passed, 0 failed**

The audit could not run this and marked it unverified. It has now been run:

```bash
cd firestore-tests && npm test
# → firebase emulators:exec --only firestore --project fridgefit-rules-test
```

→ `EXIT=0` — `# tests 60 / # pass 60 / # fail 0`

Local emulator only, against a throwaway project id. **No rules were deployed
and no production Firebase resource was contacted.**

### 2.4 Privacy manifest — verified in the bundle

Not inferred from the file existing:

```
FridgeFit.app/PrivacyInfo.xcprivacy   3722 bytes
```

---

## 3. The three wiring changes

Everything else is additive. These are the only pre-existing behavioural
seams that moved:

| File | Change |
|---|---|
| `FridgeFitApp.swift` | Builds `AppDependencies` once at launch; shows an explained failure view if the store cannot open |
| `ContentView.swift` | `init(dependencies:)` instead of constructing Firestore repositories inline. The other ~90 lines of wiring are unchanged |
| `Views/Support/PantryRepositoryEnvironment.swift` | Default is now `UnconfiguredPantryRepository` instead of a live `FirestorePantryRepository()` |

### 3.1 Single point of backend selection — verified by grep

```
grep -rn "FirestorePantryRepository(" FridgeFit/ --include="*.swift"
→ AppDependencies.swift:86   (the only construction)
→ 3 further hits, all inside doc comments
```

`PersistenceConfiguration` is read in exactly one place: `AppDependencies`.

---

## 4. Engineering challenges — root cause, impact, resolution, verification

All four were encountered during this work. None is invented.

### 4.1 The warning baseline was wrong by a factor of 22

**Root cause.** The audit measured 17 warnings from an *incremental* build that
had not recompiled most of the project. Xcode does not re-emit diagnostics for
files it does not rebuild.

**Impact.** Phase 1 was scoped as "fix 17 warnings". The real figure was 382,
and the acceptance criterion was zero.

**Resolution.** Verified first, then fixed. The work was stashed,
`xcodebuild clean` run, and the untouched baseline rebuilt: **exit 0, 382
warnings**. The cause was a single setting — `SWIFT_DEFAULT_ACTOR_ISOLATION =
MainActor` — meeting a codebase that was already *half* migrated: `InventoryEvent`,
`StorageLocation` and the inventory use cases were `nonisolated`, the types
around them were not, and every unmarked type became an isolation boundary for
the marked ones.

The decisive evidence was an experiment that made things worse: marking
`PantryItem` alone moved the count in the wrong direction, which showed the fix
was to *finish* the migration rather than patch its edges.

**Verification.** Clean build, 0 errors, 0 compiler warnings; suite unchanged at
1,114 / 0 / 4.

### 4.2 A nonisolated protocol cannot hold a `ModelContext`

**Root cause.** Phase 1 marked the repository protocols `nonisolated`. A
`nonisolated` protocol forces its witnesses nonisolated, so a `@MainActor`
repository could not touch `mainContext` — 21 errors of the form "main
actor-isolated instance method cannot be called from outside of the actor".

**Impact.** The SwiftData repositories would not compile.

**Resolution.** `PantryRepository` and `InventoryEventRepository` returned to
main-actor isolation. The alternative — `@ModelActor` — was rejected on a
correctness ground, not a stylistic one: each `@ModelActor` creates its *own*
context, and an event can only be linked to its pantry item when both objects
are managed by the same context. Two contexts would have left the relationship
silently `nil` exactly when the pantry had just written the row the event refers
to, which is the common case in `AddInventoryItemUseCase`.

**Verification.** 0 errors; `test_appendingAnEvent_linksItToItsItem` asserts the
relationship is actually populated.

### 4.3 SwiftData cannot lower a force-unwrap into a store query

**Root cause.** `fetchExpiring` first used
`expiryDate != nil && expiryDate! <= date`. It compiles, and then fails at fetch
time, because the predicate has to be translated into a query the store can run.

**Impact.** One test failed with `storageUnavailable` — the domain error wrapper
had converted SwiftData's own error into a generic one. Right for users, and it
did make the cause harder to find.

**Resolution.** `(item.expiryDate ?? unbounded) <= date`, where `unbounded` is
`Date.distantFuture` captured as a local. Nil-coalescing maps onto an expression
the store understands, and undated items fall outside every window — which is
the intended rule anyway.

**Verification.** `test_fetchExpiring_excludesUndatedItems_andOrdersSoonestFirst`
passes, and the contract suite asserts the same rule for all backends.

### 4.4 Two ways to abort the test host

Both were found by bisecting the suite one test at a time, and both are
environment limits rather than defects in the adapter.

**Constructing Firestore in-process.** `AppDependencies(backend: .firebase)`
inside a unit test aborts with `malloc: pointer being freed was not allocated`,
killing the run and taking the rest of the suite with it. Consistent with this
project's existing suite, which has *never* instantiated a Firestore client —
the three Firestore mapping suites test `encode`/`decode` as pure static
functions precisely so no client is needed.

**Building the `@MainActor` graph from a synchronous test.** The identical body
in an `async` method is fine. The crash tracked whichever test was alphabetically
first to construct `AppDependencies`, which is what identified the pattern.

**Resolution.** Every test touching the graph is `async`, and that requirement is
documented where the next person will hit it. The Firebase graph is **not**
covered by an automated test; see §5.

---

## 5. What is *not* covered

Stated plainly rather than left for a marker to discover.

| Gap | Why | How it is covered instead |
|---|---|---|
| `AppDependencies(backend: .firebase)` construction | Aborts the test host (§4.4) | Launch the app with `-persistence firebase`; `firestore-tests/` covers the rules |
| Firestore `fetch(id:)` / `fetchExpiring(before:)` behaviour | Needs a live client | Contract suite defines the semantics; the implementations are small and the mapping is separately tested |
| UI / VoiceOver behaviour | No UI test target exists, and adding one is a new target and a new scheme | Manual check |
| On-device run | Not performed in this session | Simulator only — see §6 |

---

## 6. Explicitly not done

- **No synchronisation, migration, conflict resolution or reconciliation**
  between SwiftData and Firebase, per the approved scope. Switching backend
  changes which store is read and copies nothing.
- **No user-facing database switcher.**
- **No change** to Firebase Authentication, WebRTC signalling, device presence,
  remote-camera transport, or `firestore.rules`.
- **No deployment** of anything, and **no push** to any remote.
- **No device testing.** Everything here was run on the iPhone 17 Pro simulator
  (iOS 26.1). The persistence work has no device-only dependency, but that is a
  reasoned expectation, not a measurement.
