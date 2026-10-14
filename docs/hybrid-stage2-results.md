# Hybrid Ingredient Recognition — Stage 2: Interactive Controller Feature

Stage 1 built the recognition pipeline and measured it. Stage 2 turns it into
something a person can actually use: capture, analyse, review, correct,
confirm.

- **Date:** 13 October 2026
- **Status:** implemented and measured; **no physical-device testing**
- **Scope:** YOLO-World and the YOLO11n fallback unchanged. WebRTC unchanged.
  Nothing is written to Firestore or the Pantry.

---

## 1. What changed

Two measured decisions and one UI.

**Conflict handling now prefers the classifier.** Measured across all four
candidate strategies: when the detector and the classifier disagree about the
same region, the classifier is right 5 times in 8 and the detector 1 time in
8. Switching raised overall recall from 50.0% to 57.9% and precision from
51.4% to 56.4%. It is still marked uncertain, because 5 of 8 is not 8 of 8.

**Automatic OCR-to-ingredient matching is now off by default.** The
`ICE CREAM → cream_carton` error is fixed, and the fix removed the only match
the evaluation set produced. Reading text works; turning text into an
ingredient is not demonstrated, so it is opt-in and the lines are shown to the
user instead.

**The Controller has an Analyse Ingredients flow**: capture → analyse →
review → correct → confirm, locally.

---

## 2. Fusion: choosing a conflict strategy (Task 3)

Same 11 annotated images, same metric. All four strategies run over the same
detector and region-classifier output, so only the resolution rule differs.
Conflicts are scored separately because they are a minority of regions and the
overall number hides the effect.

| Strategy | Overall recall | Precision | Conflicts right | wrong | deferred | Conflict accuracy |
|---|---|---|---|---|---|---|
| A `preferDetector` (Stage 1 default) | 50.0% | 51.4% | 1 | 7 | 0 | **12%** |
| **B `preferClassifier`** | **57.9%** | **56.4%** | **5** | **3** | 0 | **62%** |
| C `higherConfidence` | 52.6% | 54.1% | 3 | 5 | 0 | 38% |
| D `deferToUser` | 50.0% | 55.9% | 0 | 0 | 8 | n/a |

**B is adopted.** It wins on recall *and* precision, and more than fivefold on
the thing actually being decided.

### What this does not say

**It does not say the classifier is always right.** It is wrong in 3 of 8
conflicts. So:

- every conflict stays at `ConfidenceTier.conflicting`, whichever label leads
- every conflict still carries `requiresReview`
- no conflict is ever pre-ticked in the review sheet
- the losing label is kept in `conflictingClaim` and shown to the user
  ("The other method said 'Apple'")

`test_everyStrategyKeepsTheConflictTier` pins the first of those for all four
strategies, so a future change to the rule cannot quietly turn a disagreement
into a confident answer.

### Why C did worse than B

`higherConfidence` compares a YOLO softmax against a Vision calibrated score.
They are not on a common scale, and the measurement says so: it lands between
A and B rather than beating both. Kept as a selectable option because the
objection is easy to raise and the number is the cleanest answer to it.

### Why D exists

`deferToUser` asserts nothing: the region is shown with both candidates and
`assertsIngredient == false`. It has the second-best precision because it
never guesses. It is not the default — it throws away 5 correct answers out of
8 — but it is what makes "we do not know" representable rather than rounded to
one of two guesses, and it is what `assertsIngredient` exists for.

---

## 3. OCR matching (Task 4)

### The bug

`ICE CREAM - ΠΑΓΩΤΑ` matched `cream_carton`. "cream" is a legitimate whole
word inside "ice cream", so whole-word matching — which is what stops `ham`
matching `hammer` — was not enough. The surrounding words change what the word
denotes.

### The fix

Four changes, in `PackagedFoodTextReader`:

1. **Misleading compounds.** A list of phrases that contain an ingredient word
   but are a different food: `ice cream`, `milk chocolate`, `coconut milk`,
   `butter bean`, `cocoa butter`, `rice pudding`, `cheesecake`, `corned beef`,
   `eggplant`, and others. A match is rejected when a compound *properly
   contains* it.

   "Properly contains" matters: `peanut butter` is both a legitimate
   ingredient key and a phrase that must block a bare `butter`. Blocking any
   overlap would make it block itself — which it did, until
   `test_multiWordIngredientNamesMatchAsPhrases` caught it.

   Blocking is also scoped to the misleading word only: `CHICKEN FLAVOUR
   NOODLES` is not chicken, but it *is* noodles.

2. **Script separation.** Lines that are not predominantly Latin are not
   matched against an English vocabulary at all, and are reported through
   `PackagedFoodReading.nonLatinLines`. Without this, "the matcher is bad" and
   "the matcher was given Russian" are indistinguishable.

3. **Certainty, with no `verified` case.** `OCRMatchCertainty` is `.likely` or
   `.uncertain`, never verified. A qualifier (`flavour`, `style`,
   `substitute`) or a poorly-read line forces `.uncertain`. Packaging text is
   evidence about a *product*, not about an ingredient — a cereal box reading
   `RICE` is not a bag of rice.

4. **Automatic matching is off by default.**

### Result on the evaluation set

| Image | Lines | Non-Latin | Matches |
|---|---|---|---|
| `shelf_packaged` | 29 | 14 | **0** |
| `supermarket` | 15 | 3 | **0** |
| `tapas_cheese` | 4 | 0 | **0** |
| all eight unpackaged-food images | 0 | 0 | 0 |

The false positive is gone. So is the only match, so matching is now
**0 true positives and 0 false positives** on this set.

Per the brief's own rule — *"If reliable matching is not demonstrated, disable
automatic OCR-to-ingredient matching in the Demo and retain OCR as
supplemental text for user review"* — `automaticMatchingEnabled` defaults to
`false`. The review sheet shows the lines verbatim in a disclosure group, with
a note when some are not in a Latin script.

The matcher is not dead code: `PackagedFoodMatchingTests` demonstrates it
working on English packaging (`ORGANIC BASMATI RICE 1KG` → `bag_of_rice`,
`SMOOTH PEANUT BUTTER 340G` → `jar_of_peanut_butter`) and refusing the
compounds. Turning it on needs an English-language packaging set to measure
against, which we do not have.

### Non-English, assessed separately

17 of 48 lines across the three packaged images are non-Latin (Cyrillic and
Greek). Those can never match an English vocabulary. This is a vocabulary
coverage gap, not a matcher defect, and it is reported as its own number
rather than folded into a failure rate.

---

## 4. The Controller flow (Tasks 1 and 2)

```
Live WebRTC video + YOLO boxes          (unchanged, still 3 FPS)
        │
        │  "Analyse Ingredients"
        ▼
   capturing ──► data-channel photo request (20 s timeout)
        ▼
   analysing ──► detached task: YOLO on the still → crops → Vision
                 → whole-image Vision → OCR → fusion
        ▼
   summary on the snapshot card: N agreed / N single / N disagree
        │
        │  "Review Ingredients"
        ▼
   review sheet ──► accept / reject / rename / recategorise / add
        ▼
   Confirm ──► [ConfirmedIngredient], local only.  Stage 3 persists.
```

### The action

`RemoteCameraViewModel.captureAndAnalyse()` reports two phases, because a
20-second transfer and a sub-second analysis feel completely different and one
label for both reads as a hang. The button shows a spinner with
"Asking the camera for a photo…" then "Analysing ingredients…".

The capture completes through the data-channel callback, so the method awaits
a `CheckedContinuation` that `handle(binaryFrame:)` resumes on arrival and
`failCapture(reason:)` resumes on failure or timeout. Live video is never
blocked: the transfer is on the data channel and the analysis runs on a
detached task over a still.

Failures surface inline with a Dismiss button rather than as a dead end:
no connection, no video, transfer timeout, model unavailable, and
analysis failure are each reported with their own message.

### The review sheet

Two lists, kept apart:

- **In the photo** — claims with a measured region, drawn on the thumbnail.
- **Suggested** — whole-image classifications, packaging candidates and manual
  additions. **No boxes**, and never drawn.

Each row shows name, category, confidence, the tier, which methods
contributed, the other method's claim when they disagreed, and why review is
needed. Users can toggle acceptance, edit name and category, add a missed
ingredient, and swipe to delete their own additions.

Only `.agreed` rows start ticked, and `FusedIngredient.isPreselected` requires
`assertsIngredient` too, so an unresolved conflict is never pre-ticked.

Editing never rewrites what the model said: `IngredientReviewItem.recognised`
is immutable, and `wasEdited` is derived by comparison. That is the only way
to tell later whether the model was wrong or the mapping was.

---

## 5. Image and box consistency (Task 5)

Every captured photo gets a `snapshotId`, and `SnapshotAnalysis` carries the
id of the photo it describes. `currentAnalysis` returns `nil` unless they
match, and the UI reads only `currentAnalysis`.

This guards a real race: a second capture landing while the first is still
being analysed would otherwise leave the earlier result drawn over the newer
photo. The boxes would be *real* — just measured against different pixels,
which is exactly the kind of error that looks fine in a screenshot.

Verified by `SnapshotAnalysisConsistencyTests`:

| Property | How |
|---|---|
| Analysis belongs to its photo | id injected, mismatch yields `nil` |
| A new photo clears the old analysis | `snapshotId` reassigned on arrival |
| Scene claims never gain a box | `boundingBox == nil` asserted end to end |
| The review split matches which items have boxes | localised vs unlocalised |
| Source geometry travels with the boxes | `sourceSize` carried through |
| Thumbnail mapping is aspect-**fit** | compared against aspect-fill, must differ |
| Live boxes are not reused | analysis re-runs the detector on the still |

The thumbnail is `scaledToFit`, so it maps with
`DetectionGeometry.scaleAspectFit`; the live view is aspect-fill. Using the
live mode on the thumbnail would place every box wrongly, so the test asserts
the two modes actually differ before checking the fitted arithmetic.

Crops come from `DetectionRegionCropper` cutting the detector's own rectangle,
so a region classification is a statement about those pixels. No coordinates
are synthesised anywhere.

---

## 6. Tests

New in Stage 2:

| Suite | Tests | Covers |
|---|---|---|
| `IngredientReviewViewModelTests` | 20 | preselection, accept/reject, rename, recategorise, manual add, duplicates, confirm, empty results |
| `PackagedFoodMatchingTests` | 13 | the ICE CREAM regression, compounds, partial words, certainty, script, default-off |
| `SnapshotAnalysisConsistencyTests` | 9 | identity, staleness, box provenance, aspect-fit mapping |
| `DetectionFusionServiceTests` | +7 | all four strategies, uncertain state, asserted set |

Run the full suite and the device builds with:

```bash
xcodebuild -project FridgeFit.xcodeproj -scheme FridgeFit \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
xcodebuild -project FridgeFit.xcodeproj -scheme FridgeFit \
  -configuration Release -destination 'generic/platform=iOS' build
```

Re-measure the fusion strategies and OCR:

```bash
./tools/vision-eval/swift-harness/build.sh
./tools/vision-eval/swift-harness/harness \
  tools/vision-eval/swift-harness/.resources \
  tools/yolo-export/eval/images tools/yolo-export/eval/annotations.json
```

`VNClassifyImageRequest` still cannot run in the iOS simulator, so
`HybridRecognitionEvaluationTests` skips there and the Mac Catalyst harness
carries the measurement. See `docs/hybrid-stage1-results.md` §7.

---

## 7. Known limitations

1. **No physical-device testing.** See
   [`device-validation-checklist.md`](device-validation-checklist.md) and §8.
2. **11 images.** Eight conflicts decided the fusion strategy. The ordering
   (B > C > A) is consistent, but these are small numbers.
3. **OCR matching is off** and unproven — 0 true positives, 0 false positives
   on a non-English set.
4. **Recognition is still weak on protein and dairy.** Nothing in Stage 2
   changed that; the review sheet's "add a missed ingredient" is the answer
   for now, and the empty state says so explicitly.
5. **Confirmed results are not persisted.** They live in
   `@State` on the Controller screen and are cleared when a new photo arrives.
   Stage 3.
6. **The review sheet is not localised** and assumes English ingredient names.
7. **No cancellation of an in-flight analysis.** The button is disabled while
   busy, and a stale result is discarded by id, but the work itself runs to
   completion.

---

## 8. Device validation (Task 6)

**No compatible devices are connected, so none of the following has been
executed.** Checked at the time of writing:

```
$ xcrun devicectl list devices
K's Apple Vision Pro   …   unavailable   Apple Vision Pro (RealityDevice14,1)
iPhone                 …   unavailable   iPhone 15 Pro (iPhone16,1)
```

Both are paired but **unavailable** — neither is connected and usable — and
the dual-device flow needs *two* iPhones regardless, where only one is known
to this machine at all. Nothing below has been run on hardware, and no claim
in this document rests on device behaviour.

The full checklist is in
[`device-validation-checklist.md`](device-validation-checklist.md); these are
the Stage 2 additions.

Requires two physical iPhones on iOS 26.0+, signed into the same account.

- [ ] **Analyse Ingredients end to end** — tap on the Controller, photo
      arrives, summary appears, review sheet opens
- [ ] **Vision classification actually runs.** This is the big unknown: the
      classifier cannot run in the simulator at all, so the *only* evidence it
      works in an iOS process is this test. Mac Catalyst is not iOS.
- [ ] **Phases are distinguishable** — "Asking the camera…" then "Analysing…"
- [ ] **Live video keeps playing** during both phases
- [ ] **Boxes on the review thumbnail line up** with the objects, in portrait
      and landscape capture
- [ ] **Analysis latency** on-device vs the Mac Catalyst figures (YOLO 17.6 ms,
      Vision 12.0 ms, crops 32.1 ms, OCR 67.5 ms medians)
- [ ] **Memory** during analysis — crops allocate per region
- [ ] **Capture timeout** path — put the camera device to sleep mid-capture
- [ ] **Disconnect during analysis** — the result must not be applied to a
      torn-down session
- [ ] **Reconnect** then analyse again
- [ ] **A second capture during analysis** — the first result must be
      discarded rather than drawn over the new photo (the id check, on real
      timing rather than a test fixture)
- [ ] **Corrections persist** within the sheet; confirm returns the edited
      list
- [ ] **Empty state** — point at an empty shelf and confirm the message, then
      add an ingredient by hand
- [ ] **OCR text appears** for a packaged item, with no automatic matches

Record results in this document under a new "On-device measurements" heading.
Until that section exists, device behaviour is unverified and should be
described that way.
