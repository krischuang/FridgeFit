# Hybrid Ingredient Recognition — Stage 1 Implementation and Results

Apple Vision integrated alongside the existing YOLO-World pipeline, with
crop-based classification, confidence tiering and packaging OCR. Measured on
the same 11 annotated images, with the same metric, through the real Swift
APIs.

- **Date:** 13 October 2026
- **Status:** implemented and measured; **not run on a physical device**
- **Scope:** YOLO-World and the YOLO11n fallback are untouched and still ship.
  Nothing writes to the Pantry.

---

## 1. Headline

Three results, in order of how much they change the plan.

**1. Agreement between the two methods is not infallible, and now there is a
counter-example.** On `market_crowded`, YOLO-World and Apple Vision
*independently* both reported **pumpkin**, and there is no pumpkin in the
photograph. Agreement scored **5/6 correct — 83.3% precision, not 100%**.

The earlier Python figure (9 agreements, 0 errors) described a different
combining rule — set intersection over whole-image labels — and did not
survive contact with the real spatial implementation. Agreement is still the
best-precision tier, and it is still only a pre-ticked suggestion.

**2. Apple Vision reproduced exactly; YOLO-World did not.** Whole-image
classification scored **42.1% / 72.7%** in Swift — identical to Python to
three significant figures. The detector scored 23.7% in Swift against 26.3%
in Python, which turned out not to be a code difference at all (§4).

**3. Crop-based classification has the best precision of anything measured —
80.0%** — and it is the one result that genuinely needs both systems: YOLO
supplies the rectangle, Vision says what is inside it.

---

## 2. Measured results

Mac Catalyst, this machine, `tools/vision-eval/swift-harness`. Metric
identical to `evaluate_vocabulary.py`: per-image set of ingredient
identifiers, `recall = |expected ∩ detected| / |expected|`.

| Candidate | Recall | Prec | FP | fruit | veg | meat | seafood | dairy | pantry |
|---|---|---|---|---|---|---|---|---|---|
| yolo-world (swift) | 23.7% | 42.9% | 12 | 44% | 20% | 0% | 0% | 0% | **25%** |
| vision full-image @0.30 | 42.1% | 72.7% | 6 | 69% | 60% | 0% | 17% | 20% | 0% |
| vision full-image @0.10 | **55.3%** | 41.2% | 30 | 75% | **80%** | **50%** | **33%** | **40%** | 0% |
| **vision crop-based @0.20** | 31.6% | **80.0%** | **3** | 44% | 60% | **50%** | 0% | 20% | 0% |
| hybrid: yolo + crops | 39.5% | 51.7% | 14 | 56% | 60% | 50% | 0% | 20% | 25% |
| hybrid: yolo + full-image | 50.0% | 51.4% | 18 | **81%** | 60% | 0% | 17% | 20% | 25% |
| agreement (localised) | 13.2% | 83.3% | 1 | 25% | 20% | 0% | 0% | 0% | 0% |

**The shipped detector has the worst precision of every candidate measured.**
42.9%, against 72.7% for whole-image classification and 80.0% for classifying
the detector's own crops. Its labels are the weakest component in the system.

Its boxes are a different matter: crop-based classification exists only
because YOLO produces rectangles, and it is the most precise thing here.

### Per-category

- **Pantry is YOLO-only.** 25%, and every Vision variant scores 0%. Vision
  returns `container` and `cardboard_box` for a shelf of packaged goods.
- **Meat is Vision-only.** Crop-based reaches 50%; the detector never scores.
- **Seafood and dairy are whole-image-only**, and only at a permissive
  threshold (33% / 40% at 0.10), where overall precision falls to 41.2%.
- Nothing reaches seafood via crops: the detector draws no box on the prawns
  at all, so there is nothing to crop.

### Latency (Mac Catalyst, median / max, ms)

| Stage | Median | Max |
|---|---|---|
| YOLO detect | 17.6 | 36.4 |
| Vision whole-image | 12.0 | 35.0 |
| Region crops (n boxes) | 32.1 | 247.2 |
| Packaging OCR | 67.5 | 485.2 |

Crops and OCR are far outside a 3 FPS live budget (333 ms per frame for
*everything*). This is the measurement behind putting them on the
captured-photo path rather than the video path.

**Not iPhone numbers.** A Mac is not an A-series phone.

---

## 3. What was built

Live detection is untouched: `RemoteVideoFrameTap`, the 3 FPS throttle, the
one-in-flight rule, `DetectionGeometry` and the overlay all behave exactly as
before. Everything below is additive.

| File | Role |
|---|---|
| `Domain/Models/RemoteCamera/VisionIngredientMap.swift` | Loads the Vision identifier → ingredient map; three-way `kind(of:)` split |
| `Domain/Protocols/IngredientClassifying.swift` | `ClassifiedIngredient`, `ClassificationResult`. Deliberately **no bounding box** |
| `Data/RemoteCamera/AppleVisionIngredientClassifier.swift` | `VNClassifyImageRequest`; `CGImage`, `CVPixelBuffer` and `UIImage` inputs |
| `Data/RemoteCamera/DetectionRegionCropper.swift` | Cuts detector boxes out of a frame; generic over `DetectedRegion` |
| `Data/RemoteCamera/RegionIngredientClassifier.swift` | Crop → classify, keyed back to the originating region |
| `Data/RemoteCamera/PackagedFoodTextReader.swift` | `VNRecognizeTextRequest` + deterministic term matching |
| `Domain/Models/RemoteCamera/FusedIngredient.swift` | `ConfidenceTier`, `EvidenceSources`, `FusedDetectionFrame` |
| `UseCases/DetectionFusionService.swift` | The tiering rules |
| `UseCases/SnapshotIngredientAnalyzer.swift` | Runs the whole pipeline over one captured photo, off the main actor |

Plus a `detect(in: CGImage, …)` overload on `YOLOFoodDetectionService` (the
still-image path; same model, same thresholds) and three new `@Published`
properties on `RemoteCameraViewModel` (`snapshotAnalysis`,
`isAnalyzingSnapshot`, `snapshotAnalysisUnavailable`).

### The rule that shapes the design

**A classification may only be attached to a box when it was computed from
that box.** Region classifications come from cropping the detector's own
rectangle, so pairing them is a claim about the same pixels. Whole-image
classifications go to `FusedDetectionFrame.sceneLevel` with
`boundingBox == nil` and are never drawn.

Merging whole-image labels into detector rectangles would manufacture
localisation nothing measured — Vision saying "salmon" about a photo plus
YOLO boxing a lemon does not put salmon in that box. It is the easiest way to
make the numbers look better than they are.
`test_wholeImageClassificationsNeverReceiveABoundingBox` pins it.

### Single source of truth for the map

`tools/vision-eval/vision_ingredient_map.json` is read by
`score_vision.py` **and** bundled into the app for `VisionIngredientMap`.
The Python dictionaries were deleted and now load from the same file, so the
Swift pipeline and the Python evaluation cannot disagree about what `meat`
means. Vision's `meat`/`beef`/`steak` map to the generic `red_meat` and carry
`requiresReview`, exactly as the detector's ambiguous terms do.

---

## 4. Preprocessing investigation

The detector scored 23.7% in Swift against 26.3% in Python. Rather than
assume a bug, the two paths were diffed per image: they disagreed on ten
individual detections (Python found `orange`, `pear`, `broccoli`, `zucchini`
that Swift missed; Swift found six the Python run did not).

Then the obvious control — change **only** the PIL resampling filter and
re-run the Python harness:

| Resampling filter | Recall | Precision | FP | detections differing from BICUBIC |
|---|---|---|---|---|
| BICUBIC (the published run) | **26.3%** | 55.6% | 8 | – |
| BILINEAR | 21.1% | **61.5%** | 5 | 5 |
| LANCZOS | 23.7% | 56.2% | 7 | 2 |
| NEAREST | 23.7% | 50.0% | 9 | 4 |

**Changing the resampling filter alone moves recall between 21.1% and 26.3%
and precision between 50.0% and 61.5%.** The Swift result (23.7%) sits inside
that band.

Two conclusions:

1. The Swift/Python difference is **not a defect**. It is the model's
   instability near its own threshold, re-expressed through a different image
   decode.
2. **The previously published 26.3% was the most favourable of four filters.**
   It should be read as "roughly 21–26%", and the earlier threshold tuning
   (which picked 0.40 off a sweep at this precision) is less decisive than it
   looked.

Apple Vision reproduced exactly across both paths. The classifier is stable
where the detector is not — a further argument for not leaning on the
detector's labels.

---

## 5. Agreement is not perfect

The research round recorded 9 agreements with 0 errors and flagged that nine
data points prove nothing. The spatial implementation now supplies the
counter-example.

| Image | Agreed ingredient | Correct? |
|---|---|---|
| fruits_mixed | apple, banana, pineapple | ✓ ✓ ✓ |
| market_crowded | apple | ✓ |
| **market_crowded** | **pumpkin** | **✗ — not in the photo** |
| veg_mixed | carrot | ✓ |

Two independently-trained systems made the same mistake on the same region.
Independence reduces correlated error; it does not eliminate it.

**5/6 = 83.3% precision.** Still the highest-precision tier, which is why it
is the one that gets pre-ticked — and still only a default in a sheet the
user confirms. Nothing is written to the Pantry by any code path.

---

## 6. Packaging OCR

OCR itself works and **self-gates**: 29 lines on the packed shelf, 15 on the
supermarket, 5 on the tapas plate, and **0 on all eight unpackaged-food
images**. It can run unconditionally without polluting results for loose
produce.

Term matching is weaker, and the first implementation was simply broken:
**zero matches** on an image with 29 legible lines. The cause was that the
detection vocabulary is phrased for a camera — `bag of rice`, `block of
cheese`, `milk carton` — while a shelf label says `RICE`. Matching the full
phrase found nothing. Fixed by stripping packaging words to a search key
(`bag of rice` → `rice`), longest-key-first so `PEANUT BUTTER` matches
`jar of peanut butter` rather than `butter`, with whole-word matching so
`hammer` does not match `ham`.

After the fix, the evaluation set yields exactly **one** match — `cream_carton`
on the supermarket image, from the text `ICE CREAM - ΠΑΓΩΤΑ`. **That is
wrong**: ice cream is not a carton of cream.

So OCR matching is unproven. In fairness to it, this evaluation set is a poor
test — the packaging is Russian, Greek and German, and the matcher is
English-only. `PackagedFoodTextMatchingTests` shows it working on English
input. An English-language packaging set is needed before any claim about
pantry recall via OCR.

---

## 7. Tests

| Suite | Tests | Runs in simulator |
|---|---|---|
| `DetectionFusionServiceTests` | 13 | yes |
| `DetectionRegionCropperTests` | 8 | yes |
| `VisionIngredientMapTests` | 9 | yes |
| `PackagedFoodTextMatchingTests` | 6 | yes |
| `PackagingOCRTests` | 1 | yes |
| `HybridRecognitionEvaluationTests` | 4 | **skipped — see below** |

The cropper tests crop a four-colour image and assert on returned pixels,
because a vertically mirrored crop still looks like a plausible food crop and
would show up only as unexplained accuracy loss.

### `VNClassifyImageRequest` does not run in the iOS simulator

It fails with `Failed to create espresso context`. Confirmed with a 20-line
reproduction containing no FridgeFit code: the identical program returns 1303
classifications on macOS and fails under the simulator SDK.

`HybridRecognitionEvaluationTests` therefore probes for support at runtime
(rather than `#if targetEnvironment(simulator)`, so a future simulator that
gains support is picked up automatically) and skips with that explanation.
The tests are not deleted and will run on a physical device.

The Swift pipeline is measured regardless, by
`tools/vision-eval/swift-harness` — a Mac Catalyst binary built from **the
app's own source files**, not a reimplementation. Only `Shim.swift` is added,
supplying one unrelated enum so the pantry domain need not be compiled.

```bash
./tools/vision-eval/swift-harness/build.sh
./tools/vision-eval/swift-harness/harness <resources-dir> <images-dir> <annotations.json>
```

---

## 8. Not verified

- **No physical-device run.** Everything is simulator, Mac Catalyst or
  Python. Latency, thermals and on-device accuracy are unmeasured. See
  [`device-validation-checklist.md`](device-validation-checklist.md).
- **The captured-photo flow has no UI yet.** `analyzeSnapshot()` exists and is
  wired to published state; nothing presents it. The analyzer is exercised by
  tests, not by a screen.
- **OCR term matching is effectively unmeasured** (§6).
- **11 images.** Direction, not a benchmark — and §4 shows how much a single
  preprocessing choice moves the detector's numbers.
- **Agreement precision rests on 6 observations.**

---

## 9. Should YOLO stay?

**Yes — for its boxes, not for its labels.**

The case against its labels is now clear: 42.9% precision, the worst of every
candidate; 0% on meat, seafood and dairy; and §4 shows its score swinging five
points on a resampling choice. For *identification*, Apple Vision is better,
free, 0 MB, stable across preprocessing, and carries no AGPL obligation.

The case for its boxes is equally clear, and nothing else measured can do it:

- Crop-based classification — the most precise result here at **80.0%** —
  exists only because something produced rectangles.
- Pantry recall (25%) comes exclusively from the detector.
- The live overlay is a real feature. Whole-image classification cannot draw a
  box, and must not pretend to.

### Recommended next step

**In a conflict, prefer the classifier's label over the detector's.** The
current implementation keeps the detector's label and marks the item
uncertain, which was the conservative choice before there was evidence. There
now is evidence: within a detector box, the classifier is right 80.0% of the
time against the detector's 42.9%. This is a small change in
`DetectionFusionService` and should be measured, not assumed — it is left
unchanged here deliberately.

### Worth testing before committing to 24 MB

YOLO-World is 24 MB and AGPL-3.0, and is now justified by localisation alone.
Two cheaper sources of rectangles are worth measuring against it:

- `VNGenerateObjectnessBasedSaliencyImageRequest` — label-free regions, 0 MB,
  no licence obligation.
- YOLO11n — 5.3 MB, same AGPL problem, already bundled as the fallback.

If either produces boxes good enough to crop, the 24 MB model's remaining
advantage is its 25% pantry recall, which OCR is supposed to replace anyway.

**Do not remove YOLO-World now.** It is the only thing delivering boxes today,
and the fallback chain depends on it.
