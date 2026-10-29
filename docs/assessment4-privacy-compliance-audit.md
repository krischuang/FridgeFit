# FridgeFit — privacy and permission compliance audit

Traced from code and from an actual Release archive, not from comments.
Every path below was read in the current source; where a comment and the code
disagreed, the code won (and the comment was fixed — §6).

**No Git or GitHub operations were performed.**

Markers: **VERIFIED PASS** · **VERIFIED FAIL** · **NOT VERIFIED** ·
**EXTERNAL REQUIREMENT**

---

## 1. Data flow inventory

"Leaves device" means the bytes reach a server. "Linked" means Apple's
definition: tied to the user's identity.

| # | Data | Leaves device? | Recipient | Purpose | Linked | Retained | Deletion route |
|---|---|---|---|---|---|---|---|
| 1 | Email address, uid | **Yes** | Firebase Auth (Google) | Identify the account | **Yes** | Until deletion | Delete Account |
| 2 | Google profile (name, email, Google id) | **Yes** | Google | Federated sign-in | **Yes** | Google's own terms | Delete Account + Google account settings |
| 3 | Pantry, activity log, saved recipes | **No** (SwiftData) | — | The app | n/a | On device | Delete Account; app delete |
| 4 | Budget, spends, waste, prices, price book | **No** (SwiftData) | — | The app | n/a | On device | Delete Account; app delete |
| 5 | Same as 3 and 4 in `-persistence firebase` | **Yes** | Firestore `users/{uid}` | The app | **Yes** | Until deletion | Delete Account |
| 6 | Remote-camera device entry | **Yes** | Firestore `users/{uid}/devices` | Tell two iPhones apart | **Yes** | Until deletion | Delete Account |
| 7 | WebRTC SDP + ICE candidates | **Yes** | Firestore `users/{uid}/webrtcSessions` | Connection setup | **Yes** | Until deletion | Delete Account |
| 8 | Camera **video** in Camera Mode | **Peer-to-peer only** | The user's other iPhone | Live view | n/a | Not stored | n/a (never persisted) |
| 9 | Fridge and receipt **photos** | **No** | — | Vision + CoreML + Foundation Models, on device | n/a | Not persisted | n/a |
| 10 | Receipt **text** | **No** | — | Foundation Models, on device | n/a | Derived cache only | Delete Account clears the cache |
| 11 | **Pantry ingredient names** (Discover search) | **Yes, when a key is set** | **Spoonacular** | Recipe search | **No** | **EXTERNAL REQUIREMENT** | Not applicable (no identifier sent) |
| 12 | **Food intolerances** (the Avoid list) | **Yes, when a key is set** | **Spoonacular** | Narrow the search | **No** | **EXTERNAL REQUIREMENT** | as above |
| 13 | Diet filter, max ready time | **Yes, when a key is set** | Spoonacular | Narrow the search | **No** | **EXTERNAL REQUIREMENT** | as above |
| 14 | Recipe thumbnails | **Yes** (fetch) | Spoonacular CDN | Display | **No** | Cached locally | Delete Account clears the cache |
| 15 | Profile prefs, Discover filters, hidden recipes | **No** | — | UI state | n/a | `UserDefaults` | Delete Account |
| 16 | Device id, preferred role | **No** | — | Identify this install | **No** | `UserDefaults` | Deliberately kept — §4 |
| 17 | Crash/diagnostic | **Not by FridgeFit** | — | — | — | — | — |

### 1.1 The finding that mattered: items 11–13

`SpoonacularRecipeService` builds the query with `includeIngredients` (the
pantry names), `intolerances`, `diet` and `maxReadyTime`, and sends it to
`api.spoonacular.com`.

- **Food intolerances are user-provided health information.** The twelve
  values are dairy, egg, gluten, grain, peanut, seafood, sesame, shellfish,
  soy, sulfite, tree nut, wheat. For a user with coeliac disease or a nut
  allergy this is a medical fact about them.
- **It was not declared** in `PrivacyInfo.xcprivacy` → **VERIFIED FAIL**,
  now fixed (§6.2).
- **It is not linked**: the request carries no uid, email, account or device
  identifier, only the developer's API key. So "Collected, Not Linked".
- **Gated by the key.** `OnlineRecipeFeature.provider` is `.enabled`, but
  `SpoonacularConfiguration` returns `nil` without a key and Discover shows
  its unavailable state and performs no networking. A fresh checkout has no
  `Secrets.xcconfig`, so **in this repository state nothing is transmitted**.
  A shipping build with a key does transmit. Declared on that basis.

---

## 2. Permission audit

| Permission | Used? | Declared? | Verdict |
|---|---|---|---|
| Camera | Yes — `AVCaptureDevice.requestAccess(for: .video)` | Yes | **VERIFIED PASS** |
| **Local Network** | **Yes** — WebRTC host (LAN) candidates | **Was missing** | **VERIFIED FAIL → fixed** (§6.1) |
| Microphone | **No** — `isAudioEnabled = false`, no audio track | No | **VERIFIED PASS** (correctly absent) |
| Photo Library | **No** — `PhotosPicker` is out-of-process | No | **VERIFIED PASS** (correctly absent) |
| Notifications | **No** — no `UNUserNotificationCenter` anywhere | No | **VERIFIED PASS** (correctly absent) |
| Location | **No** in FridgeFit's code | No | **VERIFIED PASS** — but see §3.1 |
| Contacts / Calendar / Health / Motion / Tracking | No | No | **VERIFIED PASS** |
| Bonjour (`NSBonjourServices`) | **No** — rendezvous is via Firestore, not mDNS | No | **VERIFIED PASS** (correctly absent) |

### 2.1 Local Network — the real gap

WebRTC gathers **host ICE candidates** (this device's LAN addresses), and
`WebRTCConfiguration` documents same-Wi-Fi as the primary path:
"Same Wi-Fi: works, usually on a host (LAN) candidate". Connecting two
iPhones on one network therefore sends UDP directly to e.g. 192.168.x.x,
which on iOS 14+ requires `NSLocalNetworkUsageDescription`.

Without it iOS shows the prompt with **no explanation**, and App Review flags
the omission. Added in §6.1.

**NOT VERIFIED:** observing the prompt itself needs **two** iPhones on one
Wi-Fi. One device was available. The requirement is established from the code
path, not from seeing the dialog.

### 2.2 Denied permissions behave safely — VERIFIED PASS

`CameraPicker.request()` handles `.authorized`, `.notDetermined`, `.denied`,
`.restricted` and `@unknown default`; a refusal routes to
`CameraAccessPrompt`, which explains the state and offers
`UIApplication.openSettingsURLString`. Covered by `PermissionRecoveryTests`
and the new `PermissionDeclarationTests`.

Minor observation, not a defect: `.restricted` (Screen Time / MDM) is folded
into `.denied`, so the prompt offers Settings. A genuinely restricted device
may not be changeable there, but the state is still explained rather than
presenting a black viewfinder.

---

## 3. Third-party SDK disclosure, from the archive

Taken from a real `xcodebuild archive` (Release, iphoneos) containing **30
privacy manifests** — the app plus 29 SDK bundles. This is the input to
Xcode's Privacy Report.

| Data type | Declared by |
|---|---|
| Email address | **FridgeFit**, GoogleSignIn |
| Health | **FridgeFit** (new) |
| Search history | **FridgeFit** (new) |
| Other user content | **FridgeFit** |
| User ID | FirebaseAuth, GoogleSignIn |
| **Coarse location** | **GoogleSignIn** |
| **Device ID** | **GoogleSignIn** |
| **Phone number** | **GoogleSignIn** |
| **Name** | **GoogleSignIn** |
| Other usage / other data | GoogleSignIn |
| Other diagnostic data | FirebaseAuth, FirebaseFirestore |

**Tracking: none.** `NSPrivacyTracking` is `false` in every manifest,
including all SDKs → "Data Used to Track You: None".

### 3.1 GoogleSignIn declares more than FridgeFit asks for

FridgeFit requests **no additional scopes** — `GIDConfiguration(clientID:)`
and a bare `signIn(withPresenting:)`, i.e. default email/profile. But the SDK
*declares* coarse location, device ID and phone number, and Apple's nutrition
labels must reflect what bundled SDKs collect.

**Consequence:** the App Store privacy labels must include these, even though
FridgeFit never reads them. They are carried in
`docs/assessment4-app-store-metadata.md`. **EXTERNAL REQUIREMENT:** confirm
against GoogleSignIn 7.1.0's published documentation at submission time.

### 3.2 Required-reason APIs — VERIFIED PASS

All declared. FridgeFit itself declares only `UserDefaults` (CA92.1), which
matches its five uses. File-timestamp and boot-time reasons come from WebRTC,
gRPC, leveldb and GoogleUtilities, each declaring its own.

---

## 4. Deletion routes — VERIFIED PASS

| Data | Removed by |
|---|---|
| Firestore `users/{uid}/**` | `FirestoreAccountDataDeleter` (client, deployed path) |
| SwiftData rows (9 entities) | `SwiftDataAccountDataDeleter`, owner-scoped |
| Derived caches (substitution, receipt, online recipe) | `LocalStateAccountDataDeleter` |
| `UserDefaults` prefs | `LocalStateAccountDataDeleter` |
| Firebase Auth account | `FirebaseAccountAuthenticator`, provider-aware |

Deliberately kept: `DeviceIdentity`'s `deviceId` and `preferredRole`. They
identify the *install*, not a person, and the account's cloud device entry is
deleted separately. Minting a new id would make one install look like two.

`UIDevice.current.name` is used for the device label. On iOS 16+ this returns
the **model name** ("iPhone") unless the app holds the user-assigned-name
entitlement. No `.entitlements` file exists, so no personal device name is
transmitted — **VERIFIED PASS**.

Server-side deletion exists in `functions/` and is emulator-tested, but is
**NOT DEPLOYED**. It must not be described as a production feature.

---

## 5. Consent and additional disclosure

| Question | Answer |
|---|---|
| Any tracking or ATT prompt needed? | **No.** No IDFA, no ad SDK, no cross-app linkage. |
| Consent needed for on-device AI? | **No.** Nothing leaves the device. |
| Consent for camera / local network? | Covered by the system prompts, now both with accurate strings. |
| **Disclosure for sending intolerances to a third party?** | **Yes — was inadequate.** Fixed in §6.3 and §6.4. |
| Privacy policy required? | **Yes — EXTERNAL REQUIREMENT.** None exists. §7. |

---

## 6. Fixes applied

### 6.1 `NSLocalNetworkUsageDescription` added — `FridgeFit/Info.plist`

Explains Camera Mode and states video is never uploaded. `NSBonjourServices`
deliberately **not** added: the app browses no service.

### 6.2 Privacy manifest — `FridgeFit/PrivacyInfo.xcprivacy`

Added `NSPrivacyCollectedDataTypeHealth` (intolerances) and
`NSPrivacyCollectedDataTypeSearchHistory` (ingredient names, time limit),
both **not linked**, **not tracking**, App Functionality. Verified present in
the archived bundle.

### 6.3 Settings now discloses the third party

`StorageDisclosure` gained `DataLocation.thirdParty(name:)` and a "Discover
recipe searches" row naming Spoonacular and the Avoid list. A screen headed
*where your data lives* that omitted the only external recipient was
inaccurate by omission. The row is omitted when the provider is off, so it
never describes a transfer that cannot occur.

### 6.4 Discover preferences copy

The Avoid footer said "The screen reads ingredient names only", which reads
as on-device-only handling. It now adds: *"This list is also sent to the
recipe service to narrow the search; it isn't linked to your account."* The
Diet section already said this; the intolerance section did not.

### 6.5 Stale configuration documentation

`Secrets.xcconfig.example` claimed Spoonacular was "NOT YET ACTIVE" and
"switched OFF in code", and told the reader to flip `provider` to `.enabled`
— which it already is. Rewritten to state what is actually transmitted when a
key is supplied.

### 6.6 Regression tests added

`PermissionDeclarationTests` (8) pins the permission set in **both**
directions — a missing string and an unnecessary one both fail.
`StorageDisclosureTests` gained 4 for the third-party row.

---

## 7. Open items

| Item | Status | Owner |
|---|---|---|
| Privacy policy URL | **EXTERNAL REQUIREMENT** — none exists; App Store requires one. No URL invented. | Maintainer |
| Support URL | **EXTERNAL REQUIREMENT** — none exists | Maintainer |
| Spoonacular retention and sub-processors | **EXTERNAL REQUIREMENT** — outside FridgeFit's control | Maintainer |
| GoogleSignIn declared collection | **EXTERNAL REQUIREMENT** — confirm at submission | Maintainer |
| Local Network prompt observed | **NOT VERIFIED** — needs two iPhones | — |
| Guideline 4.8 | **Acknowledged open blocker**, out of scope by instruction | Maintainer |
| Cloud Functions deletion | Implemented, emulator-tested, **not deployed** | Maintainer |

---

## 8. Evidence

| Claim | Evidence |
|---|---|
| Intolerances transmitted | `SpoonacularRecipeService.swift` line ~93, `intolerances` query item |
| No audio captured | `WebRTCFactory.swift`: `useManualAudio = true`, `isAudioEnabled = false` |
| Host candidates gathered | `WebRTCClient.swift` candidate gathering; `WebRTCConfiguration` doc |
| Archive manifests | 30 `PrivacyInfo.xcprivacy` in `FridgeFit.xcarchive` |
| No tracking | `NSPrivacyTracking` false in all 30 |
| Manifest valid | `plutil -lint` → OK |
| Permission set pinned | `PermissionDeclarationTests` 8/8 pass |
| Disclosure correctness | `StorageDisclosureTests` 15/15 pass |
| No secrets committed | no `Secrets.xcconfig`; no service-account file; the `AIza…` key in `GoogleService-Info.plist` is a public client identifier, not a credential |
