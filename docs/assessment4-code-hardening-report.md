# FridgeFit — Assessment 4 code hardening report

Covers the production-hardening pass over the existing FridgeFit codebase:
what was broken, what was changed, what was verified, and what is still
outstanding. Nothing in this document is inferred — every "verified" claim
below corresponds to a command in [Verification](#verification) that was
actually run on this machine.

**No Git or GitHub operations were performed.** No commits, branches,
staging, pushes, PRs, or `.git` reads/writes.

---

## 1. Scope decision taken during the work

The original brief specified removing Google Sign-In and shipping a
first-party email/password-only system (App Review Guideline 4.8 avoids the
alternative-login requirement when there is no third-party login).

**Mid-task the maintainer changed this: Google Sign-In is kept as-is.** That
decision was taken before any auth code was touched, so no Google code was
removed and none was re-added. It has two consequences, both carried through
the work rather than papered over:

1. Account deletion must be **provider-aware**, because a Google-only account
   has no FridgeFit password to re-confirm with. This is implemented, not
   documented-around (§3.2).
2. Guideline 4.8 now genuinely applies and is **not satisfied**. This is a
   real, open submission risk and is recorded in §6, not hidden.

---

## 2. Confirmed bugs fixed, ranked by severity

Ranked by what the defect does to a user, not by how hard it was to fix.

| # | Severity | Defect | Original cause | Files changed |
|---|---|---|---|---|
| 1 | **Critical** | No way to delete an account. Data was unreachable and undeletable by the user. | Feature absent; Settings offered only a disabled "Clear pantry data" row. | `Domain/Errors/DeleteAccountError.swift`*, `Domain/Protocols/AccountDeletion.swift`*, `UseCases/DeleteAccountUseCase.swift`*, `Data/FirebaseAccountAuthenticator.swift`*, `Data/FirestoreAccountDataDeleter.swift`*, `Data/SwiftData/SwiftDataAccountDataDeleter.swift`*, `Data/LocalStateAccountDataDeleter.swift`*, `ViewModels/DeleteAccountViewModel.swift`*, `Views/Profile/DeleteAccountSheet.swift`*, `Views/Support/AccountDeletionEnvironment.swift`*, `AppDependencies.swift`, `ContentView.swift`, `Views/Profile/ProfileSettingsView.swift` |
| 2 | **Critical** | **Every FridgeFunds write could fail silently.** A refused Firestore write updated the screen and logged a line nobody reads; the user saw a budget/spend/price the backend had rejected. Three separate swallow points: `try?` on user resolution, a log-only completion handler, and no rollback. | `BudgetStore`/`ItemPriceStore`/`PriceBookStore` writes returned `Void`; `FirestoreFundsStores` passed `logIfFailed` as its completion. | `Funds/Repositories/BudgetStore.swift`, `ItemPriceStore.swift`, `PriceBookStore.swift`, `Funds/Repositories/Firestore/FirestoreFundsStores.swift`, `Funds/Repositories/InMemory/InMemoryBudgetStore.swift`, `Funds/Domain/FundsWriteOutcome.swift`*, `Funds/UseCases/RecordGrocerySpendUseCase.swift`, `RecordDiscardedItemCostUseCase.swift`, `Funds/FundsEnvironment.swift`, `ViewModels/ImpactBudgetViewModel.swift`, `Views/Profile/ProfileImpactView.swift`, `Views/Inventory/IngredientDrawerView.swift` |
| 3 | **Critical** | **Every on-device model call could hang forever with no exit.** The substitution service's `withThrowingTaskGroup` timeout did not work: a task group awaits its remaining children when its body returns, and `cancelAll()` only *flags* a child. `LanguageModelSession.respond` on a device reporting `.available` with no model assets never returns, so the group never closed and the timeout error was produced but never delivered. Receipt interpretation and recipe suggestions had no bound at all. | Structured-concurrency race used for an operation that ignores cancellation. | `Data/BoundedWork.swift`* (was `BoundedModelRequest.swift`), `Data/AppleSubstitutionService.swift`, `Data/AppleReceiptIngredientInterpreter.swift`, `Data/AppleRecipeSuggestionService.swift`, `Domain/Errors/ReceiptScanError.swift`, `RecipeSuggestionError.swift` |
| 4 | **High** | App Store icon could not be submitted: 40% fully transparent pixels, every remaining pixel at alpha 254, pre-rounded corners. | Artwork exported as a transparent squircle. | `Assets.xcassets/AppIcon.appiconset/fridgefit_icon.png`, `tools/appicon/make-opaque-icon.swift`* |
| 5 | **High** | **Settings stated a falsehood about the user's data**: "Sync status — Firestore account sync — Private, user-scoped cloud storage", unconditionally, in a build whose pantry is a local database. | Hard-coded copy, uncoupled from `PersistenceBackend`. | `Domain/Models/StorageDisclosure.swift`*, `Views/Profile/ProfileSettingsView.swift`, `Views/Support/AccountDeletionEnvironment.swift`*, `ContentView.swift`, `PrivacyInfo.xcprivacy`, `README.md`, `LoginView.swift` |
| 6 | **High** | `ContentView` built `FundsEnvironment.firestore(...)` unconditionally, so the shipping SwiftData build kept the pantry on device and **the prices of that pantry's contents in the cloud**. The composition root was not consulted. | Backend decision inside a `View`. | `ContentView.swift`, `AppDependencies.swift`, `Funds/FundsEnvironment.swift`, `Data/SwiftData/FundsEntities.swift`*, `Data/SwiftData/SwiftDataFundsStores.swift`*, `Data/SwiftData/PersistenceContainer.swift` |
| 7 | **Medium** | Firebase's raw error text went straight to the sign-in screen, including `userNotFound` — which lets anyone enumerate registered email addresses from the login form. | `errorMessage = error.localizedDescription` on all five auth paths. | `Domain/Errors/AuthErrorMessage.swift`*, `AuthViewModel.swift` |
| 8 | **Medium** | Six Settings rows advertised features that do not exist, each greyed out with a padlock and the word "Unavailable" — the first screenful of Settings was a list of things the app cannot do. | Placeholder UI. | `Views/Profile/ProfileSettingsView.swift` |
| 9 | **Medium** | Account deletion deleted the pantry but **not the five FridgeFunds tables** — found by a test written for this pass, not by inspection. | Omission in the first draft of the local deleter. | `Data/SwiftData/SwiftDataAccountDataDeleter.swift` |
| 10 | **Low** | Google's sign-in button rendered its white "light" card in dark mode. | `scheme: .light` hard-coded. | `LoginView.swift`, `RegisterView.swift` |
| 11 | **Low** | 7 compiler warnings (redundant `await` on same-actor calls). | Test code. | `FridgeFitTests/Online/DiscoverRefreshConcurrencyTests.swift` |
| 12 | **Low** | No client-side email validation; a typo cost a network round trip and a generic banner. | Absent. | `Domain/Models/AuthEmailValidator.swift`*, `LoginView.swift`, `RegisterView.swift` |

`*` = new file.

---

## 3. What was built

### 3.1 Bounded, cancellation-safe model requests (`BoundedWork`)

The fix for #3 is deliberately **unstructured**. The operation runs in a
detached task and reports into a single-assignment box; the caller waits on
the box, not on the operation. Whichever of {finished, deadline, cancelled}
happens first resolves it and the caller resumes immediately. The losing task
is cancelled as a courtesy.

An operation that ignores cancellation therefore keeps running after the call
returns. That cost is accepted on purpose and documented in the type: the
alternative is an indefinite spinner with no way out.

Applied to all three Foundation Models features:

- **Substitutions** — 20s, unchanged bound, working implementation.
- **Recipe ideas** — 20s (new). Fallback: the bundled catalogue and
  `EvaluateRecipeFeasibilityUseCase` involve no model, so Recipes still works.
- **Receipt interpretation** — 20s per batch *and* a 45s whole-receipt budget
  (both new). One scan is up to 7 model requests, so a per-request bound
  alone would permit 140s. A receipt that times out part-way keeps what it
  read (the review screen shows exactly those items and nothing is saved
  without confirmation); a receipt that reads nothing throws `.timeout` with
  manual entry named in the message.

Both services gained an injected generation function so the deadline logic is
testable without an Apple Intelligence device — including the case that
cannot be staged with the real SDK, a generation that never returns and
ignores cancellation.

### 3.2 Account deletion

Order is forced by Firestore's security model, not chosen:

1. **Remote data**, while the auth token is still valid.
2. **Local data** (SwiftData rows, owner-scoped).
3. **On-device caches and preferences.**
4. **The Firebase account.**
5. **Sign out.**

`firestore.rules` grants `users/{uid}/**` only while
`request.auth.uid == uid`. Deleting the account first would strand every
document the user ever wrote: unreachable by them, undeletable by the app.

Every stage is idempotent, so retry-after-partial-failure resumes rather than
repeating. `DeleteAccountError` carries *where* it stopped, and the three
states are given different copy:

- `remoteDataDeletionFailed` — nothing happened; everything is still there.
- `localDataDeletionFailed` — cloud gone, device copy may be partial.
- `accountDeletionFailed` — **data gone, login not**; the sheet says so
  explicitly, because stopping here leaves a working sign-in over an empty
  account.

Success is reported only if `user.delete()` returned cleanly.

**Provider-aware reauthentication.** `currentProviders` reads
`User.providerData`; a password account gets a password field, a Google-only
account is sent back through Google and is **never shown a password field**.
An unrecognised provider maps to `.other` and stops with
`noSupportedReauthenticationMethod` rather than guessing.

**Owner scoping.** Every local query is predicated on `ownerID`. That
predicate is the entire safety boundary on a device where two accounts have
signed in, so it is tested by asserting on the *other* account's rows.

**Nested subcollections.** Deleting a Firestore document does **not** delete
its subcollections. `webrtcSessions/{id}` owns `callerCandidates` and
`calleeCandidates`; each session's candidates are deleted *before* the
session document, or every ICE candidate would be orphaned at a path whose
parent is gone. A test parses `firestore.rules` and fails if any
`users/{uid}/<collection>` path is not covered by the deleter.

### 3.3 Funds persistence and write propagation

`FundsWriteOutcome` has three results, not two:

- `.committed` — authoritative store has it.
- `.pendingSync` — Firestore's **durable offline queue** has it; applied
  locally, not yet server-acknowledged.
- thrown error — not saved anywhere, and the local copy is rolled back.

The third state exists because `setData`'s completion fires on *server*
acknowledgement. Offline, Firestore persists the write and delivers it later,
which may be much later — so awaiting it unbounded would hang Save for the
entire time a device is off the network. The wait is bounded (5s) via
`BoundedWork`; past the bound the write is still safely queued and the UI says
"Saved on this device. It'll sync when you're back online." This is the
explicit "do not equate network dispatch with a server-acknowledged write"
requirement.

New SwiftData funds stores (`FoodBudgetEntity`, `GrocerySpendEntity`,
`WastedFoodCostEntity`, `ItemPriceEntity`, `PriceBookEntryEntity`) put the
money beside the pantry it values, in the same container, under the same
`ownerID`. **Money is stored as decimal text**, matching the existing
Firestore decision — a `Double` round trip turns 4.50 into 4.4999…, and once
in the database it is permanent. `FundsDecimal` is POSIX on both sides, so a
device set to a comma locale cannot write a price the next launch drops.

### 3.4 App icon

`tools/appicon/make-opaque-icon.swift` fills the canvas with the brand canvas
colour (`#F7F5EC`), draws the artwork at 1.02× so it reaches the edges, and
writes a PNG with **no alpha channel** (`.noneSkipLast`). It verifies before
overwriting and refuses to write a non-square, non-opaque, or
faded-corner result.

An earlier attempt at 1.34× overscan (to push the source's rounded corners
off-canvas) clipped the bolt badge and the fridge; that was rejected rather
than shipped, and the reason is recorded in the tool.

Result, measured: `hasAlpha: no`, 0 transparent pixels, 0 partial-alpha
pixels, opaque bounding box 0…1023 in both axes.

---

## 4. File-level architecture summary

| Area | Before | After |
|---|---|---|
| Pantry / events / saved recipes | SwiftData, owner-scoped | unchanged |
| **Budget / spends / waste / prices / price book** | **Firestore, always, chosen inside `ContentView`** | **Backend-selected by `AppDependencies`: SwiftData in the shipping build, Firestore in `-persistence firebase`** |
| Funds writes | sync, `Void`, log-only failure, no rollback | `async throws -> FundsWriteOutcome`, rollback on failure, pending-sync state surfaced |
| Auth | Firebase, email + Google | unchanged providers; errors mapped, email validated, **account deletion added** |
| Model requests | unbounded (2 of 3), broken bound (1 of 3) | all three bounded, cancellation-safe, with fallbacks |
| Settings storage claim | hard-coded "Firestore account sync" | derived from `PersistenceBackend` via `StorageDisclosure` |
| App icon | 1024², 40% transparent, pre-rounded | 1024², fully opaque, full-bleed |

### Schema migration and data protection

Five `@Model` types were added to `PersistenceContainer.schema`. **Adding
model types is a SwiftData lightweight migration**: new tables are created,
existing rows are not rewritten, and a store written by an earlier build
opens unchanged. No existing pantry is migrated or at risk.

Previously saved **cloud** budgets and prices are *not* discarded — the
Firestore stores and their mapping remain, fully tested, and are selected by
`-persistence firebase`. What changed is which one the shipping build reads.
Switching backends copies nothing; that was already documented in
`PersistenceConfiguration` and remains true.

### Security / privacy decisions

- `firestore.rules` **not broadened**. Deletion runs entirely as the
  signed-in user under the existing rules. No Admin SDK, no service account,
  no credentials in the app.
- Sign-in no longer distinguishes "no such account" from "wrong password".
- Three on-device caches (substitution, receipt, online-recipe) are deleted
  on account deletion — they are derived data but contain pantry contents in
  plain text.
- `DeviceIdentity` keys are deliberately **kept**: they identify the install,
  not a user, and the account's cloud device entry is deleted separately.
- `PrivacyInfo.xcprivacy` rewritten to state what the shipping configuration
  actually does, and to record the five `UserDefaults` uses (was three).
- `PhotosPicker` is out-of-process and grants no library access, so **no
  `NSPhotoLibraryUsageDescription` is required** and none was added.

---

## 5. Verification

Environment: **Xcode 26.1 (17B55)**, Swift 6.2.1, iOS 26.1 simulator SDK,
**iPhone 17 Pro simulator**, Node v20.20.2, firebase-tools 15.17.0.

### Clean build — 0 errors, 0 warnings

```
xcodebuild -project FridgeFit.xcodeproj -scheme FridgeFit \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO clean build-for-testing
```

Result: **exit 0, 0 `error:`, 0 `warning:`** from swiftc/clang.

The only line matching `warning:` anywhere in the log is
`appintentsmetadataprocessor … Metadata extraction skipped. No
AppIntents.framework dependency found.` — a tool note emitted because the app
declares no App Intents. It is not a compiler diagnostic and is not
suppressible from source. **No warnings were disabled and no build setting was
changed to hide anything.** Baseline before this work: 7 warnings.

### Unit tests — 1757 run, 0 failed, 5 skipped

```
xcodebuild … test-without-building
```

Result: **`Executed 1757 tests, with 5 tests skipped and 0 failures`**
(57.1s). Baseline before this work: 1679 tests. **+78 tests, no existing test
removed, deleted, or weakened.**

The 5 skips are pre-existing and self-declaring:

| Skipped test | Reason |
|---|---|
| `AppleSubstitutionServiceTests.test_suggestSubstitutions_whenModelUnavailable_…` | Skips where the model reports itself available — including the simulator, which reports `.available` with no assets. |
| `HybridRecognitionEvaluationTests` ×4 | Need the evaluation image corpus, which is not in the repository. |

### Firestore security rules — 77 run, 0 failed

```
cd firestore-tests && npm ci && npm test
```

Runs `firebase emulators:exec --only firestore` against the **local
emulator** on 127.0.0.1:8575. Result: **`# pass 77`, `# fail 0`**. No
production Firebase project was contacted, read, or modified at any point.

### Simulator run

App installed and launched on the iPhone 17 Pro simulator
(`com.Fridge.FridgeFit`); login screen rendered and screenshotted in **both
dark and light appearance**, confirming legibility of both and the Google
button's new scheme-aware rendering.

### Asset and manifest re-checks

- `sips`: icon is `1024×1024`, `hasAlpha: no`.
- Pixel scan: 0 transparent, 0 partial-alpha, bbox 0…1023.
- `plutil -lint`: `PrivacyInfo.xcprivacy`, `Info.plist`,
  `GoogleService-Info.plist` all **OK**.

### What was NOT verified

Stated plainly rather than implied:

- **No physical device was used.** Every Apple Intelligence claim in this
  document is about FridgeFit's *bounding and fallback* behaviour, driven
  through injected fakes. No assertion is made that the model produces good
  output on real hardware, because that was not tested here.
- **The live Firebase project was not touched.** Rules deployment state,
  the Google provider configuration, and real account behaviour are
  unverified from this machine by design.
- **The signed-in app flows were not exercised end-to-end**, because that
  needs real credentials against the live project. Everything below the UI is
  covered by the unit suite; the screens themselves were verified by the
  existing rendering tests plus the two launch screenshots.
- **Account deletion was not run against live data.** Its logic is covered by
  23 tests over fakes and a real in-memory SwiftData container.

---

## 6. Remaining risks and blockers

1. **App Review Guideline 4.8 — open, and the most likely rejection reason.**
   The app offers Google Sign-In (a third-party login) with no equivalent
   privacy-preserving alternative. Sign in with Apple was explicitly ruled
   out for this pass. Resolving it needs one of: add Sign in with Apple, drop
   Google, or qualify for an exemption. **Not fixable in code without one of
   those decisions.**

2. **Client-side recursive Firestore deletion is best-effort.** It runs as
   the signed-in user under existing rules, in batches, children before
   parents. If the app is killed or loses the network mid-deletion, documents
   remain and the next attempt finishes them. What it cannot offer is
   atomicity, or completion after the account is gone.

   **Backend integration contract** (not implemented — this repository has no
   backend, and a stub pretending to call one would be worse than the honest
   client loop):

   - Callable Cloud Function `deleteUserData`, authenticated, deriving the
     uid from `context.auth.uid` and **never** from a client argument.
   - Admin SDK `firestore.recursiveDelete(db.doc('users/' + uid))`.
   - Client calls it *before* `user.delete()`; on success, skip the local
     recursive loop; on failure, fall back to it.
   - Also register an `auth.user().onDelete` trigger as a backstop for
     accounts deleted from the Firebase console.
   - The Admin SDK must never ship inside the app — its credentials bypass
     all rules.

3. **Existing Google-only accounts.** They can sign in, use the app, and now
   delete themselves (via Google reauthentication). They have **no FridgeFit
   password**. If Google is ever removed, these accounts need an explicitly
   planned provider migration (send a password-reset link to the Google
   email, which sets a password on the existing Firebase user) or support
   intervention. **They cannot simply "use a password" — they do not have
   one**, and nothing in this codebase pretends otherwise.

4. **Firebase project configuration is unverified from here.** Specifically:
   whether `firestore.rules` as committed is actually deployed, and whether
   the `savedRecipes` rule is live (`OnlineRecipeFeature` gates saving on
   this). Verify in the console before release.

5. **On-device Apple Intelligence is unvalidated on real hardware.** The
   simulator reports `.available` with no model assets, so no simulator run
   proves anything about generation quality. The deadlines mean a device that
   cannot generate degrades to an explained, retryable state rather than
   hanging — that part *is* tested.

6. **`LocalStateAccountDataDeleter` is device-scoped, not account-scoped.**
   `UserDefaults` keys and cache files carry no owner. On a device where two
   accounts have been used, deleting one resets these *preferences* for the
   device. Genuine account data (pantry, events, recipes, budgets, prices)
   **is** owner-scoped and is left strictly alone. The trade is documented in
   the type: resetting a measurement preference is better than retaining a
   cache of the deleted account's groceries.

7. **In `-persistence firebase` mode the local SwiftData store is not
   opened**, so account deletion does not clear local rows left by a previous
   SwiftData run. `.firebase` requires a launch argument and is not the
   shipping configuration.

8. **An uncancellable model request leaks its task.** By design (§3.1). It
   holds whatever the model holds until the process ends. The alternative was
   an indefinite spinner.

---

## 7. Rubric-oriented estimate (11 code marks)

Offered as an estimate, with verified and unverified evidence separated. It
is not a grade claim.

### App Store Readiness & HIG — 4 marks

**Verified:** compliant account deletion with confirmation, provider-aware
reauthentication, partial-failure recovery and 23 tests; opaque square
non-rounded icon with a pixel-level regression test; truthful storage and
privacy copy derived from the backend; six fake settings rows removed;
light/dark verified by screenshot; auth errors mapped and made
non-enumerating; recoverable timeout/fallback states on all three AI
features.

**Unverified:** no device run; no end-to-end signed-in walkthrough.

**Open:** Guideline 4.8 (§6.1) — a genuine, unresolved submission blocker.

### Architecture, Platform Integration & Persistence — 4 marks

**Verified:** no view constructs persistence (the last offender,
`ContentView`'s `FundsEnvironment.firestore`, is fixed); use cases and
abstract repositories throughout; multi-entity SwiftData across **nine**
`@Model` types with relationships, owner scoping, Decimal-safe money and
restart persistence proven by a container-rebuild test; explicit Firestore
integration with 77 emulator-tested rules; CoreML/Vision/Foundation Models
and WebRTC all intact.

**Unverified:** on-device Apple Intelligence quality.

### Testing & Code Quality — 3 marks

**Verified:** 1757 tests, 0 failures, far beyond the five-test minimum;
+78 added this pass, all with mock repositories or injected fakes; heavy
negative/edge/regression coverage (storage refusal, offline queue, retry
without duplication, owner scoping, reauthentication mismatch, uncancellable
timeouts, corrupt rows, signed-out writes); clean build with **0 errors and 0
warnings**; no test weakened or removed. One real bug (#9) was found by a
test written during this pass.

---

## 8. Reproducing

```bash
# Build (0 errors, 0 warnings)
xcodebuild -project FridgeFit.xcodeproj -scheme FridgeFit \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO clean build-for-testing

# Unit tests (1757 / 0 failed / 5 skipped)
xcodebuild -project FridgeFit.xcodeproj -scheme FridgeFit \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO test-without-building

# Firestore rules, local emulator only (77 / 0 failed)
cd firestore-tests && npm ci && npm test

# Regenerate + verify the app icon
swift tools/appicon/make-opaque-icon.swift \
  FridgeFit/Assets.xcassets/AppIcon.appiconset/fridgefit_icon.png

# Icon properties
sips -g pixelWidth -g pixelHeight -g hasAlpha \
  FridgeFit/Assets.xcassets/AppIcon.appiconset/fridgefit_icon.png

# Manifest validity
plutil -lint FridgeFit/PrivacyInfo.xcprivacy FridgeFit/Info.plist
```
