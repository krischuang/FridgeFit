# Beyond COCO: Food Detection Model Options for FridgeFit

Feasibility study for detecting materially more food categories than the ten
COCO classes the Controller currently uses. **No implementation changes were
made** — this is research and a migration plan.

- **Date:** 12 October 2026
- **Current model:** YOLO11n (COCO), 80 classes, 10 edible
- **Benchmark hardware:** Apple M4 (macOS), Core ML via coremltools
- **Status:** **superseded by implementation, 13 October 2026** — see below

---

## Outcome (13 October 2026)

The YOLO-World recommendation was implemented and shipped to the Controller.
**See [`general-ingredient-detection.md`](general-ingredient-detection.md) for
what actually went in and how it performs.** This document is retained as the
record of the comparison that led to that decision.

Three things changed between the plan and the result, and they matter:

1. **The vocabulary grew from 80 to 113 terms** (93 ingredients + 20 non-food
   decoys). The 80-term proposal in §5 was sized around the export bug in
   §4.1, which has since been fixed properly by a toolchain upgrade rather
   than worked around by a class count. All three candidate vocabularies were
   then exported and measured; 113 won.

2. **The export bug in §4.1 was a version problem, not an invariant.** On
   `ultralytics==8.4.175` / `coremltools==9.0`, exports at 113 and 601 classes
   both match PyTorch exactly. §4.1 is still worth reading — the failure mode
   is silent — but "numClasses must be 80" was the wrong conclusion.

3. **The protein and dairy result is worse than this study suggested.** §2
   measured YOLO-World naming food classes COCO cannot. Against a
   hand-annotated set at the shipped threshold, image-level recall is
   **0% for meat, 0% for seafood and 0% for dairy/eggs** — confidently wrong,
   not merely missing (raw beef → `bread loaf` 0.71; a carton of eggs →
   `orange` 0.73). Confirmed against focused per-image vocabularies and
   against the *large* model, which was worse. Produce works (~40–44%);
   protein does not.

So the live question this document poses is still open, and is now the main
one: **nothing surveyed here detects raw proteins or dairy.** Closing that gap
needs a food-specific detector or fine-tuning on a food dataset — §3.3 found
no credible pretrained option, and that finding stands.

---

## 1. Verdict

**Recommended: YOLO-World v2 (small) with a curated 80-term fridge
vocabulary.**

It is the only candidate that is simultaneously (a) a large vocabulary
expansion, (b) a *verified* drop-in for the existing Vision pipeline, and
(c) editable without retraining.

| | Current | Recommended |
|---|---|---|
| Food classes | 10 | **80, chosen by us** |
| Dairy / eggs | ✗ none | ✓ milk carton, egg, cheese, butter, yogurt |
| Vocabulary changes | retrain | **edit a list, re-export** |
| Core ML size | 5.5 MB | 25.3 MB |
| Inference (M4, indicative) | 3.0 ms | 9.5 ms |
| Swift changes needed | — | model name + label set |

Two findings below change the picture materially and were only discovered by
actually running the exports (§4): a Core ML export bug that silently
scrambles labels, and the fact that the *nano* Open Images model — the
obvious choice on paper — is unusable in practice.

---

## 2. What was actually measured

Everything in this document was executed locally. Nothing is quoted from a
benchmark table without being reproduced.

**Test images** — three Creative Commons / public-domain photos from Wikimedia
Commons, chosen to be realistic rather than synthetic:

| Image | Content | Licence |
|---|---|---|
| `fruits.jpg` | ~30 culinary fruits, studio layout | CC BY 3.0 |
| `market.jpg` | Barcelona fruit stall, cluttered, people present | CC BY-SA 3.0 |
| `veg.jpg` | Mixed vegetables, market setting | Public domain |

**Method** — each candidate run in PyTorch, exported to Core ML, then the
exported model run through `coremltools` with the same preprocessing iOS uses
(`.scaleFill` to the model's square input). A control run against the app's
*shipped* `YOLO11n.mlpackage` validated the harness before any conclusions
were drawn: Core ML returned `banana 0.838 / apple 0.736` against PyTorch's
`0.83 / 0.74`, i.e. agreement to three decimals.

### Detections on real photos

Food-relevant detections at conf ≥ 0.25:

| Model | `fruits.jpg` | `veg.jpg` | Distinct food classes found |
|---|---|---|---|
| **YOLO11n COCO** *(current)* | 23 (apple, banana, orange) | 15 (carrot) | 4 |
| yolov8**n**-oiv7 | **0** | 3 (cucumber, carrot) | 2 |
| yolov8**s**-oiv7 | 0 | 10 (carrot, cucumber, zucchini) | 3 |
| yolov8**m**-oiv7 | ~6 (apple, pineapple, orange, strawberry) | 37 (carrot ≤0.85) | 7 |
| **YOLO-World v2 s** (fridge vocab) | **79** (apple, banana, strawberry, orange, lime, lemon, grape, bell pepper) | **38** (carrot, potato, zucchini, cucumber, bell pepper) | **13+** |
| YOLOE-11s (text-prompted) | — | carrot ≤0.90, missed cucumber/zucchini | 1 |

YOLO-World is not marginally better; it is in a different league, and its
confidences are high (banana 0.87, bell pepper 0.87, cucumber 0.85).

### Size and speed

Measured on M4 via `coremltools`, 15 runs after warm-up. **These are Mac
numbers and only indicative of ratios on iPhone** — the Neural Engine differs.

| Model | Core ML size | ms/frame (M4) | vs current |
|---|---:|---:|---|
| YOLO11n COCO *(current)* | 5.5 MB | 3.0 | 1.0× |
| yolov8s-oiv7 (601 cls) | 22.9 MB | 9.1 | 3.0× |
| **YOLO-World v2 s (80 cls)** | **25.3 MB** | **9.5** | **3.2×** |
| YOLOE-11s-seg | 40.6 MB | not benchmarked | — |

At the Controller's 3 FPS sampling budget (333 ms/frame), even a 5× increase
leaves enormous headroom. Size is the real cost: the app grows ~20 MB.

---

## 3. Option-by-option

### 3.1 YOLO-World (Tencent AI Lab) — **recommended**

Open-vocabulary detector. `set_classes([...])` bakes CLIP text embeddings for
your chosen terms into the weights; the text encoder is then stripped at
export, leaving an ordinary fixed-class detector.

**Weights:** `yolov8s-worldv2.pt`, `-m`, `-l`, `-x` via Ultralytics (auto-
downloaded). Only `worldv2` variants export; original `world` variants do not.

| | |
|---|---|
| Vocabulary | **Arbitrary.** Any terms you write. |
| Core ML | ✅ Verified: `confidence` + `coordinates` — the exact interface `YOLOFoodDetectionService` already consumes |
| Apple Silicon parity | ✅ Verified on M4: `bell pepper 0.84` vs PyTorch `0.85` |
| Size | 25.3 MB (s) |
| Licence | **GPL-3.0** upstream (Tencent), redistributed by Ultralytics under **AGPL-3.0**. Tencent offers commercial licensing on request. |
| Smallest variant | `s` — there is **no nano**, so ~3× the current compute |

**Caveats.** The exported vocabulary is frozen — changing terms means
re-exporting and shipping a new model. Export needs the `clip` package
(`git+https://github.com/ultralytics/CLIP.git`). And the 80-term vocabulary is
a choice forced partly by §4.

### 3.2 YOLOE (THU-MIG, ICCV 2025) — capable, but a worse fit

Text-prompt, visual-prompt, or prompt-free with a built-in 4,585-name
vocabulary.

| | |
|---|---|
| Vocabulary | Arbitrary, plus a 4,585-name prompt-free mode |
| Core ML | ⚠️ Exports, but emits **raw tensors** (`var_1327`, `var_1365`), not `confidence`/`coordinates` |
| Size | 40.6 MB (11s-seg) |
| Licence | **AGPL-3.0** |
| Detection quality | Found carrots well; **missed** the cucumbers and zucchini YOLO-World caught |

**Why not.** The checkpoints are segmentation models, and the Core ML export
does not produce a Vision-decodable detector. Adopting it means hand-writing
anchor decoding and NMS in Swift — exactly the work the current architecture
avoids — for a model that performed *worse* on the test images and is 60%
larger. The 4,585-class prompt-free mode is interesting but far past the point
where per-frame class filtering stays cheap.

Worth revisiting if Ultralytics ships a detection-only YOLOE with an NMS
pipeline export.

### 3.3 Pretrained food-specific models — no credible option found

| Candidate | Classes | Reality |
|---|---|---|
| [Fruits-And-Vegetables-Detection-Dataset](https://github.com/henningheyen/Fruits-And-Vegetables-Detection-Dataset) | 63 | Weights only for **m/l/x** (no nano/small); mAP50-95 **0.152–0.202**; distributed via a Google Drive folder; dataset MIT, weights licence unstated |
| Roboflow Universe "Ingredients_YOLO" | ~5 (butter, egg, milk, onion, potato) | 221 images — a toy dataset |
| Roboflow "Fruits and vegetables detection" | ~10 | 234 images |

None is a serious upgrade. The best of them has roughly **half** the mAP of
the generic models, ships no small variant, has unclear weight licensing, and
is hosted on personal cloud storage rather than a versioned release. Using one
would trade a well-maintained model for an unmaintained one.

### 3.4 Open Images V7 — the obvious choice that doesn't survive testing

Ultralytics publishes `yolov8{n,s,m,l,x}-oiv7.pt` covering **601 classes**,
including roughly 79 food/drink items — Milk, Egg, Cheese, Cream, Cucumber,
Zucchini, Pineapple, Strawberry, Tomato, Cabbage, Radish, Mushroom and more.
On paper this is exactly what FridgeFit wants, at nano size.

**In practice it does not hold up.**

`yolov8n-oiv7` found **zero** food in `fruits.jpg` at conf 0.25 — a photo
where the current COCO model found 23 items. Dropping the threshold to 0.05
revealed why: its best guess on a tableful of fruit was `Fruit 0.24`. The
confidences are systematically low (reported mAP50-95 is 18.4 vs YOLO11n's
~39 on COCO — different datasets, but the gap is real), and only the
**medium** model (26 M params, ~52 MB) becomes genuinely useful.

Open Images annotations are sparse and its 601 classes overlap heavily
(`Food`, `Fruit`, `Vegetable` compete with `Apple`, `Carrot`), which dilutes
confidence across near-synonyms.

**Still worth knowing:** OIV7 is the only option with real `Milk`, `Egg` and
`Cheese` *labels* out of the box, and `yolov8m-oiv7` does detect Cucumber,
Zucchini, Pineapple and Strawberry — genuinely beyond COCO. It is the fallback
if the YOLO-World licence proves unacceptable.

---

## 4. Two findings that change the plan

### 4.1 The Core ML export silently scrambles labels unless numClasses == 80

This is the most important result here, and it is invisible unless you verify
the export rather than trusting that it succeeded.

On the toolchain FridgeFit currently pins (**ultralytics 8.3.40 /
coremltools 8.1**), `export(format="coreml", nms=True)` produces a model whose
**boxes are correct but whose class scores are wrong** for any class count
other than 80:

```
yolov8s-oiv7 (601 classes), same image, same preprocessing:
  PyTorch : Carrot 0.90, Carrot 0.86, Carrot 0.68, Cucumber 0.64
  Core ML : Cat 0.90, Trousers 0.90, Punching bag 0.86, Train 0.86
```

The top Core ML box is `[0.639, 0.549, 0.311, 0.324]`; PyTorch's *Cucumber*
box is `[0.639, 0.551, 0.313, 0.327]` — the same object, a different label.
Not an off-by-one; the whole confidence vector is wrong. The same happened
with a 27-class YOLO-World export. An 80-class model is unaffected, which is
exactly why the shipped YOLO11n works and why nobody has noticed.

This explains the long-standing
[community "pad your class list to 80" workaround](https://github.com/ultralytics/ultralytics/issues/8461),
closed as *not planned*.

**Two independent fixes, both verified:**

1. **Upgrade the toolchain.** On **ultralytics 8.4.175 / coremltools 9.0** the
   601-class export matches PyTorch exactly (`Carrot 0.90, Carrot 0.86,
   Cucumber 0.65`). Ultralytics has since fixed "MLProgram NMS instability for
   detection models that don't use 80 classes".
2. **Use exactly 80 distinct classes.** Verified independently on the old
   toolchain.

The recommendation does **both**, which is why the vocabulary is 80 terms.

> Whatever model is adopted, the migration must include an automated check
> that Core ML output matches PyTorch. A silent label scramble passes every
> test the app currently has — the boxes still land on objects.

### 4.2 Synthetic test images are misleading

The existing `test_realInferenceFindsAnOrangeInTheKnownImage` uses an orange
disc on white. COCO YOLO11n calls it `orange 0.94`; `yolov8s-oiv7` calls it
`Ball 0.21`. That test is a good *regression* check for the current model but
says nothing about real-world quality. Model comparison needs real photographs
— hence the Wikimedia images above.

---

## 5. The proposed vocabulary

80 distinct terms, sized to the constraint in §4.1 and skewed toward what is
actually in a fridge:

```
Fruit (19)      apple banana orange lemon lime grapefruit strawberry blueberry
                raspberry grape pear peach plum mango pineapple kiwi melon
                watermelon avocado
Vegetable (27)  tomato cucumber zucchini carrot broccoli cauliflower bell pepper
                chilli pepper onion spring onion garlic ginger potato sweet potato
                mushroom lettuce spinach cabbage celery asparagus green beans peas
                corn pumpkin eggplant radish beetroot leek herbs
Dairy/eggs (9)  milk carton milk bottle yogurt pot butter cheese block cheese slice
                cream carton egg egg carton
Drinks (8)      juice carton juice bottle water bottle soda can beer bottle
                wine bottle
Condiments (6)  ketchup bottle sauce jar jam jar pickle jar mayonnaise mustard
Prepared (11)   salad bowl sandwich pizza cake bread loaf bread slice tortilla
                pasta rice bag raw chicken raw fish
```

Terms are phrased as the *visual* object ("milk carton", not "milk") because
that is what an open-vocabulary detector can actually localise. This list is a
starting point to be tuned against real fridge photos — which is the point of
an open-vocabulary model.

---

## 6. Migration plan

Deliberately incremental: the architecture does not change, and each stage is
independently verifiable and revertible.

### Stage 0 — Toolchain (half a day)

- Bump `tools/yolo-export/requirements.txt` to `ultralytics>=8.4.175`,
  `coremltools>=9.0`, matching torch; add
  `git+https://github.com/ultralytics/CLIP.git`.
- Re-export the **current** YOLO11n on the new toolchain and confirm the
  existing 516 tests still pass. Validates the toolchain in isolation, before
  any model change.

### Stage 1 — Export-parity harness (half a day) — *do not skip*

- Add `tools/yolo-export/verify_export.py`: run PyTorch and the exported
  Core ML model over fixture images and fail if top-k labels diverge.
- Wire into `setup.sh` so a scrambled export can never ship (§4.1).

### Stage 2 — Export YOLO-World with the fridge vocabulary (1 day)

- `export_yolo11n.py` → `export_model.py`, taking a model id and a vocabulary
  file; keep YOLO11n reproducible as a fallback.
- Add `tools/yolo-export/fridge_vocabulary.txt` (the 80 terms), asserting
  exactly 80 distinct entries.
- Produce `FridgeFit/Resources/FridgeFitDetector.mlpackage`.

### Stage 3 — Swift changes (half a day)

Genuinely small, because the Core ML interface is identical:

| File | Change |
|---|---|
| `YOLOFoodDetectionService.swift` | `modelName` → `"FridgeFitDetector"`; `Configuration.allowedLabels` sourced from the new vocabulary |
| `DetectedObject.swift` | Replace `COCOFoodClass` with `FridgeFoodClass` reading the same 80 terms; keep the "don't claim what the model can't see" test, updated |
| `YOLOFoodDetectionServiceTests` | New known-image expectations from real fixtures |

`RemoteVideoFrameTap`, `DetectionGeometry`, `YOLODetectionOverlay`,
`RemoteCameraViewModel` and all of the WebRTC layer are **unchanged**. The
`FrameDetecting` protocol already isolates the swap.

### Stage 4 — Tune and verify (1 day)

- Re-tune the confidence threshold: 0.45 suits COCO YOLO11n; YOLO-World's
  calibration differs and will likely want 0.30–0.35.
- Replace the synthetic-orange test with real fixture images (§4.2), keeping
  one synthetic case as a fast regression check.
- Measure on a physical iPhone — the only place the ms/frame numbers in §2
  mean anything. If 3 FPS becomes unsustainable, lower
  `RemoteVideoFrameTap.defaultMinimumInterval` first; the architecture already
  drops frames cleanly.

### Stage 5 — Decide on licensing (blocking for distribution only)

Unchanged from today in kind, but worth re-confirming: see §7.

**Total: ~3–4 days**, dominated by vocabulary tuning rather than code.

### Rollback

The old `YOLO11n.mlpackage` and its export path stay in the repo. Reverting is
a `modelName` change plus a vocabulary swap.

---

## 7. Licensing — no option improves on today

| Option | Licence | Commercial route |
|---|---|---|
| YOLO11n COCO *(current)* | AGPL-3.0 (Ultralytics) | Ultralytics Enterprise |
| **YOLO-World v2** | GPL-3.0 upstream (Tencent); AGPL-3.0 as redistributed | Tencent offer commercial licences on request; or Ultralytics Enterprise |
| YOLOE | AGPL-3.0 | Ultralytics Enterprise |
| Open Images V7 | AGPL-3.0 (Ultralytics) | Ultralytics Enterprise |
| Fruits-and-Veg (63 cls) | Dataset MIT; **weights unstated**, trained with Ultralytics | unclear — worst of the set |

Every realistic candidate is copyleft. Migrating does **not** worsen the
position already documented in `yolo-controller-detection.md` §2, and
YOLO-World arguably improves it by adding a second licensor (Tencent) who
advertises commercial terms. This remains a decision to make before App Store
distribution, not before prototyping.

---

## 8. Honest limitations of this study

- **Nothing was tested on an iPhone.** All latency figures are macOS/M4.
  Neural Engine behaviour, thermals and battery are unmeasured.
- **Three test images.** Enough to expose a tenfold capability gap and a
  silent export bug; not a benchmark. No mAP was computed on a held-out set.
- **No real fridge photos.** Market and studio shots are a proxy. The
  vocabulary should be tuned against photographs from the actual camera
  device, through the actual WebRTC pipeline, which compresses and softens
  detail.
- **YOLOE was tested less thoroughly** than YOLO-World — the raw-tensor export
  ruled it out before deeper evaluation.
- **The 80-term vocabulary is untuned.** Terms like "herbs" and "raw fish" are
  guesses and may perform poorly.
- **Open-vocabulary models hallucinate confidently.** On the cluttered market
  photo, YOLO-World reported 63 "apple" and 55 "bell pepper" boxes at conf
  0.10 — a real risk for a fridge full of overlapping items, and a reason to
  keep the threshold conservative and the per-frame cap in place.

---

## Sources

- [Ultralytics YOLO-World documentation](https://docs.ultralytics.com/models/yolo-world)
- [YOLO-World (Tencent AI Lab) repository and licence](https://github.com/AILab-CVC/YOLO-World)
- [Ultralytics YOLOE documentation](https://docs.ultralytics.com/models/yoloe)
- [YOLOE (THU-MIG), ICCV 2025](https://github.com/THU-MIG/yoloe)
- [Ultralytics Open Images V7 dataset and pretrained models](https://docs.ultralytics.com/datasets/detect/open-images-v7)
- [Open Images V7 class list (601 classes)](https://github.com/ultralytics/ultralytics/blob/main/ultralytics/cfg/datasets/open-images-v7.yaml)
- [Core ML export with custom vocabulary on Apple Silicon — issue #8461](https://github.com/ultralytics/ultralytics/issues/8461)
- [YOLOE Core ML export fix — PR #26567](https://github.com/ultralytics/ultralytics/pull/26567)
- [Fruits-And-Vegetables-Detection-Dataset (63 classes)](https://github.com/henningheyen/Fruits-And-Vegetables-Detection-Dataset)
- [Ingredients_YOLO, Roboflow Universe](https://universe.roboflow.com/leonschrallhammer-web-de/ingredients_yolo)
