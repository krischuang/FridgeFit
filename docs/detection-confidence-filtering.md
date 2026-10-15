# Confidence-based detection filtering

How FridgeFit decides which ingredient predictions reach the Controller's
screen, which numbers control that, and what each number was measured against.

Everything here was produced by re-running the two evaluation harnesses over
the installed model and the 11 annotated images. Nothing is estimated.

- `tools/yolo-export/sweep_display_policy.py` — threshold sweep through the
  app's display policy, Core ML via coremltools. Report:
  `tools/yolo-export/experiments/display_sweep.json`.
- `tools/vision-eval/swift-harness/` — the same policy built **from the app's
  own source files** for Mac Catalyst, so the before/after is measured on the
  shipped code path rather than a Python reimplementation of it. Report:
  `tools/vision-eval/results_swift_hybrid.json`.

---

## 1. The headline, up front

**Raising the confidence threshold does not fix the misclassifications it is
supposed to fix, and above 0.50 it destroys the feature.**

The three errors named in the brief, as the installed model actually reports
them:

| Image | Expected | Model says | Confidence |
|---|---|---|---|
| `eggs_carton` | egg, egg carton | `orange` | **0.726** |
| `beef_raw` | red meat | `bread loaf` | **0.712** |
| `veg_mixed` | carrot, cucumber, courgette, garlic, onion | `bell pepper` | **0.837** |

That last one is the single most confident detection across all 11 images, and
there is no pepper in the photograph. At a 0.80 display threshold it is the
**only** detection left in the entire evaluation set — recall 0.0, precision
0.0. Confidence and correctness are not the same axis for this model, so a
threshold cannot separate them.

What the change actually does:

1. **Fixes a real bug in the frame budget** that was hiding correct detections.
   This is where the measured precision and recall improvement comes from.
2. **Keeps the display threshold at 0.40**, which the sweep confirms is the F1
   maximum.
3. **Stops presenting any live detection as verified**, because the data says
   high confidence does not earn that.
4. **Uses Apple Vision disagreement** as the signal that actually correlates
   with these errors.

---

## 2. The four stages

Separated so each has its own threshold, per the brief. `DetectionFilterPolicy`
holds all of them.

| Stage | What it is | Produced by | Floor |
|---|---|---|---|
| 1. Raw predictions | Core ML output after the export's own per-class NMS (IoU 0.45) | `YOLOFoodDetectionService` | `candidateThreshold` |
| 2. Accepted candidates | Mapped to ingredient identities; decoys dropped, ambiguous classes genericised, same-ingredient overlaps merged | `IngredientNormalizer` | 0.30 |
| 3. Displayed detections | What the overlay draws | `DetectionDisplayFilter` | 0.40 |
| 4. Review suggestions | What the review sheet proposes | `DetectionFusionService` | 0.30 |

**Stage 4 reads stage 2, not stage 3.** This is the requirement that a
detection hidden from the Controller must not silently disappear from the
snapshot pipeline, and it is satisfied structurally rather than by convention:
`SnapshotIngredientAnalyzer` calls `normalizer.normalize(...)` and never
touches the display filter. A 0.34 box the overlay withholds is still cropped,
still classified by Apple Vision, and still reaches the user if Vision
independently names it.

Pinned by `test_aDetectionHiddenFromTheOverlayStillReachesReviewWhenCorroborated`.

### Apple Vision's own thresholds stay separate

Deliberately not folded into `DetectionFilterPolicy`, because they belong to a
different model with a different calibration:

| Setting | Value | Where | Why |
|---|---|---|---|
| Scene classification acceptance | 0.30 | `AppleVisionIngredientClassifier.Configuration` | The knee on this set: 42.1% recall at 72.7% precision, against 55.3%/41.2% at 0.10 |
| Region agreement floor | 0.20 | `DetectionFusionService.Configuration` | Below this a classification is a weak opinion, not a disagreement |
| Scene claim floor | 0.30 | `DetectionFusionService.Configuration` | Higher than the region floor — a scene claim has no location to corroborate it |

A YOLO softmax and a Vision calibrated score are **not** comparable numbers,
and nothing in the pipeline compares them. `ConflictStrategy.higherConfidence`
exists only so that objection could be measured rather than argued; it is not
the default, and it measured worse (§5).

---

## 3. Threshold sweep

`sweep_display_policy.py`, installed model, 11 images, 38 annotated
ingredients. Image-level presence: a true positive is a displayed ingredient
that is in the photo.

### With the shipped policy (box budget of 3)

| Threshold | Precision | Recall | F1 | TP | FP | FN | boxes/image | high-conf errors |
|---|---|---|---|---|---|---|---|---|
| **0.40** | **0.556** | **0.263** | **0.357** | 10 | 8 | 28 | 2.82 | 3 |
| 0.45 | 0.600 | 0.158 | 0.250 | 6 | 4 | 32 | 2.00 | 3 |
| 0.50 | 0.625 | 0.132 | 0.217 | 5 | 3 | 33 | 1.64 | 3 |
| 0.60 | 0.500 | 0.079 | 0.136 | 3 | 3 | 35 | 1.18 | 3 |
| 0.65 | 0.500 | 0.079 | 0.136 | 3 | 3 | 35 | 1.18 | 3 |
| 0.70 | 0.500 | 0.079 | 0.136 | 3 | 3 | 35 | 0.91 | 3 |
| 0.75 | 0.750 | 0.079 | 0.143 | 3 | 1 | 35 | 0.45 | 1 |
| 0.80 | **0.000** | **0.000** | 0.000 | 0 | 1 | 38 | 0.09 | 1 |

**0.40 is chosen.** It maximises F1 by a wide margin. 0.45 buys 4.4 points of
precision for 10.5 points of recall; 0.50 buys 6.9 for 13.1; beyond that
precision *falls* as well, because the detections that survive are
disproportionately the confident wrong ones.

Note the `high-conf errors` column — wrong claims shown with no review flag.
It is **3 at every threshold from 0.40 to 0.70**. The threshold has no
purchase on them at all. The one that finally drops at 0.75 is the eggs→orange
case; `bell pepper` at 0.837 survives to 0.80 and takes precision to zero with
it, because by then it is all that is left.

"Prioritise precision for the live overlay" is the right instruction, and 0.40
is how it is served: the precision gain came from fixing the frame budget
(§4), not from raising the floor. Raising the floor trades away three times as
much recall as it buys in precision.

---

## 4. The actual bug: a flat frame cap starved ingredient diversity

The app capped the overlay at 12 boxes, taken top-down by confidence after
dedupe. On a crowded frame one well-detected ingredient took every slot.

`fruits_mixed` at 0.40, raw per-term box counts:

```
apple 13   banana 3   orange 2   pear 1   pineapple 1   strawberry 1
```

After same-ingredient dedupe and the flat cap of 12, the overlay drew **9
apples and 3 bananas** and nothing else. The orange, pear, pineapple and
strawberry were above the threshold, correctly detected, and invisible —
pushed out by apples that each scored a point or two higher. `veg_mixed` did
the same thing with 11 carrots and one pepper, hiding the courgette.

The fix is a per-ingredient box budget applied *before* the frame budget:
at most `maximumBoxesPerIngredient` (3) boxes of any one ingredient identity.
This is not duplicate suppression — those apples are separate real apples and
three of them are still drawn. It is a fairness rule for a finite overlay.

### Measured effect, Python harness at 0.40

| | Precision | Recall | F1 | TP | FP | boxes/image |
|---|---|---|---|---|---|---|
| Before (flat cap 12) | 0.417 | 0.132 | 0.200 | 5 | 7 | 3.27 |
| **After (budget 3)** | **0.556** | **0.263** | **0.357** | **10** | 8 | **2.82** |

Precision +13.9 points, recall +13.1 points, F1 +0.157, and **fewer** boxes on
screen. Budget sizes 2, 3 and 4 scored identically; 6 lost most of the gain;
unbounded lost all of it. 3 is the middle.

### Measured effect, Swift harness — the shipped code path

Built from `FridgeFit/` sources for Mac Catalyst, so this is the real
normaliser and the real display filter, with Vision's `.scaleFill`
preprocessing rather than PIL's resize.

| | Precision | Recall | FP identities | Total boxes | boxes/image |
|---|---|---|---|---|---|
| Before (flat cap) | 42.9% | 23.7% (9/38) | 12 | 60 | 5.45 |
| **After (budgeted)** | **47.8%** | **28.9%** (11/38) | 12 | **44** | **4.00** |

Precision +4.9 points, recall +5.2 points, **27% fewer rectangles**.

Per-image box counts, before → after:

```
beef_raw          1 ->  1     market_crowded   12 ->  9
chicken_raw       1 ->  1     prawns            0 ->  0
eggs_carton       6 ->  6     shelf_packaged    4 ->  4
fish_platter      2 ->  2     supermarket       9 ->  3
fruits_mixed     12 -> 12     tapas_cheese      1 ->  1
                              veg_mixed        12 ->  5
TOTAL            60 -> 44
```

**Stated plainly:** the false-positive *set* is identical before and after —
the same 12 wrong identities appear in both. Precision improved because the
same box budget now names more correct ingredients, not because any wrong
detection was suppressed. No recognition accuracy was gained by hiding
anything, and none is claimed.

The two harnesses disagree on absolute numbers (23.7% vs 13.2% recall for the
"before" case) because of the PIL-vs-Vision preprocessing difference already
documented in `general-ingredient-detection.md` §4. They agree on the sign and
rough size of every delta, which is what the threshold choice rests on.

---

## 5. Confident misclassifications, and what does help

### What was tried and rejected

Both measured, both left out, both still reproducible in the sweep so the
rejection can be re-checked:

| Rule | Measured at 0.40 | Verdict |
|---|---|---|
| Cross-class spatial NMS | P 0.562, R 0.237, F1 0.333 (vs 0.357) | **Rejected.** At every IoU from 0.60 to 0.85 it removed one false positive *and* a correct `zucchini` from `veg_mixed`. Net F1 down. |
| Decoy veto (drop a food box a more-confident decoy covers) | Identical to shipped, to three decimals | **Rejected.** Zero effect on all 11 images. No measured benefit, so no code. |

Separate physical objects overlap constantly in a fridge drawer. Suppressing
across classes on this evidence would cost more than it saves, which is why
suppression stays strictly within one ingredient identity at IoU 0.55.

No per-category thresholds were introduced. Several categories have one image
in the set; that cannot support a threshold.

### What does correlate: region disagreement

Apple Vision classifying the detector's own crop lands on exactly the regions
where the detector is wrong. From the Swift harness, 11 conflicting regions
across the set — on `beef_raw`, `eggs_carton`, `fish_platter`, `veg_mixed` and
`shelf_packaged`, which is where the detector's false positives are.

Scored by which label is kept in a conflict:

| Strategy | Overall recall | Precision | Conflicts right | Conflict accuracy |
|---|---|---|---|---|
| `preferDetector` | 50.0% | 48.7% | 1 of 11 | **9%** |
| **`preferClassifier`** (shipped) | **60.5%** | **56.1%** | **8 of 11** | **73%** |
| `higherConfidence` | 55.3% | 53.8% | 6 of 11 | 55% |
| `deferToUser` | 50.0% | 54.3% | 0 (11 deferred) | — |

**When the two methods disagree about a region, keeping the detector's label is
right 1 time in 11.** That is the usable signal, and it is available because
the two methods are genuinely independent — different training data, different
architecture, different failure modes.

Implemented as:

- a disagreement is `ConfidenceTier.conflicting`: both labels kept, both
  confidences kept, never pre-ticked, always flagged;
- `ReviewReason.notCorroborated` records the weaker case — Vision classified
  this exact crop and named nothing. "We asked and it saw nothing" and "we
  never asked" are different facts and no longer collapse into one state;
- no hardcoded mappings. A wrong `orange` on a carton of eggs stays an
  `orange` claim the user rejects. It is never silently rewritten to `egg`.

Region classification runs on the **snapshot** path only. It costs one Vision
request per box — median 36.5 ms per image, max 251.8 ms on this machine, and
the wider candidate list made it slower, not faster. The live tap's budget is
333 ms at 3 FPS with WebRTC decoding alongside it, so the worst case does not
fit. Live stays detector-only, which is why live is never called verified.

### Agreement is the best tier and still not proof

On `market_crowded` both methods independently reported "pumpkin" and there is
no pumpkin in the photograph. Agreement measured 6 of 7 correct (85.7%).
Independence reduces correlated error; it does not remove it. Agreement is a
pre-ticked row in a sheet the user still accepts.

---

## 6. Nothing live is verified

`DetectedIngredient.isVerified` is a computed property that returns `false`,
not a stored flag. There is no value the type can hold that makes a
detector-only claim trusted, and `requiresConfirmation` is likewise always
true.

What *does* vary is `DetectionConfidenceBand`, which changes presentation only:

| Band | Confidence | Stroke |
|---|---|---|
| `tentative` | 0.40–0.60 | dashed, amber |
| `strong` | ≥ 0.60 | solid, category tint |

A solid box says the model is confident. It does not say the model is right —
and the overlay carries a standing `N unconfirmed · capture a photo to review`
caption so that is stated rather than implied. Measured precision in the
strong band on this set is 72.2% (13 of 18), i.e. roughly one solid box in
four is wrong.

Verification lives on `FusedIngredient.tier == .agreed`, requires Apple Vision
to have named the same ingredient in the same region, and exists only on the
snapshot path. The pantry is unchanged: only rows the user explicitly accepts
reach it, through `AddDetectedIngredientsUseCase`.

---

## 7. Overlay behaviour

- Each box carries the ingredient name, the confidence percentage, and a
  category glyph. Flagged candidates carry a `?`.
- Labels sit above their box; when two would collide — same row, within 120 pt
  — the lower-confidence one moves inside its own box. Overlapping captions are
  both unreadable and ambiguous about which box they name.
- A box with no room above it puts its label inside regardless.
- When nothing clears the threshold the overlay shows a subtle
  **"No reliable ingredients detected"**. That is a different claim from
  "nothing is there": weak guesses are being withheld, not absent. Nothing is
  fabricated to fill the space, and there is no "show the best weak one anyway"
  fallback.
- Non-food is excluded before the view ever sees it: decoy-category terms are
  dropped in stage 2.

### Flicker and staleness

`displayReleaseThreshold` (0.34) is hysteresis. A detection oscillating around
0.40 between frames would blink three times a second; one already drawn
survives down to 0.34. **Entry stays at 0.40**, so hysteresis can only retain a
box, never introduce one.

`staleAfter` (1.5 s) clears the overlay when results stop arriving. At ~3 FPS
it never fires in normal operation. A gap longer than the window also discards
the retained set, so a stalled stream does not let a weak detection inherit its
place when frames resume.

Live video performance is untouched: the filter is a handful of comparisons on
a list that is already capped at 24, run on the main actor after inference has
already completed off it. `RemoteVideoFrameTap` is unchanged — same 3 FPS
throttle, same one-in-flight rule, same `.utility` queue.

---

## 8. Every number, and where it lives

`FridgeFit/UseCases/DetectionFilterPolicy.swift`:

| Setting | Default | COCO fallback | Basis |
|---|---|---|---|
| `candidateThreshold` | 0.30 | 0.40 | Below display so fusion sees more than the overlay |
| `maximumCandidates` | 24 | 24 | One Vision request per box, snapshot path only |
| `displayThreshold` | 0.40 | 0.45 | F1 maximum in §3 |
| `displayReleaseThreshold` | 0.34 | 0.40 | 0.06 below entry; stops threshold blink |
| `strongThreshold` | 0.60 | 0.60 | Presentation boundary, not a trust boundary |
| `duplicateIoU` | 0.55 | 0.55 | Within one ingredient identity only |
| `maximumBoxesPerIngredient` | 3 | 3 | §4; 2/3/4 scored identically, 6 lost the gain |
| `maximumDisplayedBoxes` | 12 | 12 | Unchanged |
| `staleAfter` | 1.5 s | 1.5 s | ~4 missed frames at 3 FPS |
| `reviewThreshold` | 0.30 | 0.40 | Matches the candidate floor, not the display floor |

The COCO YOLO11n fallback keeps its own policy. Its ten classes are
closed-vocabulary and better calibrated, and nothing in the sweep above
describes that model, so none of the sweep is applied to it.

All of these are pinned by
`IngredientDetectorFactoryTests.test_theShippedFilteringPolicyIsTheOneThatWasMeasured`,
so re-tuning requires editing a test that says why the number is what it is.

### Re-running the measurements

```bash
# Python sweep through the display policy
cd tools/yolo-export
.venv/bin/python sweep_display_policy.py \
    --thresholds 0.40 0.45 0.50 0.60 0.65 0.70 0.75 0.80 \
    --report experiments/display_sweep.json

# Swift harness over the app's own sources (needs the model compiled to
# .mlmodelc next to the vocabulary JSON — xcrun coremlcompiler compile)
./tools/vision-eval/swift-harness/build.sh
./tools/vision-eval/swift-harness/harness <resources> \
    tools/yolo-export/eval/images tools/yolo-export/eval/annotations.json
```

---

## 9. The limitation, not buried

**11 images and 38 annotated ingredients is a smoke test, not a benchmark.**

It is enough to:

- rank 0.40 against 0.80 — the difference is F1 0.357 against 0.000;
- establish that the box-budget bug was real and that fixing it improves both
  precision and recall on the shipped code path;
- establish that no threshold removes the confident misclassifications;
- establish that region disagreement correlates with them, 1-in-11 on 11
  conflicting regions.

It is **not** enough to:

- choose between 0.40 and 0.42;
- support per-category thresholds — several categories have a single image;
- claim a confidence interval on any of these percentages.

Image-level presence is also a generous metric: it asks whether the model found
*an* apple, not whether it found all six. And the two harnesses differ on
absolutes because of the PIL-vs-Vision preprocessing gap.

**All settings here are conservative provisional values**, chosen as the F1
maximum of a small sweep and pinned by tests so a change is deliberate. The
honest statement about the model has not changed: it gives real produce
coverage and gives FridgeFit no protein, seafood or dairy detection
(0/2, 0/6, 0/5 on this set at every threshold). That is a model problem, scoped
in `food-detection-model-research.md`, and no amount of filtering addresses it.

---

## 10. Test coverage

| Area | Where |
|---|---|
| Threshold filtering, borderline values, inclusivity | `DetectionDisplayFilterTests`, `IngredientNormalizerTests` |
| Per-ingredient budget, several real objects of one class | `DetectionDisplayFilterTests` |
| Duplicate and overlapping boxes | `IngredientNormalizerTests` |
| Empty results, no weak-fallback | `DetectionDisplayFilterTests` |
| Stability across frames, hysteresis, staleness | `DetectionDisplayFilterTests`, `RemoteCameraDetectionTests` |
| Confident misclassifications surviving every threshold | `DetectionDisplayFilterTests`, `DetectionUncertaintySignalTests` |
| Disagreement, uncorroborated regions, no hardcoded mappings | `DetectionUncertaintySignalTests` |
| Nothing live is verified | `DetectionUncertaintySignalTests`, `RemoteCameraDetectionTests` |
| Stage 2 wider than stage 3; hidden boxes reach review | `DetectionUncertaintySignalTests`, `RemoteCameraDetectionTests` |
| Hybrid fusion compatibility | `DetectionFusionServiceTests` |
| Label collisions, empty state, box mapping | `YOLODetectionOverlayLayoutTests`, `YOLODetectionOverlayTests` |
| Review sheet behaviour, pantry gating | `IngredientReviewViewModelTests`, `AddDetectedIngredientsUseCaseTests` |
| The shipped numbers are the measured ones | `IngredientDetectorFactoryTests` |
