# General-Purpose Ingredient Detection (YOLO-World v2)

On-device, open-vocabulary ingredient detection on the Controller's incoming
WebRTC video, replacing the ten edible COCO classes of `yolo11n` with a
113-term ingredient vocabulary spanning fruit, vegetables, meat, seafood,
dairy and pantry goods.

**Read the [Measured performance](#measured-performance) section before relying
on this.** The model works, the pipeline is verified end to end, and the
vocabulary is correct — but YOLO-World v2 (small) genuinely cannot see raw
meat, seafood, eggs or cheese in our test images. That is a capability limit of
the model, not a bug in the integration, and it is documented honestly below
rather than papered over.

---

## 1. What ships

| | |
|---|---|
| Base model | `yolov8s-worldv2` (Ultralytics YOLO-World v2, small) |
| Vocabulary | 113 terms — 93 ingredients + 20 non-food decoys |
| Export | Core ML `.mlpackage`, `nms=True`, 640×640, FP16 |
| On-disk size | 24 MB (vs 5.2 MB for `yolo11n`) |
| Inference | Vision (`VNCoreMLRequest`), on-device only, no network |
| Fallback | `yolo11n` + 10 COCO food classes, retained and tested |
| Firestore | **Nothing is written.** Detection output is in-memory only. |

Both models stay in the bundle; only one is ever instantiated per session
(`test_resolvingProducesASingleDetector`).

### Why open-vocabulary at all

YOLO-World bakes CLIP text embeddings for a fixed term list into the model at
export time via `set_classes()`. After export it is an ordinary closed-set
detector with 113 classes — no text encoder, no CLIP, no runtime prompt
handling on device. Changing the vocabulary means re-exporting, which is why
the vocabulary file is the single source of truth and why parity is checked
against it on every export.

---

## 2. Vocabulary

`tools/yolo-export/ingredient_vocabulary.json` is the source of truth. It is
copied verbatim into `FridgeFit/Resources/` and parsed at runtime by
`IngredientTaxonomy`, so the Swift side can never disagree with the exported
class order.

| Category | Terms | Examples |
|---|---|---|
| fruit | 19 | apple, banana, orange, strawberry, avocado, lemon |
| vegetable | 23 | tomato, broccoli, carrot, bell pepper, lettuce, onion |
| meat / poultry | 14 | chicken breast, bacon, sausage, ground meat, steak |
| seafood | 13 | salmon fillet, prawn, tuna steak, mussel, squid |
| dairy / eggs | 10 | egg, block of cheese, milk carton, butter, yoghurt pot |
| other pantry | 14 | bread loaf, rice, pasta, canned food, flour, eggs carton |
| **decoy** | **20** | plate, bowl, person, hand, kitchen knife, chopping board |
| **total** | **113** | |

Each entry carries `{term, ingredient, display, category, requiresReview,
genericFallback}`.

### Why 113 and not 80

Three vocabularies were exported separately and evaluated on the same
annotated images, at the shipped threshold:

| Vocabulary | Recall @0.40 | Precision @0.40 | False positives | Decoys absorbed |
|---|---|---|---|---|
| A — 80 terms (no decoys) | 21.1% (8/38) | 47.1% | 9 | – |
| B — 93 terms (no decoys) | 23.7% (9/38) | 52.9% | 8 | – |
| **C — 113 terms (93 + 20 decoys)** | **26.3% (10/38)** | **55.6%** | **8** | 23 |

C wins on both axes, so it ships. Two caveats worth stating: the gaps are one
to two detections wide on a 38-item evaluation set, and at a *lower* threshold
(0.35) B and C tie exactly on recall, precision and false positives — the
decoys' measurable benefit there is only that 28 detections carry decoy labels
instead of food labels. The decoy argument is sound in principle and mildly
supported in measurement; it is not a dramatic effect at this sample size.

The 80-class variant was rejected on measurement, not on principle. YOLO-World
has no architectural attachment to 80 classes; the number only matters because
of an export bug (§5).

### Why decoys

Decoys are real vocabulary slots given to non-food objects the model will see
anyway — plates, hands, knives, chopping boards. Without somewhere plausible
to go, a hand gets classified as the nearest food term. On the evaluation set
**23 detections** at threshold 0.40 landed on decoy terms rather than on food
terms. Note the honest size of that effect: against option B (same 93
ingredients, no decoys) the false-positive count is identical at 8 — the
decoys bought one extra true positive, not a halving of errors.

Decoys reach the model; they never reach the user. `IngredientNormalizer`
drops them, and `test_decoyTermsAreNeverReportedAsIngredients` pins that down.

### Category balance

Fruit and vegetables together are 42 of 93 ingredient terms (45%) — a majority
of produce, which matches a fridge, but not an allocation of "nearly all"
slots. Meat, seafood, dairy and pantry hold the other 51. Note that the
measured results do **not** reflect this balance: see §4.

---

## 3. Export and verification

```bash
cd tools/yolo-export
./setup.sh                              # venv + pinned requirements
python export_ingredient_detector.py    # exports and installs into Resources/
python verify_parity.py --model ../../FridgeFit/Resources/FridgeFitIngredients.mlpackage
python evaluate_vocabulary.py --model ../../FridgeFit/Resources/FridgeFitIngredients.mlpackage \
    --thresholds 0.35 0.40 0.50
```

Pinned toolchain (`requirements.txt`): `ultralytics==8.4.175`,
`coremltools==9.0`, `torch==2.8.0`, `torchvision==0.23.0`, plus Ultralytics'
CLIP fork. **These versions are load-bearing** — see §5.

### Parity is mandatory

`verify_parity.py` compares the Core ML package against the PyTorch model it
came from, on every evaluation image:

- class ordering is identical to the vocabulary file, index by index
- detections are matched by IoU (≥0.5 to pair, ≥0.85 to count as agreeing)
- confidences agree within 0.08
- near-ties below `--decisive-conf 0.40` are reported separately, since a
  1-pixel difference can flip the winner there legitimately

Current result against the shipped package:

```
Ordering   : OK (113 classes in vocabulary order)
11/11 images, 0 label mismatches, 0 confidence mismatches, 0 box mismatches
PARITY OK - Core ML matches PyTorch on every image.
```

(Detection counts differ by ±1 on four dense images — `fruits_mixed` 41 vs 42,
`market_crowded` 27 vs 28 — all at sub-0.40 confidence near the NMS cutoff.
Every detection that exists in both is identical.)

The harness has a proven negative control: shuffle the vocabulary and it fails
loudly with `FAIL: class ordering differs at index 0`. A parity check that
cannot fail is not a check.

### In-app parity check

`IngredientTaxonomyTests` reads the `names` metadata out of the shipped
`.mlpackage` and asserts it matches the bundled vocabulary JSON in order. If
someone re-exports with a different term list and forgets to copy the JSON,
the test suite catches it rather than the user seeing "banana" on a carrot.

---

## 4. Measured performance

11 images from Wikimedia Commons, hand-annotated at the image level
(`tools/yolo-export/eval/annotations.json`), licences recorded in
`eval/image_sources.json`. Image-level recall: did the model name an
ingredient that is actually present?

### At the shipped threshold (0.40)

| Category | Recall | False positives |
|---|---|---|
| fruit | 7/16 (43.8%) | 1 |
| vegetable | 2/5 (40.0%) | 2 |
| **meat** | **0/2 (0.0%)** | 1 |
| **seafood** | **0/6 (0.0%)** | 1 |
| **dairy / eggs** | **0/5 (0.0%)** | 1 |
| pantry | 1/4 (25.0%) | 2 |
| **overall** | **10/38 (26.3%)** | **8** — precision 55.6% |

### Threshold sweep

| Threshold | Recall | Precision | False positives | Decoys absorbed |
|---|---|---|---|---|
| 0.35 | 26.3% | 41.7% | 14 | 28 |
| **0.40** | **26.3%** | **55.6%** | **8** | 23 |
| 0.50 | 13.2% | 62.5% | 3 | 14 |

0.40 is the knee: identical recall to 0.35, precision up 14 points, false
positives halved. Above it recall collapses. This is why
`IngredientNormalizer.Configuration.default.displayThreshold` is 0.40, and
`test_theShippedFilteringPolicyIsTheOneThatWasTuned` pins it so the tuning
cannot be silently undone.

### The honest headline: protein and dairy do not work

Zero recall on meat, seafood and dairy is not a phrasing problem or a
threshold problem. It was investigated directly:

- **Focused vocabularies.** Re-exported with only the terms relevant to a
  single image (e.g. just the seafood terms for `prawns`). No improvement.
- **A bigger model.** `yolov8l-worldv2` (large) performed *worse*, not better.
- **What it actually says.** Raw beef → `bread loaf` at 0.71. A carton of eggs
  → `orange` at 0.73. These are confident, wrong, and stable.

YOLO-World v2's training distribution rewards recognisable whole objects.
Raw proteins and dairy are texture-and-colour problems without a canonical
silhouette, and the CLIP text embedding for "salmon fillet" does not land
anywhere useful in its visual space.

**Consequence for the product:** this model gives the Controller real,
broadened coverage of produce — roughly 40–44% image-level recall across fruit
and vegetables, against `yolo11n`'s 10 classes. It does not give FridgeFit
protein or dairy detection. Any pantry feature built on top must treat those
categories as manual entry. Closing that gap needs a food-specific detector or
fine-tuning, which is scoped in
[`food-detection-model-research.md`](food-detection-model-research.md).

### Caveats on these numbers

- **11 images is a smoke test, not a benchmark.** Treat the per-category
  figures as direction, not precision. They are enough to establish that
  produce works and protein does not; they are not enough to rank thresholds
  to two decimal places.
- **Image-level recall is generous.** It asks whether the model found *an*
  apple, not whether it found all six.
- **Preprocessing differs between the harness and the app.** The Python
  evaluation resizes with PIL; the app uses Vision's `.scaleFill`. On a
  synthetic high-contrast fixture these diverge noticeably (coremltools scored
  an orange disc at 0.537, Vision at 0.363 — the box was identical). On
  photographs the gap should be far smaller, but **the 0.40 default is tuned
  against the PIL path and may want re-tuning against on-device measurements.**
  This is a known open item, not a settled number.

---

## 5. The Core ML label-scrambling bug

Worth recording, because it cost real time and it silently produces a model
that looks fine.

On `ultralytics==8.3.40` / `coremltools==8.1`, exporting a YOLO-World model
with any class count **other than 80** produces an `.mlpackage` whose
**bounding boxes are correct and whose class scores are attached to the wrong
labels.** Nothing errors. The model loads, Vision decodes it, boxes land on
objects — and the names are nonsense.

This is the trap the brief warned about: it makes "just use exactly 80 classes"
look like a fix, when it is only a mask over a broken export.

Fixed by upgrading to `ultralytics==8.4.175` / `coremltools==9.0`, after which
a 601-class export and the 113-class export both match PyTorch exactly. The
parity harness exists so this class of bug can never ship again, and the
version pins exist so it cannot creep back.

---

## 6. Swift integration

Reuses the existing detection pipeline wholesale. `RemoteVideoFrameTap`,
`YOLOFoodDetectionService`, the 3 FPS throttle, the one-inference-in-flight
guard and `DetectionGeometry` are unchanged — see
[`yolo-controller-detection.md`](yolo-controller-detection.md).

```
RemoteVideoFrameTap ──► YOLOFoodDetectionService ──► DetectionFrame (raw)
  (real CVPixelBuffer)     (Vision + Core ML)               │
                                                            ▼
                                            IngredientNormalizer (policy)
                                                            │
                                                            ▼
                                            IngredientDetectionFrame
                                                            │
                                                            ▼
                                   RemoteCameraViewModel ──► YOLODetectionOverlay
```

### New types

| File | Role |
|---|---|
| `Domain/Models/RemoteCamera/IngredientTaxonomy.swift` | Loads the bundled vocabulary; `IngredientGroup`, `IngredientDefinition` |
| `Domain/Models/RemoteCamera/DetectedIngredient.swift` | `DetectedIngredient`, `IngredientDetectionFrame`, `DetectionSource`, `ReviewReason` |
| `UseCases/IngredientNormalizer.swift` | All policy: thresholds, decoys, genericisation, duplicate suppression, caps |
| `Data/RemoteCamera/IngredientDetectorFactory.swift` | Model selection and the COCO fallback |

`IngredientGroup` is deliberately separate from the Pantry's existing
`IngredientCategory` and maps onto it via `pantryCategory` (fruit/vegetable →
`.produce`, meat/seafood → `.meat`, dairy → `.dairy`, pantry → `.other`).
Nothing in the Pantry was modified.

### Normalisation policy

`IngredientNormalizer` is where the app decides what it is willing to claim.
Pure functions, no I/O, fully unit-tested.

1. **Unknown terms are dropped.** A label outside the taxonomy is never
   invented into an ingredient.
2. **Decoys are dropped.**
3. **Below 0.40 is dropped** (inclusive at 0.40).
4. **Ambiguous classes are genericised.** 9 terms carry `requiresReview` with a
   `genericFallback`: `raw beef steak`, `lamb chop`, `raw pork` → **Red Meat**;
   poultry terms → **Poultry**. Per the brief, uncertain raw meat is never
   asserted as a species. High confidence does not change this — an
   indistinguishable class stays indistinguishable
   (`test_ambiguousClassesStayFlaggedEvenAtHighConfidence`).
5. **0.40–0.60 is flagged `.lowConfidence`**, rendered with a dashed orange box
   and a trailing `?`.
6. **Duplicates are suppressed within the same ingredient only** (IoU > 0.55).
   Two vocabulary terms mapping to one ingredient (`raw beef steak` +
   `minced beef`) survive the model's per-class NMS and would otherwise draw
   two boxes on one steak. A tomato overlapping a lettuce leaf is two real
   things and both survive.
7. **Sorted by confidence, capped at 12.**

The raw model term is preserved on every result (`rawTerm`) so a reviewer can
always see what the model actually said.

### Fallback

`IngredientDetectorFactory.makeBest()` prefers the ingredient model and falls
back to `yolo11n` + 10 COCO food classes if the model or the vocabulary JSON is
missing or fails to load, recording a human-readable `fallbackReason` that the
UI surfaces as a warning. A degraded Controller shows ten reliable classes
rather than nothing. Tested by hiding each resource from the bundle.

### UI

`YOLODetectionOverlay` tints boxes per category, draws review items in dashed
orange with a `?`, and shows the category SF Symbol in the label. The status
row reports the active model's short name (`YOLO-World` / `YOLO11n`), the
category chips present in frame, an "N to confirm" count, and the fallback
warning when applicable.

---

## 7. Tests

| Suite | Tests | What it covers |
|---|---|---|
| `IngredientTaxonomyTests` | 15 | Vocabulary parsing, category balance, `.mlpackage` ↔ JSON parity |
| `IngredientNormalizerTests` | 24 | Every policy rule above, as pure functions |
| `IngredientDetectorFactoryTests` | 11 | Selection, fallback, **real inference** with the shipped model |

50/50 passing, and the **whole suite is green: 567 tests, 0 failures** on
iPhone 16 Pro simulator — nothing elsewhere in the app regressed.

The inference tests run the real exported model through Vision on a generated
640×640 frame and assert the label, the category, and that the box lands on the
object — which also pins the coordinate convention end to end. Those tests use
a deliberately permissive normaliser: they are testing that inference works,
not re-testing the filtering policy, and the synthetic fixture scores ~0.36
through Vision (see the preprocessing caveat in §4). The shipped 0.40 default
is asserted separately and explicitly.

A blank white frame must produce **nothing** — asserted with the permissive
normaliser, so a spurious detection fails the test instead of hiding behind a
threshold.

### Not verified

**No physical-device run.** Everything above is simulator and Python. The
following require two real iPhones and have not been executed:

- end-to-end dual-device detection over a real WebRTC stream
- sustained 3 FPS and thermal behaviour with a 24 MB model on the Neural Engine
- whether Vision's on-device preprocessing shifts confidences enough to warrant
  re-tuning the 0.40 threshold (§4)

Manual steps are in
[`webrtc-remote-camera-testing.md`](webrtc-remote-camera-testing.md).

---

## 8. Licensing

| Component | Licence | Obligation |
|---|---|---|
| `yolov8s-worldv2` weights | **AGPL-3.0** (Ultralytics) | ⚠️ See below |
| Ultralytics package | AGPL-3.0 | Build-time tooling only |
| `coremltools` | BSD-3-Clause | None |
| CLIP (Ultralytics fork) | MIT | Attribution |
| Evaluation images | CC BY 3.0 / CC BY-SA 3.0 / CC BY-SA 4.0 / public domain | Attribution; recorded per-image in `eval/image_sources.json` |

**The AGPL-3.0 weights are a real distribution question, not a formality.**
Ultralytics licenses YOLO-World weights under AGPL-3.0; shipping a derived
`.mlpackage` in a closed-source App Store binary is widely read as triggering
copyleft. This is fine for coursework and internal prototyping. Before any
public release, FridgeFit needs either an Ultralytics commercial licence, or an
Apache/MIT-licensed detector, or a model fine-tuned from permissively licensed
weights. `yolo11n` is under the same AGPL terms, so the fallback does not avoid
the issue.

Flagged for a human decision — not something to resolve in code.

---

## 9. Known limitations

1. **No meat, seafood, dairy or egg detection.** 0/13 on the evaluation set,
   with confident wrong answers. The headline limitation.
2. **Overall recall is 26.3%.** Useful for produce, not a complete inventory.
3. **24 MB model**, ~4.6× `yolo11n`. Not measured on device for thermals.
4. **Threshold tuned against PIL preprocessing**, not Vision's. May need
   re-tuning on device.
5. **11-image evaluation set.** Direction, not a benchmark.
6. **Vocabulary is fixed at export.** Adding a term means re-exporting and
   re-running parity.
7. **Nothing is persisted.** `IngredientDetectionFrame` is structured for a
   future Pantry write (`pantryCategory`, stable `ingredientId`, `rawTerm`,
   review flags) but no Firestore write exists, per the brief.
8. **AGPL licensing unresolved** for public distribution (§8).
