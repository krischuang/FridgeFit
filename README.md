# FridgeFit

An iOS app for tracking what's in your fridge and cooking from it. Scan a
grocery receipt and FridgeFit reads it on-device with Apple Intelligence,
turns the lines into pantry ingredients, and suggests recipes you can
actually make with what you have — flagging anything missing and offering
substitutions.

**Features**

- **Pantry** — add, update and remove ingredients, stored per-account in an
  on-device SwiftData database.
- **Receipt scanning** — Vision reads the receipt text, Foundation Models
  interprets it into ingredients with quantities and units. Entirely
  on-device; the photo never leaves the phone and never reaches a server.
- **Recipes** — browse recipes and see per-ingredient availability
  (have it / not enough / missing) computed against your real pantry.
- **Recipe suggestions** — on-device Apple Intelligence proposes recipes
  built from what's actually in your pantry.
- **Substitutions** — for any ingredient you're short on, on-device Apple
  Intelligence proposes alternatives, validated against your pantry before
  being shown.
- **Budget & impact** — a food budget, logged grocery spends, valued waste
  and a per-ingredient price book, stored beside the pantry they describe.
- **Accounts** — Firebase Authentication, with email/password and Google
  Sign-In, plus in-app account deletion that removes the cloud data, the
  on-device data and the sign-in itself.

Architecture is layered: `Domain` (models, protocols, errors) → `UseCases`
→ `Data` (SwiftData, Firestore, Vision, Foundation Models) → `ViewModels`
→ `Views`. 1,820 unit tests cover the domain, use-case, persistence and
view-model layers, plus 129 Firebase emulator tests (86 Firestore
security-rules, 43 Cloud Functions account-deletion) run against the local
emulator suite.

A TypeScript Cloud Functions backend for server-side account deletion lives
in `functions/`. It is complete and emulator-tested but **not deployed** —
deploying needs the Blaze plan — so the shipping app uses its on-device
deletion path. See `docs/assessment4-final-production-verification.md`.

### Where your data actually lives

Worth stating plainly, because it is easy to assume otherwise from the
Firebase dependency:

| Data | Where | Synced between devices? |
|---|---|---|
| Pantry, kitchen activity, saved recipes | On device (SwiftData) | No |
| Budget, spends, waste, saved prices | On device (SwiftData) | No |
| Your email address / sign-in | Firebase Authentication | — |
| Remote-camera pairing + WebRTC signalling | Firestore, under `users/{uid}` | — |
| Fridge photos, receipt photos, camera video | Never uploaded | — |

FridgeFit uses **no iCloud and no CloudKit**, and does not sync your kitchen
between devices. `PersistenceConfiguration.compiledDefault` selects
SwiftData; a `-persistence firebase` launch argument switches the business
data to Firestore, and Profile → Settings states whichever one is live (see
`StorageDisclosure`).

---

## Requirements

| | Version | Why |
|---|---|---|
| **Xcode** | **26.1 or newer** | The project is built with the iOS 26 SDK and Swift 6.2 settings (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY`). Older Xcode cannot open it. |
| **iOS deployment target** | **26.0** | The Foundation Models framework (on-device Apple Intelligence) is iOS 26.0+. |
| **macOS** | Whatever Xcode 26.1 requires (macOS 15.6+) | |
| **Apple Developer account** | Free account is fine | Only needed to run on a physical device. |

Simulator is enough to build, run and test everything except the Apple
Intelligence features — those need real hardware (see
[Troubleshooting](#troubleshooting)).

---

## Quick start

```bash
git clone <repo-url>
cd FridgeFit
open FridgeFit.xcodeproj
```

Then press **⌘R**. That's it for the simulator — Firebase config is
committed, Swift packages resolve automatically on first open, and no
secrets file is required.

One optional step, only if you need it:

- Running **on a physical device** → set your team, see
  [Apple Development Team](#apple-development-team).

The three Apple Intelligence features — receipt scanning, recipe
suggestions and ingredient substitutions — need no configuration at all,
but do need a physical device that supports Apple Intelligence with the
feature enabled. See [Apple Intelligence](#apple-intelligence).

---

## Configuration

### Firebase

**Nothing to do.** `FridgeFit/GoogleService-Info.plist` is committed, and
every collaborator shares the one Firebase project (`fridgefit-app`). It is
picked up automatically because the `FridgeFit` folder is an Xcode
*file-system-synchronized group* — files in that folder are bundled
resources without needing to be added to the project file.

This file is committed deliberately. It holds client identifiers, not
credentials; anyone with the app binary can read them. The real security
boundary is `firestore.rules`, which scopes every document to its owning
user. **If this repository is ever made public, re-ignore this file** and
hand it to collaborators out of band instead.

You should not need to create your own Firebase project. If you do, replace
`GoogleService-Info.plist` **and** update the Google Sign-In URL scheme in
`FridgeFit/Info.plist` to your new `REVERSED_CLIENT_ID` — the two must
match or Google Sign-In will fail to return to the app.

### Apple Development Team

Required only for running on a physical device. Simulator builds need no
signing at all.

The team ID is **not** committed — it is read from your own gitignored
`Secrets.xcconfig`, so nobody's team ends up in `project.pbxproj` and
there's no signing churn in pull requests.

```bash
cp Secrets.xcconfig.example Secrets.xcconfig
```

Then uncomment and fill in:

```
LOCAL_DEVELOPMENT_TEAM = ABCDE12345
```

Your 10-character Team ID is in **Xcode → Settings → Accounts → your Apple
ID → Team ID**, or at [developer.apple.com/account](https://developer.apple.com/account)
under Membership details. Restart Xcode after editing the file — xcconfig
changes are only read when the project loads.

Signing stays **automatic**; you do not need to manage provisioning
profiles. Avoid setting the team through Xcode's Signing & Capabilities
pane, because that writes `DEVELOPMENT_TEAM` back into `project.pbxproj`
and you'd be committing your team ID to everyone else's checkout.

### Bundle Identifier

Defaults to `com.Fridge.FridgeFit`, which is what the shared Firebase
project is registered against. **Leave it alone unless a device install
fails with a provisioning error** — that happens when your Apple ID can't
claim an identifier someone else already registered.

If you need your own, set a suffix in `Secrets.xcconfig`:

```
LOCAL_BUNDLE_ID_SUFFIX = .yourname
```

which produces `com.Fridge.FridgeFit.yourname`. Consequences:

- Firebase logs a bundle-ID mismatch warning but **keeps working** — Auth
  and Firestore key off the API key and project ID, not the bundle ID.
- **Google Sign-In is unaffected**; it keys off `CLIENT_ID`.
- Do not commit the suffix — `Secrets.xcconfig` is gitignored, so this is
  handled for you.

### Google Sign-In

**Nothing to do.** The URL scheme in `FridgeFit/Info.plist` already matches
`REVERSED_CLIENT_ID` in the committed `GoogleService-Info.plist`, and
`FridgeFitApp.swift` wires `GIDSignIn` from the Firebase client ID at
launch. Only revisit this if you swap in a different Firebase project.

### Apple Intelligence

**Nothing to configure.** Three features run on Apple's on-device
Foundation Models — receipt scanning, pantry recipe suggestions, and
ingredient substitutions. There is no API key, no account, and nothing
leaves the device.

What they do need is hardware. Each one reads
`SystemLanguageModel.availability` fresh on every use and maps it onto
`AppleIntelligenceAvailability`, so a device that can't run the model gets
an explanation instead of a failure:

| State | What the user sees |
| --- | --- |
| Available | The feature works |
| Apple Intelligence off in Settings | "Apple Intelligence Is Off", with what to turn on |
| Device not eligible | "Not Supported on This Device" |
| Model still downloading | "Apple Intelligence Isn't Ready", try again shortly |

Substitutions in particular never fabricate a suggestion when the model
can't run — *Find Substitute* is replaced by the explanation, and the rest
of the recipe screen keeps working. Pantry, recipes, Discover and auth are
unaffected on every device.

**The simulator cannot actually run these features, but it does not say
so.** On the iOS 26.1 simulator `SystemLanguageModel.availability` reports
`.available`, yet no model assets exist and a generation request never
returns. Substitutions survive this because
`AppleSubstitutionService` bounds every generation with a 20-second timeout
and surfaces "Finding substitutes took too long" — receipt scanning and
recipe suggestions have no equivalent bound and will simply hang on the
simulator. Use a real device to try any of the three.

Everything above the provider is tested against mocks, which is why the
suite itself runs on the simulator.

### Spoonacular API key

Optional, and only for the Discover tab's online recipes — see the
commented `SPOONACULAR_API_KEY` block in `Secrets.xcconfig.example` for
what it enables and how to turn it on.

`Secrets.xcconfig` is **gitignored and must stay that way.** Any key there
is injected via build settings into `Info.plist` at build time, so it never
appears in source. Note that this means the key *is* readable inside the
built app binary — fine for a class project, not a pattern for production.

---

## Building and running

**Xcode:** open `FridgeFit.xcodeproj`, pick the **FridgeFit** scheme (it's
shared and committed, so it's there on a fresh clone), choose a simulator
or device, press ⌘R. Run tests with ⌘U.

**Command line:**

```bash
# Build
xcodebuild build -project FridgeFit.xcodeproj -scheme FridgeFit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Test (240 tests)
xcodebuild test -project FridgeFit.xcodeproj -scheme FridgeFit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Swift package dependencies (Firebase, GoogleSignIn) resolve automatically
on first build. Expect the first build to take several minutes while they
download and compile.

---

## Troubleshooting

**"Could not locate configuration file: 'GoogleService-Info.plist'"** —
the file is missing from `FridgeFit/`. Confirm with
`git ls-files FridgeFit/GoogleService-Info.plist`; if it's absent, your
clone predates this being committed — pull the latest `main`.

**"Signing for 'FridgeFit' requires a development team"** — you're
building for a device without a team set. Follow
[Apple Development Team](#apple-development-team), or just switch the
destination to a simulator, which needs no signing.

**Device install fails with a provisioning / identifier error** — the
default bundle ID is already claimed by another Apple ID. Set
`LOCAL_BUNDLE_ID_SUFFIX`, see [Bundle Identifier](#bundle-identifier).

**Changes to `Secrets.xcconfig` seem to have no effect** — xcconfig files
are read when the project loads. Quit and reopen Xcode, then clean the
build folder (⇧⌘K).

**"The package product 'FirebaseAuth' is not supported" / package resolve
failures** — in Xcode, **File → Packages → Reset Package Caches**, then
**Resolve Package Versions**. `Package.resolved` is gitignored, so each
machine resolves its own versions.

**Receipt scanning, recipe suggestions or substitutions say Apple
Intelligence is unavailable** — expected on the simulator and on hardware
that doesn't support Apple Intelligence. These features need a physical
device with Apple Intelligence enabled in Settings, and the model assets
downloaded. The app degrades gracefully with an explanation rather than
failing; the pantry, recipes and auth are unaffected. See
[Apple Intelligence](#apple-intelligence).

**Project won't open / "unsupported project version"** — you're on an
Xcode older than 26.1. Update Xcode.

---

## Repository layout

```
FridgeFit/              App source (file-system-synchronized group)
  Domain/               Models, protocols, errors — no framework imports
  UseCases/             Business rules
  Data/                 SwiftData, Firestore, Vision, Foundation Models, Spoonacular
  ViewModels/           Observable state for the views
  Views/                SwiftUI screens
  GoogleService-Info.plist   Firebase config (committed on purpose)
  Info.plist            Google Sign-In URL scheme, camera usage, API keys
FridgeFitTests/         240 unit tests
Config.xcconfig         Committed build config; includes Secrets.xcconfig
Secrets.xcconfig.example  Template for your local, gitignored secrets
firestore.rules         Per-user Firestore access rules
docs/                   Feature audit and progress dashboard
```
