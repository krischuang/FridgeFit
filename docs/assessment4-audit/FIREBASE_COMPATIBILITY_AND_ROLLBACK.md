# Firebase Compatibility, Data Ownership and Rollback

**Purpose:** prove that adding SwiftData does not degrade any Firebase feature,
and that Firebase can be restored as the primary backend afterwards with a
one-line change.

---

## 1. Classification of every piece of data

The brief asks for five categories. Each item below is **[Verified]** by reading
the named implementation.

### 1.1 Local persistent business data → **moves to the configured backend**

| Data | Current home | Evidence |
|---|---|---|
| Pantry items | `users/{uid}/pantry` | `FirestorePantryRepository.swift:36` |
| Inventory events | `users/{uid}/inventoryEvents` | `FirestoreInventoryEventRepository.swift:36` |

Both are one-shot reads and writes with **no snapshot listeners**. Nothing
observes them in real time; `InventoryStore` re-reads after each write by
explicit design (`ViewModels/InventoryStore.swift:29-35`). **Swapping their
backend therefore costs zero live-update behaviour.**

### 1.2 Cloud-synchronised business data → **stays Firebase**

| Data | Why it stays |
|---|---|
| Saved recipes | `SavedRecipeRepository` is **[Verified]** declared `nonisolated` (`SavedRecipeRepository.swift:24`), so a SwiftData conformance needs `@ModelActor`. The feature is also **[Verified]** switched off — `OnlineRecipeFeature.savedRecipeStorage` is `.disabledPendingRulesDeployment` and `ContentView.swift:50` receives `nil`. Cost to port: real. Benefit: none. |

### 1.3 Ephemeral session state → **stays Firebase, permanently**

| Data | Firestore API used | Evidence |
|---|---|---|
| WebRTC offer/answer | `runTransaction` | `FirestoreSignalingTransport.swift:115` |
| Session document updates | `addSnapshotListener` | `:176` |
| ICE candidates | `addSnapshotListener` | `:222` |
| Inbound session discovery | `addSnapshotListener` | `:267` |
| Device presence | `addSnapshotListener` | `FirestoreDeviceRegistry.swift:130` |

**This is the category the brief warns about, and the warning is correct.**
Signalling is a *rendezvous between two devices that cannot see each other*. A
local database is not merely a poor fit — it cannot perform the function at all,
because the two phones share no local store. `runTransaction` is doing real work
here: it is how one device atomically claims an offer without both answering.

A local store also could not replace device presence: a heartbeat
(`DeviceHeartbeat.swift`) is only meaningful to an *observer on another device*.

**No part of the remote-camera subsystem is touched by this proposal.**

### 1.4 Authentication state → **stays Firebase, permanently**

`AuthViewModel` (`AuthViewModel.swift:12-98`) owns email/password sign-in,
Google federated sign-in, and an `addStateDidChangeListener` handle. Firebase
Auth also backs the `users/{uid}` path that every security rule depends on
(`firestore.rules:33-35`).

Unaffected. SwiftData has no opinion about identity — which is exactly the
limitation recorded in `RECOMMENDED_ADAPTER_ARCHITECTURE.md` §7.1.

### 1.5 Derived / regenerable data → **unchanged**

| Data | Home | Keep as-is because |
|---|---|---|
| Bundled recipes | compiled-in | not user data |
| Online recipe results | `OnlineRecipeCacheStore` (memory) | regenerable from the API |
| Substitution suggestions | `SubstitutionCache` | regenerable |
| Online recipe preferences | `UserDefaults` | small, non-relational, correct where it is |
| Device identity | `UserDefaults` | must survive independently of business data |
| Recognition results | **nowhere** | **[Verified]** discarded; §2 |

---

## 2. The one genuine gap in the current design

**[Verified]** Ingredient recognition — YOLO detection, Vision classification,
and the fusion of the two — persists **nothing**. The pipeline runs, the user
confirms items in the review sheet, pantry items are written, and the detection
record itself is discarded.

So the app cannot answer "what did the camera see last Tuesday?", and cannot
measure its own model against user decisions. `DATA_MODEL_AND_RELATIONSHIPS.md`
§2.3-2.4 proposes capturing it in SwiftData. Worth noting that this is the one
place the proposal **adds capability** rather than relocating it — and SwiftData
is the right home precisely because no Firestore collection or security rule
exists for it.

---

## 3. Compatibility guarantees

| Firebase asset | Status under this proposal |
|---|---|
| `FirestorePantryRepository` | **Unmodified.** Still conforms, still selectable |
| `FirestoreInventoryEventRepository` | **Unmodified** |
| `FirestoreSavedRecipeRepository` | **Unmodified**, remains the only implementation |
| `FirestoreDeviceRegistry` | **Untouched** |
| `FirestoreSignalingTransport` | **Untouched** |
| `FirestoreDiagnostics` | **Untouched** |
| `AuthViewModel` | **Untouched** |
| `firestore.rules` | **Not edited, not deployed** |
| `firestore-tests/` emulator suite | **Unchanged and still passing** |
| 3 Firestore mapping test suites | **Unchanged** |
| `GoogleService-Info.plist` | **Unchanged** |
| SPM dependencies | **Unchanged** — no package added or removed |

One exception, stated plainly: if the two protocol methods in
`RECOMMENDED_ADAPTER_ARCHITECTURE.md` §4 are adopted, `FirestorePantryRepository`
gains `fetch(id:)` and `fetchExpiring(before:)` — roughly ten lines, and
`fetch(id:)` makes it *faster* (one `getDocument()` instead of reading the whole
collection). Existing methods are not altered.

---

## 4. Switching adapters does not move data

Stated bluntly because the brief requires it and because it is the easiest thing
to imply by accident during a presentation:

> **Changing `PersistenceConfiguration.backend` changes which store the app
> reads. It copies nothing. A pantry item added in SwiftData mode does not
> appear in Firebase mode, and vice versa.**

Each mode has exactly one source of truth:

| Mode | Source of truth for pantry + events | Scope |
|---|---|---|
| `.swiftData` | local `store.sqlite` | this device |
| `.firebase` | `users/{uid}` in Firestore | this Firebase account, all devices |

### 4.1 Optional one-way import — **[Proposal]**, not recommended for v1

If a populated local store is wanted for the demo, the *safe* direction is a
**one-way, idempotent, explicitly-triggered** import:

```
Firestore ──read──▶ [PantryItem] ──upsert by id──▶ SwiftData
```

It is safe only because of four properties, three of which **[Verified]**
already hold:

1. **Stable shared identity** — both stores key on `PantryItem.id.uuidString`
   (`FirestorePantryRepository.swift:47`), so an upsert by `id` is idempotent
   and re-running it cannot duplicate rows.
2. **Identical field encoding** — the SwiftData schema stores enum `rawValue`
   strings exactly as Firestore does (`DATA_MODEL_AND_RELATIONSHIPS.md` §2.1).
3. **Read-only on the cloud side** — nothing is written to or deleted from
   Firestore, so a failed import cannot damage the user's real data.
4. **User-triggered, never automatic** — a silent background import is how
   duplicate and resurrected rows happen.

**Still not recommended for v1.** It earns no marks and adds a failure mode on
demo day. Adding items by hand in front of the marker is better evidence of
native persistence than a silent import, because the marker watches it happen.

### 4.2 What is explicitly not built

Bidirectional sync, tombstones, conflict resolution, pending-change queues,
delete propagation, last-writer-wins timestamps. All rejected in
`COREDATA_VS_SWIFTDATA_DECISION.md` §6: zero marks, high risk, and the app has
**[Verified]** no real-time requirement in its business data.

---

## 5. Restoring Firebase as the primary backend

### 5.1 The intended route — one line

```swift
// Data/PersistenceConfiguration.swift
private static let compiledDefault: PersistenceBackend = .firebase
```

Rebuild. Every Firestore code path is live again, because it was never removed
and has been **[Verified]** by the contract tests on every CI run
(`IMPLEMENTATION_AND_TEST_PLAN.md` §4).

No data migration is needed: the Firestore documents were never deleted or
modified, so they are exactly as the app last left them.

### 5.2 Full removal of SwiftData, if ever wanted

Still cheap, because the work is additive:

1. Delete `Data/SwiftData/`.
2. Delete `Data/PersistenceConfiguration.swift`; inline Firestore construction
   in `AppDependencies`, or revert `ContentView.init()` to its current form.
3. Restore the `PantryRepositoryKey` default.
4. Remove the SwiftData test files.
5. Optionally revert the two protocol methods — or keep them; they improve the
   Firestore path on their own merits.

Steps 1-4 are deletions. **No Firebase code is resurrected, because none was
ever removed.** This is the property that the dual-adapter design exists to
provide, and it is the direct answer to the brief's reversibility requirement.

### 5.3 Reversibility risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Firebase path rots because nobody runs it | Medium | Contract tests run against **both** backends in CI |
| A new feature is written SwiftData-only | Medium | The protocol is the only API; a feature that needs a new method must add it to every conformance, which fails loudly at compile time |
| `PantryRepositoryKey` default left pointing at the wrong backend | **High if not caught now** | Explicit P1 item; **[Verified]** at `PantryRepositoryEnvironment.swift:20-22` |
| Local data lost on reinstall | Certain, by design | Documented: SwiftData mode is device-local. Not a defect |
| Two accounts share one local pantry | Certain in `.swiftData` mode | `RECOMMENDED_ADAPTER_ARCHITECTURE.md` §7.1 — accept and document, or add `ownerUserID` |

---

## 6. Unresolved questions

1. **Will `firestore.rules` be deployed before the demo?** If yes, saved recipes
   switch on and the Recipes tab gains a section — a behaviour change during
   assessment week, worth sequencing deliberately.
2. **Does the marker expect a cloud feature demonstrated at all?** If the graded
   build defaults to `.swiftData`, the Firebase work is invisible unless the
   presentation explicitly switches modes. The demo script
   (`PRESENTATION_EVIDENCE_PLAN.md` §2, step 8) allows for this.
