# FridgeFit — final production verification

Continues from `docs/assessment4-code-hardening-report.md`. That pass left
two engineering limitations open; this one resolves the first and bounds the
second.

> **Superseded in part by a later pass.** Physical-device verification and
> the privacy/App Store audit were completed afterwards. Where this document
> and the three below disagree, the later ones are current:
>
> - `docs/assessment4-physical-device-verification.md`
> - `docs/assessment4-privacy-compliance-audit.md`
> - `docs/assessment4-app-store-metadata.md`
>
> Net effect: the device checks here marked NOT VERIFIED are now **10 PASS /
> 0 FAIL / 4 NOT VERIFIED**, and two compliance defects found later (a
> missing Local Network permission and undeclared health data sent to
> Spoonacular) have been fixed.

**No Git or GitHub operations were performed** — no commits, branches,
staging, pushes, PRs, or `.git` reads/writes, including read-only commands.

Every figure below corresponds to a command in §5 that was actually run on
this machine. Nothing is inferred, and unexecuted checks are marked
**NOT VERIFIED** rather than passed.

---

## 1. What was open, and where it stands now

| Limitation (previous report) | Status |
|---|---|
| Client-side Firestore deletion is best-effort: no recursive delete, cannot resume after the app dies, nothing stops writes landing mid-deletion | **Resolved in code.** A TypeScript Cloud Functions backend with `recursiveDelete`, a durable idempotent job, a rules-enforced write lock, and an auth-deletion backstop. Fully emulator-tested. **Not deployed** — see §9. |
| App Store Guideline 4.8 (Google without an equivalent privacy-preserving option) | **Out of scope by instruction.** Unchanged and still open — §10. |

---

## 2. Files added and modified

### Added — backend (10)

| File | Purpose |
|---|---|
| `functions/package.json` | Node 20 functions package; build, test and emulator scripts |
| `functions/tsconfig.json` | Strict TypeScript, `noUnusedLocals`, `noImplicitReturns` |
| `functions/src/index.ts` | `requestAccountDeletion`, `accountDeletionStatus`, `onAuthUserDeleted`; auth and recency enforcement |
| `functions/src/deletion.ts` | The workflow: claim, lock, recursive delete, verify, delete account, unlock |
| `functions/src/paths.ts` | The per-user collection map, shared by the workflow and its tests |
| `functions/test/support/harness.mjs` | Emulator-only Auth/Firestore/Functions helpers |
| `functions/test/deletion.e2e.test.mjs` | 27 end-to-end scenarios |
| `functions/test/staleAuth.e2e.test.mjs` | 5 recent-authentication scenarios (separate emulator run) |
| `functions/test/safety.test.mjs` | 11 no-production-access and path-drift guards |
| `tools/device-verification/run-device-checks.sh` | Device checker; reports NOT VERIFIED when it cannot check |

### Added — iOS (5)

| File | Purpose |
|---|---|
| `FridgeFit/Domain/Protocols/AccountDeletionBackend.swift` | `RemoteDeletionState`, `RemoteDeletionOutcome`, backend protocol |
| `FridgeFit/Data/CallableAccountDeletionBackend.swift` | Callable client over URLSession; config flag (off by default) |
| `FridgeFitTests/Account/AccountDeletionBackendTests.swift` | 24 decoding, mapping and TS↔Swift contract tests |
| `FridgeFitTests/Account/BackendDeleteAccountUseCaseTests.swift` | 15 backend-path use-case tests |
| `FridgeFitTests/Integration/AppGraphEndToEndTests.swift` | 10 flows through the real composition root |
| `FridgeFitTests/Device/DeviceReadinessTests.swift` | 14 device checks, skipping as NOT VERIFIED off-hardware |

### Added — docs (2)

`docs/assessment4-device-verification-checklist.md`,
`docs/assessment4-final-production-verification.md` (this file).

### Modified (8)

| File | Change |
|---|---|
| `firestore.rules` | Write lock (`isNotBeingDeleted` / `canWrite`); read/write split; `deletionJobs` + `deletionLocks` read-only to clients |
| `firebase.json` | `functions` codebase; Auth (9599) and Functions (5401) emulators |
| `FridgeFit/Domain/Errors/DeleteAccountError.swift` | `backendUnreachable`, `deletionStatusUnknown` + copy |
| `FridgeFit/UseCases/DeleteAccountUseCase.swift` | Backend path; `error(for:)` outcome mapping |
| `FridgeFit/AppDependencies.swift` | Backend wiring; `makeLocalAccountDataDeleter()` |
| `FridgeFit/Views/Profile/DeleteAccountSheet.swift` | "Check Again" affordance and unknown-state copy |
| `firestore-tests/rules.test.mjs` | +9 write-lock tests (77 → 86) |
| `FridgeFitTests/Integration/AppGraphEndToEndTests.swift` | Two tests made `async` (see §3, bug 3) |

---

## 3. Bugs found and fixed during this pass

All three were found by tests written in this pass, not by inspection.

### 1. The post-deletion sweep resurrected job documents

`onAuthUserDeleted` called `deleteUserData`, which recorded progress via
`updateJob`. `updateJob` writes with `merge: true`, which **creates** the
document when absent — so sweeping an account that never had a job (a
console deletion) wrote a half-filled `deletionJobs/{uid}` for a user who no
longer existed, and left it there permanently.

Caught by `does not corrupt progress when requests overlap`, which saw a
second job document appear after the collection had been cleared.

**Fix:** `deleteUserData(uid, [], { recordProgress: false })` on the sweep
path. `functions/src/deletion.ts`, `functions/src/index.ts`.

### 2. Device detection matched disconnected phones

`grep -E 'available'` also matches **un**available — the script picked a
disconnected iPhone 13 mini and then failed with "device not found".

Compounded by a second defect: `devicectl` reports a CoreDevice UUID that
`xcodebuild` does not accept; it wants the hardware id. The script now asks
`xcodebuild -showdestinations`, the same tool that will run the tests.

**Fix:** `tools/device-verification/run-device-checks.sh`.

### 3. Two new synchronous tests crashed the test host

`test_inSwiftDataMode_theFundsEnvironmentIsLocal` and
`test_settingsDisclosureMatchesTheGraphThatWasBuilt` were synchronous
`@MainActor` tests that built an `AppDependencies` and let it deallocate in
the same frame. Tearing a SwiftData `ModelContainer` down inside that frame
killed the host with `malloc: pointer being freed was not allocated`,
twice per full run.

The suite still reported 0 failures — but `xcodebuild` exited 65 with
`** TEST EXECUTE FAILED **` and
`Restarting after unexpected exit, crash, or test timeout`. A report that
quoted only "0 failures" would have been wrong.

**Fix:** both made `async` with a single `await Task.yield()`. Assertions
unchanged. Full suite now exits 0 with zero restarts.

> This only affects a test-only pattern. In the app `AppDependencies` is
> built once at launch and lives for the process lifetime.

---

## 4. Backend architecture

### 4.1 Workflow

```
requestAccountDeletion  (callable, auth required, recent login required)
  └─ runDeletion(uid)                     uid from the verified token only
       1. claimJob          transactional; idempotent; resumes stale claims
       2. lockUser          deletionLocks/{uid} → rules reject user writes
       3. deleteUserData    recursiveDelete per collection, progress saved
       4. findRemainingData real read; throws if anything survives
       5. deleteAuthUser    Admin SDK — the irreversible step, last
       6. unlockUser + mark completed
```

States: `pending → deletingData → dataDeleted → deletingAuth → completed`,
with `failed` reachable from any step and retryable from all of them.

### 4.2 Why data first, auth last

`firestore.rules` grants `users/{uid}/**` only while
`request.auth.uid == uid`. That constrains the *client*; the Admin SDK
bypasses rules, so the server could delete in either order. It deletes data
first for a different reason: **if the account went first and cleanup then
failed, the user could no longer authenticate to ask for a retry.** The only
thing that could finish would be a backstop running without their
credentials — which exists, but depending on it as the primary path means
routinely orphaning data and hoping a trigger fires.

This satisfies requirement 9 twice: the data is already gone before the
account is touched, and `onAuthUserDeleted` can finish any remainder with no
user credentials at all.

### 4.3 Recovery, and what is *not* claimed

**There is no cross-service atomicity.** Firestore and Firebase
Authentication are separate systems with no shared transaction.

| Failure point | State left behind | Recovery |
|---|---|---|
| Before step 3 | Nothing deleted | Retry; the error says nothing changed |
| During step 3 | Some collections empty; progress recorded | Retry resumes from `deletedCollections` |
| Step 4 finds leftovers | Data partly gone, account alive | Retry; UI warns data has already gone |
| During step 5 | **Data gone, account alive** | Retry deletes the account; `dataDeleted` is explicitly resumable |
| After step 5, before step 6 | Account gone, lock possibly left | `onAuthUserDeleted` sweeps and unlocks |
| Worker dies mid-job | Stale claim | Next request takes over after `STALE_CLAIM_MS` (10 min) |

Not implemented, and stated rather than implied: a **scheduled sweeper** for
jobs abandoned by a user who never returns. Cloud Scheduler requires Blaze,
so it is specified in §9 instead of being half-built.

### 4.4 Write lock

While a job runs, `deletionLocks/{uid}` exists and `firestore.rules` rejects
every user **write** beneath `users/{uid}` (reads still work, so an app left
open renders rather than erroring). Without it, the app could add a pantry
item into a subtree mid-deletion and the item would survive a deletion
reported as complete.

Cost: one `exists()` per user write. Writes here are user-initiated and
infrequent.

### 4.5 Scope: Cloud Storage

**Not included, because the project does not use it.** No `FirebaseStorage`
import exists anywhere; saved-recipe photos are SwiftData
`@Attribute(.externalStorage)`, which is local. Adding a Storage stage would
be dead code implying a dependency that is not there (requirement 7).

---

## 5. Authentication and authorization protections

| Protection | Where | Test |
|---|---|---|
| uid from the verified token only; payload uid ignored | `requireRecentlyAuthenticatedUid` | `ignores a client-supplied uid and deletes only the caller's own account` |
| Unauthenticated rejected | `index.ts` | `rejects an unauthenticated request`, `rejects a garbage bearer token` |
| Recent login required (300s, server-enforced) | `maxAuthAgeSeconds` | `staleAuth.e2e.test.mjs` (5 tests) |
| A rejected request deletes nothing | — | `deletes nothing when it rejects` |
| Status scoped to the caller | `accountDeletionStatus` | `scopes status to the caller` |
| Clients cannot write job or lock | `firestore.rules` | `never lets a client write the lock or the job` |
| Clients cannot read another user's job or lock | `firestore.rules` | `never lets a client read another user's lock or job` |
| Provider-aware reauthentication preserved (client) | `FirebaseAccountAuthenticator` | `googleOnlyAccount_isNeverAskedForAPassword` and 15 others |
| Reauthenticating as a *different* account is refused before anything is sent | `DeleteAccountUseCase` | `reauthenticatingAsADifferentAccount_neverReachesTheBackend` |
| No Admin credentials in the app | — | no service-account file in the repo; verified by `find` |

`auth_time` is used rather than token issuance: a refreshed token does not
reset it, which is the property the check needs.

**Note on the Firebase API key** in `GoogleService-Info.plist`: it is a
public client identifier, not a secret. Security comes from the rules and
from Auth. No private keys are in the repository.

---

## 6. Test results

All figures from the runs in §8.

### Swift — 1832 executed, 1817 passed, 0 failed, 15 skipped

> Updated by the later privacy/permission pass (+12: 8
> `PermissionDeclarationTests`, 4 `StorageDisclosureTests`). The figures in
> the block below were correct when written (1820) and are superseded.

```
Executed 1820 tests, with 15 tests skipped and 0 failures (0 unexpected)
** TEST EXECUTE SUCCEEDED **     exit 0, 0 restarts, 0 crashes
```

Previous baseline 1757 → **+63**, no test removed, skipped, weakened or
disabled.

Skips, all self-declaring:

| Count | Suite | Reason |
|---|---|---|
| 10 | `Device*Tests` | NOT VERIFIED — needs hardware (new this pass) |
| 4 | `HybridRecognitionEvaluationTests` | Evaluation image corpus not in the repo (pre-existing) |
| 1 | `AppleSubstitutionServiceTests` | Model self-reports available on simulator (pre-existing) |

### Firebase emulator — 129 executed, 129 passed, 0 failed, 0 skipped

| Suite | Tests | Result |
|---|---|---|
| Firestore rules (`firestore-tests`) | 86 | pass (was 77, +9 for the write lock) |
| Functions E2E, default window | 27 | pass |
| Functions E2E, stale-auth window | 5 | pass |
| Functions safety / path drift | 11 | pass |

### Coverage of the thirteen required E2E scenarios

| Scenario | Where | Result |
|---|---|---|
| Email/password creation + deletion | `creates, signs in, deletes, and then cannot sign in again` | pass |
| Google provider-aware reauth | `signInWithIdp` emulator strategy; 2 tests | pass |
| Successful complete deletion | 5 tests incl. job state and lock release | pass |
| Repeated deletion requests | 3 tests incl. 3 concurrent calls | pass |
| Network interruption | client-timeout test; status remains authoritative | pass |
| Partial Firestore deletion failure | seeded `deletingData` job with recorded progress | pass |
| Retry and recovery | 5 tests incl. `dataDeleted` → completed | pass |
| Unauthorized attempts | 5 tests incl. spoofed uid | pass |
| Cross-account isolation | 3 accounts incl. a Google one | pass |
| All Funds collections | asserted as exactly five, each emptied | pass |
| Nested collection cleanup | 3 sessions × 2 candidate subcollections | pass |
| Backend unavailable / timeout | dead port + `AbortSignal.timeout` | pass |
| Login attempt after deletion | `EMAIL_NOT_FOUND` asserted | pass |

### Clean build — 0 errors, 0 warnings

```
Compile:  exit 0
error:    0
warning:  0   (swiftc/clang)
```

The only `warning:` line anywhere is
`appintentsmetadataprocessor … No AppIntents.framework dependency found` — a
tool note, not a compiler diagnostic, emitted because the app declares no App
Intents. **No warning was suppressed and no build setting was changed to hide
anything.**

TypeScript compiles clean under `strict` with `noUnusedLocals`.

---

## 7. Physical device checks

A paired **iPhone 15 Pro (iPhone16,1)** was present.

### Verified

| Check | Result | Evidence |
|---|---|---|
| App builds for real iOS hardware | **PASS** | `Debug-iphoneos/FridgeFit.app`, `lipo -archs` → `arm64`, 0 errors |
| App code-signs for device | **PASS** | `CodeSign …/Debug-iphoneos/FridgeFit.app` in the build log |
| CoreML models bundled and compiled | **PASS** | `DevicePackagingTests` (simulator; packaging is device-independent) |
| Detector factory resolves with fallback | **PASS** | `DevicePackagingTests` |
| `NSCameraUsageDescription` present | **PASS** | `DevicePackagingTests` |
| Vision OCR runs without error | **PASS** | `DeviceVisionTests` |

### SUPERSEDED — the device run has since completed

This section originally recorded every device check as NOT VERIFIED because
the phone was locked. **It has since been unlocked and the suite has run on
real hardware.** Full results:
`docs/assessment4-physical-device-verification.md`.

Device: **iPhone 15 Pro (iPhone16,1), iOS 26.6.1, Developer Mode enabled,
wired.** Result: **10 PASS, 0 FAIL, 4 NOT VERIFIED.**

| Check | Result |
|---|---|
| Real Apple Intelligence model availability | **VERIFIED PASS** |
| Receipt interpretation generates real output | **VERIFIED PASS** (8.193 s) |
| Recipe suggestions generate real output | **VERIFIED PASS** (4.450 s) |
| On-device model failure behaviour | **VERIFIED PASS** |
| Camera hardware / authorization | **VERIFIED PASS** |
| Background / foreground transitions | **NOT VERIFIED** (manual) |
| Memory and thermals under sustained detection | **NOT VERIFIED** (Instruments) |
| Offline mode on device | **NOT VERIFIED** (manual) |
| Receipt OCR quality on real paper | **NOT VERIFIED** (manual) |

**No mock-generated AI output is offered as evidence of model quality.** The
two generation tests above assert on real model output from the device and
skip on the simulator. The remaining four need a human; see
`docs/assessment4-device-verification-checklist.md`.

---

## 8. Commands that were run

```bash
# Clean build — exit 0, 0 errors, 0 warnings
xcodebuild -project FridgeFit.xcodeproj -scheme FridgeFit \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO clean build-for-testing

# Swift suite — 1820 executed / 0 failed / 15 skipped, exit 0
xcodebuild … test-without-building

# Firestore rules — 86/86
cd firestore-tests && npm test

# Functions: safety 11/11, E2E 27/27, stale-auth 5/5
cd functions && npm test && npm run test:e2e && npm run test:e2e:stale
cd functions && npm run typecheck

# Device checks — NOT VERIFIED (locked phone)
tools/device-verification/run-device-checks.sh

# Simulator launch — app running, no crash
xcrun simctl install booted …/FridgeFit.app
xcrun simctl launch booted com.Fridge.FridgeFit

# Asset and manifest audit
sips -g pixelWidth -g pixelHeight -g hasAlpha \
  FridgeFit/Assets.xcassets/AppIcon.appiconset/fridgefit_icon.png
plutil -lint FridgeFit/PrivacyInfo.xcprivacy FridgeFit/Info.plist
```

Emulator runs use project id **`demo-fridgefit`**. The `demo-` prefix makes
firebase-tools treat it as offline-only: it refuses to contact Google
servers and needs no credentials. `functions/test/safety.test.mjs` asserts
this as a test. The production project (`fridgefit-app`) was **never**
contacted, read or modified.

---

## 9. Deployment prerequisites, cost, and manual commands

**Nothing below was run.** Deployment requires decisions that are the
maintainer's.

### Prerequisites

1. **Blaze (pay-as-you-go) plan.** Cloud Functions 2nd gen requires it —
   Spark cannot deploy functions at all. This is the blocking prerequisite.
2. APIs enabled (the CLI prompts): Cloud Functions, Cloud Build,
   Artifact Registry, Eventarc, Cloud Run.
3. `firebase login` with deploy rights on `fridgefit-app`.
4. Node 20 locally.

### Cost

Account deletion is rare and the functions are idle otherwise. Free tiers:
2M invocations/month, 400k GB-seconds, 5GB Artifact Registry.

Realistic expectation: **well inside the free tier**, with a small standing
Artifact Registry storage cost for the container images (cents/month).
`maxInstances: 10` caps runaway spend. This is an estimate from the
published free-tier limits, not a measurement — no billing was enabled and
no deploy was performed.

### Manual deployment

```bash
cd functions && npm ci && npm run build

# Rules first: the write lock must exist before the functions rely on it.
firebase deploy --only firestore:rules --project fridgefit-app

firebase deploy --only functions --project fridgefit-app

# Verify, then enable the client:
#   FridgeFit/Data/CallableAccountDeletionBackend.swift
#   AccountDeletionBackendConfiguration.compiledDefault =
#     URL(string: "https://us-central1-fridgefit-app.cloudfunctions.net")
```

### Scheduled sweeper (specified, not implemented)

```ts
export const sweepAbandonedDeletions = onSchedule("every 6 hours", async () => {
  const stale = await getFirestore().collection("deletionJobs")
    .where("state", "in", ["pending", "deletingData", "dataDeleted", "deletingAuth"])
    .where("updatedAt", "<", Timestamp.fromMillis(Date.now() - 36e5))
    .get();
  for (const job of stale.docs) await runDeletion(job.id);
});
```

Needs Cloud Scheduler (Blaze). Until then, recovery is on the next request
plus the `onAuthUserDeleted` backstop — both implemented and tested.

### The shipping app is unaffected

`AccountDeletionBackendConfiguration.compiledDefault` is `nil`, so the app
uses the **on-device deletion path**, which is unchanged and fully tested.
The backend is wired, tested and off. `test_theBackendIsDisabledByDefault`
asserts it, so this cannot drift silently. A `-accountDeletionBackend <url>`
launch argument points a run at the emulator without a rebuild.

---

## 10. Remaining blockers

1. **Guideline 4.8 — open, out of scope by instruction.** Google Sign-In
   with no equivalent privacy-preserving alternative. Needs Sign in with
   Apple, dropping Google, or an exemption.
2. **Functions not deployed** — requires Blaze (§9). Code complete and
   emulator-verified.
3. **Physical device checks NOT VERIFIED** — the phone was locked (§7).
4. **No scheduled sweeper** — needs Cloud Scheduler; two other recovery
   paths are implemented.
5. **No UI test target.** The project has `FridgeFit` and `FridgeFitTests`
   only. UI flows are covered by view-rendering and integration tests plus
   simulator launches in both appearances; no `XCUITest` target was added,
   as that is a project-structure change beyond this task's scope.
6. **Rules deployment state unverified** — whether `firestore.rules` as
   committed is live on `fridgefit-app` cannot be checked from here. The
   write lock **must** be deployed before the functions rely on it.
7. **In `-persistence firebase` mode the local SwiftData store is not
   opened**, so deletion does not clear local rows from a previous SwiftData
   run. `.firebase` needs a launch argument and is not the shipping
   configuration.

---

## 11. Rubric reassessment

Verified and unverified evidence separated. An estimate, not a grade claim.

### App Store Readiness & HIG — 4

**Verified:** compliant deletion with confirmation, provider-aware
reauthentication, honest pending/failed/unknown states, and a server-side
workflow that cannot report success the backend did not confirm; opaque
square icon with pixel-level regression tests; truthful storage/privacy copy
derived from the backend actually built; permission recovery; light and dark
verified by screenshot; app builds **and code-signs for real hardware**.

**Unverified:** on-device model quality; device UI walkthrough.

**Open:** Guideline 4.8 — a genuine, out-of-scope submission blocker.

### Software Architecture, Platform Integration & Persistence — 4

**Verified:** no view constructs persistence; use cases and abstract
repositories throughout, now including `AccountDeletionBackend`;
nine-entity SwiftData with relationships, owner scoping, Decimal-safe money
and restart persistence proven by rebuilding the whole dependency graph over
one file; explicit Firestore integration with 86 emulator-tested rules; a
real TypeScript Cloud Functions backend with a durable job model; CoreML,
Vision, Foundation Models and WebRTC intact.

**Unverified:** production deploy behaviour.

### Automated Testing & Code Quality — 3

**Verified:** 1820 Swift tests and 129 Firebase emulator tests, 0 failures,
0 crashes; +63 Swift and +52 emulator tests this pass with nothing removed or
weakened; adversarial coverage (spoofed uid, cross-account isolation, stale
auth, concurrent requests, partial failure, resumption, dead backend,
contradictory replies); clean build with **0 errors and 0 warnings**; strict
TypeScript. Three real bugs found by these tests — including one that made
`xcodebuild` exit non-zero while the suite reported "0 failures", which a
report quoting only the failure count would have missed.

---

## 12. Evidence index

| Claim | Evidence |
|---|---|
| 1820 Swift tests, 0 failures, exit 0 | `Executed 1820 tests, with 15 tests skipped and 0 failures`, `** TEST EXECUTE SUCCEEDED **` |
| 0 compiler warnings | `grep -c 'warning:'` excluding the AppIntents note → 0 |
| 86 rules tests | `# pass 86 / # fail 0` |
| 27 + 5 + 11 Functions tests | `# pass 27`, `# pass 5`, `# pass 11`, all `# fail 0` |
| No production access | `demo-fridgefit`; asserted by `safety.test.mjs`; emulators on 127.0.0.1 |
| Device build and signing | `Debug-iphoneos/FridgeFit.app`, `lipo -archs` → `arm64`, `CodeSign` in log |
| Device tests not run | `Error Domain=com.apple.dt.deviceprep Code=-3 "Unlock iPhone to Continue"` |
| Icon opaque | `sips` → `hasAlpha: no`, 1024×1024 |
| Manifests valid | `plutil -lint` → OK |
| App launches | `xcrun simctl launch` → pid; process alive after 5s |
| Backend off by default | `test_theBackendIsDisabledByDefault` |
| No Admin credentials in repo | no service-account file found |
