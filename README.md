# FridgeFit

An iOS app for tracking what's in your fridge and cooking from it. Scan a
grocery receipt and FridgeFit reads it on-device with Apple Intelligence,
turns the lines into pantry ingredients, and suggests recipes you can
actually make with what you have — flagging anything missing and offering
substitutions.

**Features**

- **Pantry** — add, update and remove ingredients, synced per-user through
  Cloud Firestore.
- **Receipt scanning** — Vision reads the receipt text, Foundation Models
  interprets it into ingredients with quantities and units. Entirely
  on-device; the photo never leaves the phone and never reaches a server.
- **Recipes** — browse recipes and see per-ingredient availability
  (have it / not enough / missing) computed against your real pantry.
- **Recipe suggestions** — on-device Apple Intelligence proposes recipes
  built from what's actually in your pantry.
- **Substitutions** — for any ingredient you're short on, get alternatives
  via OpenRouter, validated against your pantry before being shown.
- **Discover (online recipes)** — search Spoonacular for real recipes that
  use your pantry, filtered by diet, intolerances and time, with a
  fail-closed allergen check and an offline cache of the last results.
- **Accounts** — Firebase Authentication, including Google Sign-In.

Architecture is layered: `Domain` (models, protocols, errors) → `UseCases`
→ `Data` (Firestore, Vision, Foundation Models, OpenRouter, Spoonacular) → `ViewModels`
→ `Views`. 240 unit tests cover the domain, use-case and view-model layers.

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

Two optional steps, each only if you need it:

- Running **on a physical device** → set your team, see
  [Apple Development Team](#apple-development-team).
- Using the **substitutions feature** → add an OpenRouter key, see
  [OpenRouter API](#openrouter-api-key).
- Using the **Discover tab** → add a Spoonacular key, see
  [Spoonacular API key](#spoonacular-api-key).

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

### OpenRouter API key

Needed only for the **ingredient substitutions** feature. Without it, the
rest of the app is completely unaffected: `OpenRouterConfiguration`
returns `nil` for a missing key and `ContentView` substitutes an
`UnconfiguredSubstitutionService`, so tapping *Find Substitute* shows a
"not configured" message instead of failing or crashing.

```bash
cp Secrets.xcconfig.example Secrets.xcconfig   # if you haven't already
```

Add your key from [openrouter.ai/keys](https://openrouter.ai/keys):

```
OPENROUTER_API_KEY = sk-or-v1-...
```

The model defaults to `google/gemma-4-31b-it:free` and can be overridden
with `OPENROUTER_MODEL`.

`Secrets.xcconfig` is **gitignored and must stay that way.** The key is
injected via build settings into `Info.plist` at build time, so it never
appears in source. Note that this means the key *is* readable inside the
built app binary — fine for a class project, not a pattern for production.

### Spoonacular API key

Needed only for the **Discover** tab (online recipes). Without it the rest
of the app is unaffected: `SpoonacularConfiguration.load()` returns `nil`
and `ContentView` wires an `UnconfiguredOnlineRecipeService`, so Discover
shows a "not set up" message instead of failing.

Get a free key from the
[Spoonacular console](https://spoonacular.com/food-api/console#Dashboard)
and add it to `Secrets.xcconfig`:

```
SPOONACULAR_API_KEY = your-key
```

Alternatively set the `SPOONACULAR_API_KEY` environment variable on the
run scheme — it takes precedence over the build setting.

The free plan has a daily point quota, so Discover only searches when you
tap **Find Recipes** (never on appear or on pantry edits) and asks for 30
results per search. When the quota is used up you'll see a clear
"limit reached" message; when offline, the last results for the same
pantry + filters are shown and labelled as saved.

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

**Receipt scanning or recipe suggestions say Apple Intelligence is
unavailable** — expected on the simulator and on hardware that doesn't
support Apple Intelligence. These features need a physical device with
Apple Intelligence enabled in Settings, and the model assets downloaded.
The app degrades gracefully with an explanation rather than failing; the
pantry, recipes and auth are unaffected.

**Discover says online recipes aren't set up** — no Spoonacular key. See
[Spoonacular API key](#spoonacular-api-key). If it says the key was
rejected, check for a typo or stray quotes in `Secrets.xcconfig`, then
clean the build folder (⇧⌘K) so `Info.plist` picks up the new value.

**"Find Substitute" reports the feature isn't configured** — no OpenRouter
key. See [OpenRouter API key](#openrouter-api-key).

**Project won't open / "unsupported project version"** — you're on an
Xcode older than 26.1. Update Xcode.

---

## Repository layout

```
FridgeFit/              App source (file-system-synchronized group)
  Domain/               Models, protocols, errors — no framework imports
  UseCases/             Business rules
  Data/                 Firestore, Vision, Foundation Models, OpenRouter, Spoonacular
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
