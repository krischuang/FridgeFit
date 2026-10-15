# Remote Camera (WebRTC) — Testing Report

A second iPhone, signed into the same Firebase account, acting as a remote
fridge camera: live video to the phone in your hand, a remote shutter, and
the captured photo delivered back to the main app.

- **Implemented:** 11 October 2026
- **Firestore rules deployed:** 12 October 2026 (see §4)
- **Toolchain:** Xcode 26.1 (17B55), Swift 6.2.1, iOS SDK 26.1
- **Deployment target:** iOS 26.0 (unchanged)
- **Firebase project:** `fridgefit-app`
- **WebRTC:** [`stasel/WebRTC`](https://github.com/stasel/WebRTC) 154.0.0 (M154), Swift Package Manager

---

## 1. Test results at a glance

| # | Test | Result | How it was verified |
|---|------|--------|---------------------|
| A | Build verification | **PASS** | Simulator + device, Debug + Release, all green. Zero warnings from new code. |
| B | Device registration | **PASS** | 19 automated tests. Two device IDs under one account, presence/staleness. |
| C | Session signaling | **PASS** | 44 automated tests. Offer/answer, ICE, state machine, cleanup. |
| D | DataChannel protocol | **PASS** | 24 automated tests, plus 2 over a real SCTP channel. |
| E | Image transfer | **PASS** | 24 automated tests, plus a real JPEG over a real data channel. |
| — | **Real WebRTC loopback** | **PASS** | 9 tests driving two genuine `RTCPeerConnection`s, including decoded video. |
| — | Screen mounting | **PASS** | 5 tests. Each screen hosted in a real window, lifecycle run. |
| — | **Firestore security rules** | **PASS** | 42 emulator tests against the deployed file (§4a). |
| — | Error diagnostics | **PASS** | 26 automated tests (§4b). |
| — | **Rules deployment** | **DEPLOYED & VERIFIED** | Live ruleset re-fetched and replayed; all operations allowed, cross-account denied. |
| F | Two physical iPhones | **NOT TESTED** | No devices available. Manual steps in §6. |
| G | Cross-network (Wi-Fi ↔ cellular) | **NOT TESTED** | Needs two devices on separate networks. Scenario in §7. |

**427 Swift tests + 42 rules tests, 0 failures.** 240 of the Swift tests are
the pre-existing suite — unchanged and still passing.

> Tests F and G are **not** claimed as passing. No physical iPhone has been
> connected at any point (`xcrun devicectl list devices` reports the only
> paired iPhone as `unavailable`), so no claim is made about NAT traversal,
> real radio links, or real camera hardware. **Device discovery between two
> real iPhones has therefore not been observed end to end** — the rules that
> blocked it are deployed and verified, but the on-device run remains to be
> done by someone with two handsets (§5).

---

## 2. What was actually executed

### Test A — Build verification

```
xcodebuild -scheme FridgeFit -destination 'generic/platform=iOS Simulator' -configuration Debug build
** BUILD SUCCEEDED **

xcodebuild -scheme FridgeFit -destination 'generic/platform=iOS' -configuration Debug  CODE_SIGNING_ALLOWED=NO build
** BUILD SUCCEEDED **

xcodebuild -scheme FridgeFit -destination 'generic/platform=iOS' -configuration Release CODE_SIGNING_ALLOWED=NO build
** BUILD SUCCEEDED **
```

The device build links `WebRTC.xcframework/ios-arm64`; the simulator build
links `ios-x86_64_arm64-simulator`. Both slices ship in the package, so the
same code runs in the Simulator and on hardware.

The app was installed and launched on the iOS 26.1 Simulator and stayed
running; the Pantry tab rendered its normal empty state, confirming existing
functionality is intact.

**Warnings.** Zero from the new code, in both configurations. Six warnings
remain in the project, all pre-existing and all in files this work never
touched (`VisionReceiptTextRecognizer`, `ReceiptItemDraft`,
`IngredientCanonicalizer`, `PantryViewModel`, `RecipeViewModel`). They were
present before this work and are left alone.

### Tests B–E and the loopback suite

```
xcodebuild -scheme FridgeFit -destination 'platform=iOS Simulator,id=…' test
Executed 427 tests, with 0 failures (0 unexpected) in 14.382 seconds
** TEST SUCCEEDED **

cd firestore-tests && npm test
# tests 42 / pass 42 / fail 0
```

| Suite | Tests | Covers |
|---|---:|---|
| `DeviceRegistrationTests` | 19 | Test B — two device IDs on one account, cross-account isolation, presence window, role switching, field mapping |
| `WebRTCSessionCoordinatorTests` | 44 | Test C — offer/answer ordering, ICE exchange and queueing, state machine, cleanup, expiry, self-connection refusal, ICE failure, media watchdog |
| `RemoteControlMessageTests` | 24 | Test D — every message round-trips; malformed, oversized and unknown frames handled |
| `ImageTransferTests` | 24 | Test E — chunking, framing, reassembly (out-of-order, duplicate, corrupt), encode/decode |
| `RemoteCameraViewModelTests` | 17 | Controller screen end to end: discover → connect → capture → display |
| `WebRTCConfigurationTests` | 19 | STUN/TURN loading, credential redaction, error messages |
| `WebRTCLoopbackTests` | 9 | **Real WebRTC**, both ends in-process |
| `RemoteCameraViewMountingTests` | 5 | Each screen mounted in a real `UIWindow` with its lifecycle run |
| `FirestoreDiagnosticsTests` | 26 | Error code classification, context capture, uid redaction, user-facing mapping, signed-out paths |
| *(pre-existing suites)* | 240 | Pantry, recipes, receipt scanning, substitutions — unchanged |
| `firestore-tests/rules.test.mjs` | 42 | Security rules, against the emulator — separate runner, see §4a |

### The loopback suite is the important one

Mock-based tests prove the logic *around* WebRTC. They say nothing about
whether the SDK integration works. `WebRTCLoopbackTests` therefore builds two
real `WebRTCClient`s — real `RTCPeerConnectionFactory`, real SDP, real ICE,
real SCTP, real VP8/H.264 — and connects them over the loopback interface,
with `InMemorySignalingTransport` standing in for Firestore and a synthetic
frame generator standing in for the camera (the Simulator has none).

All 9 pass:

| Test | Proves |
|---|---|
| `twoRealPeerConnections_negotiateAndConnect` | ICE genuinely reaches `connected` |
| `theOfferAndAnswerAreRealSdp` | Offer contains `m=video` + `a=recvonly` and `m=application`; answer comes back `a=sendonly` — i.e. the camera's track really attached to the transceiver the controller offered |
| `realIceCandidatesAreExchangedThroughSignaling` | Real `typ host` candidates flow both ways through the signaling layer |
| **`realVideoFramesReachTheController`** | **Frames encoded on one peer are decoded on the other and `FirstFrameSentinel` fires** |
| `aConnectionWithNoCameraTrackNeverConfirmsVideo` | With no track published, ICE still connects and the app still refuses to claim video |
| `controlMessagesCrossTheRealDataChannel` | ping/pong over real SCTP |
| `aMalformedFrameOnTheRealChannelIsDroppedNotFatal` | Raw non-JSON on the wire is dropped; the channel survives and keeps working |
| **`aRealJpegCrossesTheDataChannelAndDecodes`** | **A multi-chunk JPEG is reassembled byte-identical and decodes to the right dimensions** |
| `disconnectingClosesBothRealPeerConnections` | Teardown closes both ends and deletes the session |

What loopback **cannot** cover: NAT traversal, STUN, TURN, packet loss, radio
links, or real camera hardware. Loopback is the easiest possible ICE case.
Those remain Tests F and G.

---

## 3. Three defects found and fixed

These were found by the tests, not by inspection. Worth calling out because
two of them would have been visible immediately on real hardware.

### 3.1 Process abort when leaving any of the new screens — **critical**

Dismissing Connected Devices, Camera Mode or Remote Camera aborted the
process:

```
malloc: *** error for object 0x262c5e6f0: pointer being freed was not allocated
  swift::TaskLocal::StopLookupScope::~StopLookupScope()
  swift_task_deinitOnExecutorImpl(...)
  RemoteCameraViewModel.__deallocating_deinit
  outlined consume of StateObject<RemoteCameraViewModel>.Storage
  @objc _UIHostingView.__ivar_destroyer
```

Every `@MainActor` class gets an **isolated `deinit`**, which the runtime
performs by hopping to the main actor. SwiftUI releases a `@StateObject` from
the hosting view's Objective-C ivar destructor — not inside a Swift task — and
that hop corrupts the concurrency runtime's task-local stack and aborts. The
same thing happens when one isolated deinit runs inside another (a view model
releasing its `DeviceHeartbeat`).

Fixed by marking the deinits `nonisolated` on the six affected classes
(`DeviceHeartbeat`, `WebRTCSessionCoordinator`, `WebRTCClient`, and the three
view models). None of that cleanup needs the main actor — cancelling tasks and
snapshot listeners is safe from any thread.

This reproduces on a device, not just in tests: it is the ordinary dismissal
path.

### 3.2 Empty STUN list made every connection fail

`WebRTCClient.iceServers(from:)` built an `RTCIceServer` from the STUN list
unconditionally. With an empty list that produces a server with no URLs, which
WebRTC rejects outright:

```
(ice_server_parsing.cc:366): ICE server parsing failed: Empty uri. (SYNTAX_ERROR)
```

`peerConnection(with:constraints:delegate:)` then returns `nil` and the whole
session fails. Not reachable from the shipped default (two STUN URLs), but any
STUN-less configuration would have been fatal rather than simply meaning "no
STUN". Now the server is only added when the list is non-empty.

### 3.3 Downscaling compared points against a pixel budget

`SnapshotImageEncoder.downscaled` tested `UIImage.size` — which is in
*points* — against a pixel limit. A 1000×750-point image at scale 3 is
3000×2250 pixels and sailed straight through unshrunk, producing a JPEG
several times the intended size. Now computed in pixels, and the image is
always redrawn so orientation is baked in rather than left as EXIF for the
receiver to reinterpret.

---

## 4. Firestore security rules — **DEPLOYED 12 October 2026**

### The permission error, and what caused it

**Symptom.** Profile → Connected Devices showed *"Couldn't reach the signaling
service: Missing or insufficient permissions"* and the device list stayed
empty. Pantry and Recipes kept working.

**Root cause.** The rules had never been deployed. The ruleset live on
`fridgefit-app` was the one released on **2026-09-09** (ruleset
`53ac3caf-a6ee-4a82-8e1b-25f1c51957df`), which granted only
`users/{uid}/pantry/{id}` and ended with a catch-all
`match /{document=**} { allow read, write: if false; }`. Every device-registry
and signaling path fell through to that deny.

This was confirmed rather than assumed: the live ruleset was fetched from the
Firebase Rules API, loaded into the Firestore emulator, and the app's real
operations were replayed against it.

```
Against the ruleset then live on fridgefit-app:
  DENY   register device  (setDoc users/{uid}/devices/{id})
  DENY   read device      (getDoc users/{uid}/devices/{id})
  DENY   discover devices (list  users/{uid}/devices)
  DENY   create session   (setDoc users/{uid}/webrtcSessions/{id})
  DENY   ICE candidate    (setDoc .../callerCandidates/{id})
  ALLOW  pantry item      (setDoc users/{uid}/pantry/{id})
```

That `ALLOW` on the last line is the clincher: it reproduces the exact
observed behaviour — pantry fine, remote camera dead.

**Ruled out as causes**, each checked rather than assumed:

| Candidate | Finding |
|---|---|
| Auth not complete before listeners attach | Not the cause. Connected Devices is only reachable from `ContentView`, which renders solely when `authViewModel.isAuthenticated`. A nil uid would also have produced `notAuthenticated`, not a permission error. |
| Wrong UID / UID mismatch | Not the cause. `userIDProvider` reads `Auth.auth().currentUser?.uid` at call time and every path is built from it. |
| Incorrect document paths | Not the cause. The paths the code builds match the rules exactly (see the list at the top of `firestore.rules`). |
| Wrong Firebase project | Not the cause. `GoogleService-Info.plist` `PROJECT_ID` is `fridgefit-app`, matching the CLI's project and `GCM_SENDER_ID` 469376880085. |
| Missing Firestore database | Not the cause. `(default)`, `FIRESTORE_NATIVE`, exists. |
| Missing composite index | Not the cause. Both queries are single-field (`calleeDeviceId ==`, `expiresAt <`) and auto-indexed. A missing index also returns `FAILED_PRECONDITION`, not `PERMISSION_DENIED`. |
| Rules not covering subcollections | Would have been a cause had the rules been deployed — a parent rule does **not** cascade to subcollections, so ICE candidates need their own match. The deployed rules cover it. |

### The rules now live

Deployed 2026-10-12, ruleset `2da1764e-a954-40cb-b334-59f0c9f8f439`.
`firestore.rules` is the source of truth; the shape is:

```javascript
function isOwner(uid) {
  return request.auth != null && request.auth.uid == uid;
}

match /users/{uid}/pantry/{pantryItemId}        { allow read, write: if isOwner(uid); }  // unchanged
match /users/{uid}/devices/{deviceId}           { allow read, write: if isOwner(uid); }
match /users/{uid}/webrtcSessions/{sessionId}   { allow read, write: if isOwner(uid); }

match /users/{uid}/webrtcSessions/{sessionId}/{candidateCollection}/{candidateId} {
  allow read, write: if isOwner(uid)
    && candidateCollection in ['callerCandidates', 'calleeCandidates'];
}

match /{document=**} { allow read, write: if false; }   // unchanged
```

Three things worth knowing about that shape:

- **`read` covers `get` *and* `list`.** Discovery lists
  `users/{uid}/devices`, and a camera queries `webrtcSessions` by
  `calleeDeviceId`. Rules can allow `get` while rejecting `list`, so this is
  not incidental.
- **The ICE subcollection needs its own match.** Without it the session
  document reads fine and candidates are denied — SDP is exchanged and the
  connection then never completes, which looks exactly like a network fault.
- **The candidate collection name is pinned** to the two the app uses rather
  than a recursive `{path=**}`, so nothing else under a session becomes
  writable.

### Verified against the live ruleset

After deploying, the live ruleset was fetched back and replayed in the
emulator:

```
Against the ruleset NOW LIVE on fridgefit-app:
  ALLOW  register device              ALLOW  caller ICE candidate
  ALLOW  heartbeat                    ALLOW  callee ICE candidate
  ALLOW  discover devices (list)      ALLOW  listen to ICE candidates
  ALLOW  read device                  ALLOW  session cleanup (delete)
  ALLOW  create session               ALLOW  pantry still works
  ALLOW  write SDP offer
  ALLOW  write SDP answer             DENY   other user reads devices
  ALLOW  camera queries its sessions  DENY   other user reads sessions
                                      DENY   other user reads ICE
                                      DENY   other user reads pantry
                                      DENY   unauthenticated read
ALL AS EXPECTED
```

### Re-deploying

The project is pinned by `.firebaserc`, so a deploy cannot land on the wrong
project by accident:

```bash
cd "<repo root>"
cd firestore-tests && npm test && cd ..      # 42 rules tests, run these first
firebase deploy --only firestore:rules --project fridgefit-app
```

Only `firestore:rules` is ever deployed — never indexes, functions or hosting.

### What the rules can and cannot enforce

They authorise at the **account** level: both devices must be the same
authenticated UID. They *cannot* express "this session is addressed to this
particular device", because the device ID is not part of the request's auth
claims. That second check is enforced client-side in
`WebRTCSessionCoordinator`, which refuses any session whose `calleeDeviceId`
is not this device, and refuses a session this device created itself.

---

## 4a. Security rules tests

`firestore-tests/` runs `firestore.rules` — the same file that gets deployed —
against the Firestore emulator.

```bash
cd firestore-tests
npm install     # first time only
npm test
# tests 42 / pass 42 / fail 0
```

Covers, for devices, sessions, both ICE candidate subcollections and the
pre-existing pantry: owner allowed; other user denied; unauthenticated denied;
plus the default-deny paths and an assertion that an unrelated subcollection
under a session stays closed.

The emulator runs on **port 8575**, configured in the repo-root `firebase.json`
because Docker commonly holds the default 8080. That `emulators` block affects
local testing only — the `firestore` block is what deployment uses.

> `firestore-tests/node_modules/` is not currently covered by `.gitignore`.
> Worth adding a line for it; left alone here rather than touching Git config.

---

## 4b. Error diagnostics

The original failure said only *"Missing or insufficient permissions"*. It did
not say which call was denied, against which path, while signed in as whom —
and the generic hint it did carry was attached to *every* signaling error,
including network drops, so it would have sent someone to redeploy rules that
were already fine.

`FirestoreDiagnostics` now wraps every Firestore call in the feature. A
failure carries the operation, the path, the Firebase error code, the auth
state and the project:

```
Firestore listen denied — path: users/{uid}/devices, code: 7 PERMISSION_DENIED,
auth: signed in (uid a1b2c3d4…), project: fridgefit-app,
message: Missing or insufficient permissions.
```

Logged to subsystem `com.Fridge.FridgeFit`, category `Firestore`. Filter the
device console on that to see it.

**Nothing sensitive is logged.** No tokens, no credentials. The uid is an
account identifier, so the path is rewritten to `users/{uid}/…` and only an
eight-character tag is kept — enough to correlate two devices in one log,
and asserted by `test_theDiagnosticSummaryNeverContainsTheFullUid`.

What the user sees stays readable, and now matches the actual fault:

| Firestore result | What the user is told |
|---|---|
| `PERMISSION_DENIED` (7) | Names the denied path and says the rules for `users/{uid}/devices` and `users/{uid}/webrtcSessions` need deploying |
| `UNAUTHENTICATED` (16), or signed out | "You need to be signed in to use a remote camera" |
| Anything else (e.g. `UNAVAILABLE`) | The underlying message, the code name, and which operation on which path — **no** suggestion to redeploy rules |

Two related fixes went in alongside:

- **Registry writes were not wrapped at all.** `register`, `heartbeat`,
  `updateStatus` and `updateRole` threw raw Firestore `NSError`s, so the first
  thing the screen showed was a bare "Missing or insufficient permissions"
  before the listener's better message replaced it. All now go through the
  same path.
- **Listeners re-read auth on failure.** A snapshot listener used to report
  using the uid captured when it attached. If the user signed out while the
  listener was live, the resulting denial looked like a rules problem; it now
  correctly reports `notAuthenticated`.

---

## 5. Test F — two physical iPhones (NOT TESTED)

No iPhone was connected. `xcrun devicectl list devices` reported the only
paired device as `unavailable`. Run these steps on real hardware.

### Prerequisites

1. ~~Deploy the Firestore rules~~ — **done, 12 October 2026** (§4). Confirm
   with `firebase deploy --only firestore:rules --project fridgefit-app` if
   you are unsure; re-deploying an unchanged file is harmless.
2. Two iPhones on iOS 26.0 or later.
3. A development team set — copy `Secrets.xcconfig.example` to
   `Secrets.xcconfig` and set `LOCAL_DEVELOPMENT_TEAM`.
4. Both iPhones on the **same Wi-Fi** network for the first run.

### Steps

1. Build and run on both devices.
2. Sign in to the **same FridgeFit account** on both. (Different accounts is
   the first negative test — see below.)
3. On **both**: Profile tab → **Connected Devices**. Each should list the
   other within about 10 seconds.
4. **Device A (camera):** tap **Camera Mode**. Grant camera access when asked.
   The preview should appear and status should read **Available**.
   - Leave this screen open. A camera only advertises while the screen is up.
5. **Device B (controller):** tap **Remote Camera**. Device A should appear
   under *Available Cameras*. Tap it.
6. **Verify live video.** Status goes Connecting → Connected, and the
   placeholder is replaced by live video.
   - *If it says "Connected. Waiting for the first video frame…" and stays
     there, that is the app correctly refusing to claim video it is not
     receiving.* Check Device A is still on Camera Mode with a visible preview.
7. **Capture.** Tap **Capture Photo** on Device B. Expect, within ~1 second:
   progress text, then the photo below the live view.
8. **Save.** Tap **Save Locally** (writes to `Documents/RemoteSnapshots/`) or
   **Share**.
9. **Switch camera.** Tap **Switch Remote Camera** — the live view should flip
   between rear and front.
10. **Disconnect / reconnect.** Tap **Disconnect**, then **Reconnect**. A fresh
    session is created; video should return.

### Negative tests worth running

| Scenario | Expected |
|---|---|
| Different Firebase accounts | Neither device lists the other. Discovery is scoped by UID in the Firestore path. |
| Deny camera permission on A | Camera Mode explains and points at Settings; never a black preview. |
| Force-quit A while connected | B shows Reconnecting then the session ends; A drops off the device list within ~35 s (stale heartbeat). |
| Turn Wi-Fi off on A | B shows **Reconnecting** (recoverable), not Failed. |
| Background B mid-session | Session ends cleanly; A returns to Available. |
| Leave Camera Mode on A | B is told immediately via `session_end`, rather than waiting out an ICE timeout. |

---

## 6. Test G — cross-network (NOT TESTED)

**No result is claimed. No network test was invented.**

### Scenario to run

1. Device A (camera) on home Wi-Fi.
2. Device B (controller) on 4G/5G, **Wi-Fi off**.
3. Connect as in §5.

### How to read the outcome

- **Video arrives** → STUN alone was enough. Both NATs were traversable.
- **Status reaches Failed** with *"Couldn't open a direct connection… STUN
  alone only works when both devices can reach each other directly"* → a TURN
  relay is required. This is the expected result behind carrier-grade NAT,
  which most mobile networks use.
- **Connected but no video, then "no video arrived"** → a path was found but
  media is not flowing; usually a one-way candidate pair.

Filter the device console on subsystem `com.Fridge.FridgeFit`, category
`WebRTC` for the state transitions.

### Configuring TURN, if needed

No TURN server is shipped, and none is required for same-Wi-Fi testing.
Nothing has been purchased or deployed. To supply your own, add to the
gitignored `Secrets.xcconfig`:

```
TURN_URL = turn:turn.example.com:3478
TURN_USERNAME = your-username
TURN_CREDENTIAL = your-password
```

All three or none — a half-configured TURN server gathers relay candidates
that always fail authentication, which looks exactly like a network fault.
Credentials are read from Info.plist at runtime and never logged;
`describedForLogs` reports presence only.

---

## 6a. Troubleshooting: permissions still denied

Work down this list — it is ordered by how often each one is the answer.

**1. Confirm what is actually live.** Do not trust the local file; it only
matters if it was deployed.

```bash
firebase deploy --only firestore:rules --project fridgefit-app
```

Or read the live ruleset in the console:
`https://console.firebase.google.com/project/fridgefit-app/firestore/rules`.
The ruleset ID at the time of writing is
`2da1764e-a954-40cb-b334-59f0c9f8f439`; an older ID means the deploy did not
land.

**2. Read the actual error.** Filter the device console on subsystem
`com.Fridge.FridgeFit`, category `Firestore`. The line names the operation,
the path and the code — which immediately separates the cases below.

**3. `code: 16 UNAUTHENTICATED` or `auth: SIGNED OUT`.** Not a rules problem.
The session expired or the user signed out. Sign out and back in.

**4. `code: 7 PERMISSION_DENIED` on a `…/callerCandidates` or
`…/calleeCandidates` path.** The session document rule is deployed but the
subcollection rule is not — a parent rule does not cascade. Symptom is
distinctive: status reaches Connecting, SDP is exchanged, and the connection
never completes. Check the deployed rules contain the
`{candidateCollection}` match.

**5. `code: 7` on `users/{uid}/devices` with `auth: signed in`.** The rules
are stale. Re-deploy and retry.

**6. Right rules, wrong project.** Check they agree:

```bash
plutil -extract PROJECT_ID raw FridgeFit/GoogleService-Info.plist   # fridgefit-app
firebase use                                                        # fridgefit-app
```

A `LOCAL_BUNDLE_ID_SUFFIX` in `Secrets.xcconfig` makes Firebase log a
bundle-id mismatch warning. That warning is harmless and does **not** cause
permission errors — Firestore authorises on the auth token, not the bundle id.

**7. Still denied?** Reproduce in isolation against the deployed rules:

```bash
cd firestore-tests && npm test
```

If those 42 pass but the device still fails, the rules are not the problem —
look at the auth state in the log line.

**8. Devices discovered but never connect.** Not a permissions issue at all;
see §6 on STUN/TURN. Permission failures show up as an error message;
connectivity failures show up as Connecting → Failed.

---

## 7. Known limitations

**STUN is not a connectivity guarantee.** STUN tells each device its own
public address so the two can try to reach each other directly. It does not
relay. Same Wi-Fi works; ordinary home NATs usually work; carrier-grade NAT
and symmetric NAT frequently fail and need TURN. The app says so on screen
rather than implying otherwise.

**No background camera.** iOS does not permit background camera capture.
Camera Mode stops capture on disappear and on backgrounding. The camera device
must stay on the Camera Mode screen with the screen awake.

**Presence is inferred, not declared.** A crashed device cannot write "I'm
gone", so devices heartbeat every 10 s and others treat silence beyond 35 s as
absence. A device that vanishes stays listed for up to 35 seconds.

**Stills are video frames, not full-resolution photos.** The capture comes
from the live 720p stream rather than a second `AVCaptureSession` — two
sessions cannot share one camera, and a second one would stall the live
stream. Plenty for reading a fridge shelf, well above what
`SnapshotImageEncoder`'s 1280px long edge keeps anyway.

**No Simulator camera.** Camera Mode reports "no camera available" in the
Simulator. Testing the camera side needs hardware.

**One session at a time.** A camera already in a session ignores further
offers rather than dropping the live one.

**Recognition is not implemented.** `FoodRecognitionService` is the extension
point; the default conformance returns nothing and says why. FridgeFit's
existing on-device intelligence reads *receipt text*, not food in a
photograph — running it over a picture of vegetables would produce confident
nonsense. `MockFoodRecognitionService` exists for UI work only, is opt-in, and
flags everything `isMockData` so the UI can badge it. **Nothing from this
screen is ever written to the pantry.**

**No backend.** Stale signaling sessions are swept opportunistically when a
device starts a session (2-minute TTL), because there is nowhere to run a cron
job.

**Not load-tested.** Battery drain, thermal behaviour over long sessions, and
behaviour on older hardware are unmeasured.

---

## 8. Architecture

```
┌──────────────── Device A: Camera ────────────────┐   ┌───────────── Device B: Controller ─────────────┐
│ CameraModeView                                   │   │ RemoteCameraView                               │
│   └ CameraModeViewModel                          │   │   └ RemoteCameraViewModel                      │
│       ├ CameraVideoSource                        │   │       ├ ImageTransferAssembler                 │
│       │   └ RTCCameraVideoCapturer               │   │       └ FoodRecognitionService (unimplemented) │
│       │       └ frame tap ──► still capture      │   │                                                │
│       └ WebRTCSessionCoordinator (callee)        │   │       └ WebRTCSessionCoordinator (caller)      │
│           └ WebRTCClient ◄─ RTCPeerConnection    │   │           └ WebRTCClient ◄─ RTCPeerConnection  │
└───────────────────┬──────────────────────────────┘   └────────────────────┬───────────────────────────┘
                    │                                                       │
                    │   ╔═══════════════════════════════════════════════╗   │
                    └──►║ Firestore (signaling only — SDP + ICE)        ║◄──┘
                        ║  users/{uid}/devices/{deviceId}               ║
                        ║  users/{uid}/webrtcSessions/{sessionId}       ║
                        ║    ├ callerCandidates/                        ║
                        ║    └ calleeCandidates/                        ║
                        ╚═══════════════════════════════════════════════╝
                    ┌───────────────────────────────────────────────────────┐
                    │  WebRTC peer-to-peer (never touches Firestore)        │
                    │   • video track     Camera ──────────────► Controller │
                    │   • data channel    control JSON ◄───────► both ways  │
                    │   • data channel    JPEG chunks ─────────► Controller │
                    └───────────────────────────────────────────────────────┘
```

### Data flow, step by step

1. **Auth.** Both devices sign in through the existing `AuthViewModel`. The
   UID scopes every Firestore path, which is what makes "same account" the
   discovery boundary rather than a client-side filter.
2. **Identity.** Firebase UID identifies the *account*, not the phone, so each
   install mints a persistent `deviceId` (`DeviceIdentity`) and publishes
   `users/{uid}/devices/{deviceId}`.
3. **Presence.** A 10-second heartbeat refreshes `lastSeenAt`. Readers treat a
   gap beyond 35 s as offline regardless of the stored status — which is what
   stops a crashed device lingering as "available".
4. **Discovery.** The controller lists devices with `deviceRole == .camera`
   that are present, excluding itself.
5. **Signaling.** The **controller is always the caller**, the camera always
   the callee. Fixing that up front is what avoids SDP glare — neither side
   has to detect a simultaneous offer, because only one side ever creates one.
   - Controller creates the session doc, adds a `recvOnly` video transceiver
     and the data channel, creates the offer, writes it.
   - Camera sees an offer addressed to it, attaches its track, answers.
   - Both push ICE candidates to their own subcollection and read the other's.
     Candidates arriving before the remote description is set are **queued**,
     not dropped — dropping them is a classic "connects most of the time" bug.
6. **Media.** Video flows peer-to-peer. ICE reaching `connected` is *not*
   treated as success: a `FirstFrameSentinel` attached to the remote track
   reports the first decoded frame, and an 8-second watchdog reports
   `mediaNeverArrived` if none comes. The shutter stays disabled until a frame
   is confirmed.
7. **Capture.** Controller sends `capture_photo`. The camera converts its most
   recent video frame to a JPEG (≤1280px long edge), announces
   `capture_completed` with the chunk count, then sends 12 KB binary chunks
   with buffer backpressure. The controller reassembles and displays.
8. **Teardown.** Either side sends `session_end`, marks the document closed and
   deletes it along with both candidate subcollections.

### Design decisions worth knowing

**One capture session.** `AVCapturePhotoOutput` or the existing `CameraPicker`
would each want their own `AVCaptureSession`, and `RTCCameraVideoCapturer`
already owns one. Two sessions competing for one camera is not supported — the
second interrupts the first, so the live stream would stall on every shutter
press. Instead `CameraVideoSource` sits *between* the capturer and the WebRTC
video source as the capturer's delegate: every frame is forwarded untouched
and the most recent one retained. One session, no contention, and the still is
by construction the frame the controller was looking at.

**Images go over the data channel, not Firestore.** Chunked binary frames with
a 27-byte header (magic, version, transfer UUID, chunk index, chunk count).
Base64 in JSON would be a third larger; Firestore would be slow and would
leave a permanent copy of something the user did not ask to store.

**Testability.** `SignalingTransport` and `PeerConnectionControlling` exist so
`WebRTCSessionCoordinator` — which holds the ordering rules that are easy to
get wrong — can be driven end to end with no Firebase, no WebRTC, no camera
and no network. `WebRTCClient` is the only type that touches the SDK.

---

## 9. Files

### Added — domain (pure, no WebRTC or Firebase)

| File | Purpose |
|---|---|
| `Domain/Models/RemoteCamera/DeviceRole.swift` | `camera` / `controller` |
| `Domain/Models/RemoteCamera/DeviceConnectionStatus.swift` | The 7 UI states |
| `Domain/Models/RemoteCamera/RegisteredDevice.swift` | Device document + presence + field mapping |
| `Domain/Models/RemoteCamera/RemoteControlMessage.swift` | DataChannel protocol + total decoder |
| `Domain/Models/RemoteCamera/ImageTransferFrame.swift` | Binary framing + `ImageTransferAssembler` |
| `Domain/Models/RemoteCamera/WebRTCSignalingModels.swift` | SDP/ICE payloads, session record, state machine |
| `Domain/Errors/RemoteCameraError.swift` | Every failure, with actionable text |
| `Domain/Protocols/DeviceRegistry.swift` | Registry abstraction + `RemoteSubscription` |
| `Domain/Protocols/SignalingTransport.swift` | Signaling abstraction |
| `Domain/Protocols/PeerConnectionControlling.swift` | Peer connection abstraction |
| `Domain/Protocols/FoodRecognitionService.swift` | Snapshot extension point |

### Added — data

| File | Purpose |
|---|---|
| `Data/RemoteCamera/DeviceIdentity.swift` | Persistent per-install ID |
| `Data/RemoteCamera/DeviceHeartbeat.swift` | 10 s presence beat |
| `Data/RemoteCamera/FirestoreDeviceRegistry.swift` | `users/{uid}/devices` |
| `Data/RemoteCamera/FirestoreSignalingTransport.swift` | `users/{uid}/webrtcSessions` |
| `Data/RemoteCamera/InMemoryDeviceRegistry.swift` | Test double |
| `Data/RemoteCamera/InMemorySignalingTransport.swift` | Test double |
| `Data/RemoteCamera/MockPeerConnection.swift` | Linkable peer-connection double |
| `Data/RemoteCamera/WebRTCFactory.swift` | Shared factory; disables WebRTC's audio session |
| `Data/RemoteCamera/WebRTCClient.swift` | The only type touching `RTCPeerConnection` |
| `Data/RemoteCamera/WebRTCConfiguration.swift` | STUN default, optional TURN |
| `Data/RemoteCamera/CameraVideoSource.swift` | Capture + frame tap for stills |
| `Data/RemoteCamera/FirstFrameSentinel.swift` | Detects the first decoded frame |
| `Data/RemoteCamera/SnapshotImageEncoder.swift` | Downscale + JPEG + decode |
| `Data/RemoteCamera/FoodRecognitionServices.swift` | Unimplemented (default) + mock |

### Added — use case, view models, views

| File | Purpose |
|---|---|
| `UseCases/WebRTCSessionCoordinator.swift` | Negotiation, ICE, state, teardown, media watchdog |
| `ViewModels/ConnectedDevicesViewModel.swift` | Screen A |
| `ViewModels/CameraModeViewModel.swift` | Screen B |
| `ViewModels/RemoteCameraViewModel.swift` | Screen C |
| `Views/RemoteCamera/ConnectedDevicesView.swift` | Screen A |
| `Views/RemoteCamera/CameraModeView.swift` | Screen B |
| `Views/RemoteCamera/RemoteCameraView.swift` | Screen C |
| `Views/RemoteCamera/WebRTCVideoView.swift` | `RTCMTLVideoView` for SwiftUI + `VideoSurface` |
| `Views/Support/RemoteCameraPresentation.swift` | Status symbols and tints |

### Added — tests

`FridgeFitTests/RemoteCamera/` — `DeviceRegistrationTests`,
`WebRTCSessionCoordinatorTests`, `RemoteControlMessageTests`,
`ImageTransferTests`, `RemoteCameraViewModelTests`, `WebRTCConfigurationTests`,
`WebRTCLoopbackTests`, `RemoteCameraViewMountingTests`.
`FridgeFitTests/Support/` — `SignalingHarness`, `SyntheticVideoSource`.

### Modified

| File | Change |
|---|---|
| `FridgeFit.xcodeproj/project.pbxproj` | Added the `stasel/WebRTC` 154.0.0 package to both targets |
| `FridgeFit/Info.plist` | Camera usage description now mentions streaming to your own device; added `TURN_*` passthroughs |
| `FridgeFit/Views/ProfileView.swift` | Added the **Connected Devices** link (Pantry and Recipes untouched) |
| `Secrets.xcconfig.example` | Documented the optional TURN settings |

### Added / modified for the permission fix (12 October 2026)

| File | Change |
|---|---|
| `firestore.rules` | **Deployed.** Ownership rules for `devices`, `webrtcSessions` and the two ICE candidate subcollections, via an `isOwner(uid)` helper. Pantry rule and default deny unchanged. |
| `.firebaserc` | **New.** Pins the default project to `fridgefit-app` so a deploy cannot land on the wrong project. |
| `firebase.json` | Added an `emulators` block (Firestore on port 8575, UI off). The `firestore` deploy config is unchanged. |
| `firestore-tests/` | **New.** 42 security rules tests against the emulator — `package.json`, `rules.test.mjs`. |
| `FridgeFit/Data/RemoteCamera/FirestoreDiagnostics.swift` | **New.** `FirestoreOperation`, `FirestoreFailure` and the wrapper that attaches operation, path, code, auth state and project to every failure. |
| `FridgeFit/Data/RemoteCamera/FirestoreDeviceRegistry.swift` | Every call routed through `FirestoreDiagnostics`; writes were previously unwrapped. Listener re-reads auth on failure. |
| `FridgeFit/Data/RemoteCamera/FirestoreSignalingTransport.swift` | Same, across all three listeners and every session/candidate operation. |
| `FridgeFit/Domain/Errors/RemoteCameraError.swift` | `signalingUnavailable` surfaces the reason it was given instead of appending a fixed "deploy your rules" hint to every failure. |
| `FridgeFitTests/RemoteCamera/FirestoreDiagnosticsTests.swift` | **New.** 26 tests: code classification, context capture, uid redaction, user-facing mapping, signed-out paths. |
| `FridgeFitTests/RemoteCamera/WebRTCConfigurationTests.swift` | One test updated to match the new error-message ownership. |
| `FridgeFitTests/RemoteCamera/WebRTCSessionCoordinatorTests.swift` | Deployment-guidance test now builds the error the way production does, via `FirestoreFailure`. |

Nothing was removed. Pantry, Recipes, receipt scanning, substitutions and the
Firebase app configuration are unchanged; their 240 tests still pass, and the
pantry rule is byte-for-byte the same behaviour it had before.

---

## 10. Why `stasel/WebRTC`

Google stopped publishing an official iOS WebRTC binary. `stasel/WebRTC` is
the actively maintained SPM distribution of the upstream build, tracking
Chromium milestones (154.0.0 = M154, current at the time of writing).

Compatibility checked before integrating:

| Requirement | Status |
|---|---|
| Swift Package Manager | Yes — binary target, no CocoaPods |
| Xcode 26.1 | Resolves and links cleanly |
| Swift 6.2.1 | Objective-C module; imported `@preconcurrency` |
| iOS 26.0 deployment target | Framework minimum is iOS 12.0 |
| Device + Simulator | `ios-arm64` and `ios-x86_64_arm64-simulator` slices both present |

Added to **both** targets — the test target needs it to load the app module's
interface under `@testable import`, and `WebRTCLoopbackTests` uses it directly.

---

## 11. Git and deployment status

**No Git operations have been performed at any point**, across both the
original implementation and the permission fix. No `status`, `diff`, `log`,
`add`, `commit`, `push`, `pull`, `fetch`, `checkout`, `switch`, `branch`,
`rebase`, `merge`, `tag` or `stash`; no GitHub API calls; no changes to
`.git/`, `.gitignore` or any Git configuration. All changes are working-tree
edits, left uncommitted for review.

**Firebase deployment — Firestore rules only, on 12 October 2026, with
explicit approval.**

```
=== Deploying to 'fridgefit-app'...
✔  cloud.firestore: rules file firestore.rules compiled successfully
✔  firestore: released rules firestore.rules to cloud.firestore
✔  Deploy complete!
```

Verified afterwards by re-fetching the live ruleset:
`2da1764e-a954-40cb-b334-59f0c9f8f439`, updated `2026-10-12T05:09:39Z`
(previously `53ac3caf-a6ee-4a82-8e1b-25f1c51957df` from 2026-09-09).

Nothing else was deployed — no indexes, no functions, no hosting — and no
other Firebase setting was changed. `GoogleService-Info.plist` was not
modified.
