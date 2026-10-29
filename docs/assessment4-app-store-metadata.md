# FridgeFit — App Store Connect metadata

Drafted against the **shipping configuration** and verified against Apple's
field limits. Every claim describes something that works in the build as it
stands.

**Two rules applied throughout:**

1. **No URL is invented.** Every URL field is marked EXTERNAL REQUIREMENT
   with a note on what must exist. A placeholder that looks real is worse
   than an obvious gap.
2. **Nothing undeployed is described as live.** The Cloud Functions account
   deletion backend is written and emulator-tested but **not deployed**, so
   no copy references server-side deletion.

Markers: **VERIFIED PASS** · **NOT VERIFIED** · **EXTERNAL REQUIREMENT**

---

## 1. Identity

| Field | Value | Limit | Count | Status |
|---|---|---|---|---|
| App Name | `FridgeFit` | 30 | **9** | **VERIFIED PASS** |
| Subtitle | `Cook what you already have` | 30 | **26** | **VERIFIED PASS** |
| Bundle ID | `com.Fridge.FridgeFit` | — | — | matches `GoogleService-Info.plist` |
| Version | `1.0` (`MARKETING_VERSION`) | — | — | from `project.pbxproj` |
| Build | `1` (`CURRENT_PROJECT_VERSION`) | — | — | same |
| SKU | EXTERNAL REQUIREMENT | — | — | chosen in App Store Connect |

Counts measured programmatically, not estimated.

---

## 2. Categories

| Field | Value | Rationale |
|---|---|---|
| Primary | **Food & Drink** | Core purpose: pantry tracking and cooking from what you have |
| Secondary | **Productivity** | Receipt scanning, budgeting and the activity log |

Deliberately **not** Health & Fitness: FridgeFit tracks food inventory and
spending, not nutrition or health outcomes. Choosing it would misdescribe the
app and invite a review question it could not answer.

---

## 3. Age rating — 4+

| Questionnaire item | Answer | Why |
|---|---|---|
| Violence / horror / profanity / sexual content | None | No such content |
| Alcohol, tobacco or drug use or references | **None** | Recipes come from Spoonacular's general catalogue and are not filtered for alcohol as an ingredient |
| Simulated gambling, contests | None | — |
| Medical/treatment information | **None** | Intolerance filters narrow a search; the app makes no medical claim and says so in-app |
| Unrestricted web access | **No** | No in-app browser. External links open in Safari |
| User-generated content / social | **No** | No sharing, no user-to-user content |

**Rating: 4+.** **NOT VERIFIED** — the questionnaire is completed in App
Store Connect and its outcome cannot be produced here.

> One honest caveat worth recording: the recipe catalogue is a third party's
> and may contain recipes using alcohol as a cooking ingredient. Apple
> ordinarily treats culinary use as not requiring a raised rating, but if
> Review disagrees the answer to the alcohol item is the one to revisit.

---

## 4. Promotional text

> Scan a receipt and FridgeFit reads it on your iPhone, not on a server. See what you can cook tonight, what's about to go off, and what your food is costing you.

**160 / 170 characters — VERIFIED PASS.** Editable without a new build.

---

## 5. Keywords

```
pantry,fridge,grocery,receipt,scanner,recipe,leftovers,food waste,budget,ingredients,meal,kitchen
```

**97 / 100 characters — VERIFIED PASS.** No spaces after commas (they count).
No competitor names, no terms the app does not support.

---

## 6. Description

Reviewed line by line against the build. Nothing below describes an
unavailable feature.

```
FridgeFit keeps track of what's in your fridge and helps you cook it before
it goes to waste.

SCAN YOUR RECEIPT
Photograph a grocery receipt and FridgeFit reads it on your iPhone. Apple
Intelligence turns the lines into ingredients with quantities and units, and
you confirm the list before anything is added. The photo never leaves your
phone and is never sent to a server.

KNOW WHAT YOU HAVE
Add, edit and use up ingredients. FridgeFit tracks quantities, storage
location and expiry, and keeps a history of what you finished and what you
threw out.

COOK WHAT YOU ALREADY HAVE
Browse recipes and see, per ingredient, whether you have enough. On-device
Apple Intelligence suggests meals built from your actual pantry, and proposes
substitutes for anything you're short on.

SEE WHAT FOOD COSTS YOU
Set a food budget, log grocery spends, and record what each ingredient cost.
FridgeFit shows what's sitting in your fridge, what's about to expire, and
what waste has cost you this month.

DISCOVER MORE RECIPES
Search thousands of online recipes matched against your pantry, filtered by
diet and by ingredients you avoid. Save the ones you like, and they're
available offline afterwards.

YOUR KITCHEN STAYS ON YOUR IPHONE
Your pantry, history, saved recipes and budget are stored in a database on
your device. They aren't uploaded and aren't synced between devices.
FridgeFit doesn't use iCloud. Your email address identifies your account, and
you can delete your account and everything in it from Profile > Settings.

ON-DEVICE INTELLIGENCE
Receipt reading, recipe ideas and substitutions all run on your iPhone using
Apple Intelligence. They need an iPhone 15 Pro or newer with Apple
Intelligence turned on. Where it isn't available, FridgeFit says so and you
can still add ingredients by hand.

Recipe data from Discover is provided by Spoonacular. When you search, the
ingredient names, your diet filter and the ingredients you avoid are sent to
that service to find matches. Nothing identifying you is sent with them.
```

**2,024 / 4,000 characters — VERIFIED PASS.** (Measured programmatically.)

### Claim check

| Claim | Status |
|---|---|
| On-device receipt reading; photo never leaves | **VERIFIED PASS** — Vision + Foundation Models; device-verified |
| Pantry/budget stored on device, not synced, no iCloud | **VERIFIED PASS** — `compiledDefault == .swiftData`; `StorageDisclosure` |
| Recipe availability per ingredient | **VERIFIED PASS** |
| Suggestions and substitutes on device | **VERIFIED PASS** — device-verified in 4.45 s |
| Budget, spends, waste, prices | **VERIFIED PASS** |
| Discover search and offline saved recipes | **VERIFIED PASS** (needs a configured key) |
| Delete account from Settings | **VERIFIED PASS** — on-device path; **server-side backend not mentioned, because it is not deployed** |
| iPhone 15 Pro or newer for Apple Intelligence | **VERIFIED PASS** — A17 Pro minimum |
| Spoonacular receives search terms | **VERIFIED PASS** — stated plainly |

**Deliberately absent:** cross-device sync, cloud backup, nutrition tracking,
barcode scanning, meal planning, shopping lists, sharing. None exist.

---

## 7. URLs — EXTERNAL REQUIREMENT

| Field | Required? | Status |
|---|---|---|
| Privacy Policy URL | **Mandatory** | **EXTERNAL REQUIREMENT — does not exist.** No URL invented |
| Support URL | **Mandatory** | **EXTERNAL REQUIREMENT — does not exist** |
| Marketing URL | Optional | Not provided |

The app currently links to no privacy policy, and `RegisterView` deliberately
omits a terms/privacy line because there is no document to link to. That is
honest in-app, but **submission is blocked** until a policy is hosted.

### What the policy must cover

Derived from the audit, so it can be written accurately:

1. Email address via Firebase Authentication; Google Sign-In as an option.
2. Pantry, activity, recipes, budget stored **on device**; not synced.
3. Remote-camera device entries and WebRTC signalling in Firestore under the
   user's own uid; **video peer-to-peer, never uploaded**.
4. Discover search sends ingredient names, diet and **food intolerances** to
   Spoonacular, with no identifier; link Spoonacular's policy.
5. Photos processed on device; never uploaded.
6. **No tracking, no advertising, no data brokers.**
7. Deletion: in-app Delete Account removes cloud data, on-device data and the
   sign-in.
8. Contact address for privacy requests.

---

## 8. Privacy nutrition labels

Built from the **archive's 30 manifests**, so SDK collection is included —
not just what FridgeFit's own manifest says.

### Data Used to Track You

**None.** `NSPrivacyTracking` is `false` in all 30 manifests. No IDFA, no ad
SDK, no ATT prompt. **VERIFIED PASS.**

### Data Linked to You

| Type | Source | Purpose |
|---|---|---|
| Email Address | FridgeFit, GoogleSignIn | App Functionality |
| Name | GoogleSignIn | App Functionality |
| Phone Number | **GoogleSignIn (SDK)** | App Functionality |
| User ID | FirebaseAuth, GoogleSignIn | App Functionality |
| Device ID | **GoogleSignIn (SDK)** | App Functionality |
| Coarse Location | **GoogleSignIn (SDK)** | App Functionality |
| Other User Content | FridgeFit (Firebase mode; device entries always) | App Functionality |

> The four SDK-only rows are declared by GoogleSignIn 7.1.0's own manifest.
> FridgeFit requests no extra scopes and never reads them, but Apple requires
> bundled-SDK collection to be disclosed.
> **EXTERNAL REQUIREMENT:** re-confirm at submission.

### Data Not Linked to You

| Type | Source | Purpose |
|---|---|---|
| **Health** (food intolerances) | FridgeFit → Spoonacular | App Functionality |
| **Search History** (ingredient names, time limit) | FridgeFit → Spoonacular | App Functionality |
| Diagnostics | FirebaseAuth, FirebaseFirestore | App Functionality |

### Not collected

Photos, video, audio, contacts, precise location, purchases, browsing
history, sensitive info, financial info.

> The budget figures are financial *in subject matter* but never leave the
> device in the shipping configuration, so they are not "collected". In
> `-persistence firebase` they are stored under the user's own uid and fall
> under Other User Content.

---

## 9. App Review notes

```
FridgeFit is a pantry tracker. Most features work without any account setup
beyond signing in.

TEST ACCOUNT
Sign-in is required. Please create an account with the email/password form on
the first screen - registration is immediate and needs no verification step.
Google Sign-In is also available.

Alternatively use:
  Email:    [EXTERNAL REQUIREMENT - create a synthetic reviewer account]
  Password: [EXTERNAL REQUIREMENT]

WHAT TO TRY
1. Sign up, then My Fridge > + to add a few ingredients by hand.
2. Recipes: per-ingredient availability against what you added.
3. Profile > Impact & Budget: set a budget, log a spend.
4. Profile > Settings: "Where your data lives" states exactly what is stored
   where, and Delete Account removes the account and all of its data.

APPLE INTELLIGENCE FEATURES
Receipt scanning, recipe suggestions and ingredient substitutions run
on-device and need an iPhone 15 Pro or newer with Apple Intelligence enabled.
On other hardware they show an explained unavailable state rather than
failing, and ingredients can still be added by hand. Verified on an
iPhone 15 Pro running iOS 26.6.1.

CAMERA AND LOCAL NETWORK
Camera: receipt and fridge photos, processed entirely on device.
Local Network: Camera Mode streams video directly between two iPhones signed
into the same account on one Wi-Fi network. It needs two devices; declining
either permission leaves an explained state with a route into Settings.

DISCOVER TAB
Online recipe search is provided by Spoonacular. Searches send ingredient
names, the diet filter and the avoid list, with nothing identifying the user.
If the tab reports it is unavailable, the build has no API key configured and
performs no networking.

ACCOUNT DELETION
Profile > Settings > Delete Account. Confirmation, then deletion of cloud
data, on-device data and the sign-in itself. A recent sign-in may be
requested; for a Google account this re-opens Google's sheet rather than
asking for a password.
```

**NOT VERIFIED:** the reviewer credentials must be created by the maintainer
against a synthetic account. No credentials are invented here.

---

## 10. Screenshots — NOT VERIFIED

Required: 6.9" and 6.5" iPhone, up to 10 each. Suggested: My Fridge, Recipes
with availability, Impact & Budget, receipt review, Settings "Where your data
lives". Not produced here; no mock-ups are supplied as evidence.

---

## 11. Submission blockers

| # | Blocker | Type |
|---|---|---|
| 1 | **Guideline 4.8** — Google Sign-In with no equivalent privacy-preserving option | Acknowledged open, out of scope |
| 2 | Privacy Policy URL does not exist | EXTERNAL REQUIREMENT |
| 3 | Support URL does not exist | EXTERNAL REQUIREMENT |
| 4 | Reviewer credentials not created | EXTERNAL REQUIREMENT |
| 5 | Screenshots not produced | NOT VERIFIED |
| 6 | Age-rating questionnaire not completed | NOT VERIFIED |
| 7 | Spoonacular key must be configured, or Discover ships unavailable | Maintainer decision |

Items 2 and 3 are hard blockers: App Store Connect will not accept a
submission without them.
