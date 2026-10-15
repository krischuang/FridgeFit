# Hybrid Ingredient Recognition — Evaluation and Proposal

Follow-on from [`general-ingredient-detection.md`](general-ingredient-detection.md),
which shipped YOLO-World v2 to the Controller and measured it at 26.3% recall
/ 55.6% precision, with **0% on meat, seafood and dairy**.

This document answers: is there a reliable path to general ingredient
recognition, and what should be built next.

- **Date:** 13 October 2026
- **Status:** evaluation complete, nothing implemented
- **Headline:** yes — but not the one that was expected

---

## 1. Verdict

**Apple's built-in `VNClassifyImageRequest` outperforms the YOLO-World model
we just shipped, on the same images, on both recall and precision — and it is
free, offline, already on every device, and carries no AGPL obligation.**

| Candidate | Recall | Precision | False pos |
|---|---|---|---|
| YOLO-World v2, 113 terms @0.40 | 26.3% | 55.6% | 8 |
| **Apple Vision classify @0.30** | **42.1%** | **72.7%** | **6** |

That was not the expected result, and it changes the plan. The second finding
changes it again:

**When YOLO-World and Apple Vision independently agree on an ingredient, they
were right every time — 9 agreements, 0 false positives, 100% precision.**

So the two systems should not be merged into one list. They should form
**confidence tiers**: agreement is trustworthy enough to pre-tick in a review
sheet, either-alone is a suggestion, and nothing is ever written to the Pantry
without the user confirming.

Third finding: **Apple Intelligence cannot help here.** The Foundation Models
framework in the iOS 26.1 SDK accepts text only — verified by inspecting the
shipped `.swiftinterface`, not assumed.

---

## 2. Apple Intelligence feasibility

### Image input is not supported — verified, not assumed

```
$SDK/System/Library/Frameworks/FoundationModels.framework/Modules/
    FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface
```

Occurrences in that 1,536-line interface:

| Symbol | Count |
|---|---|
| `Image`, `CGImage`, `UIImage`, `CIImage`, `CVPixelBuffer` | **0** |
| any identifier containing "mage" | **0** |
| `multimodal`, `attachment` | **0** |

`PromptRepresentable` — the protocol defining what can be put into a prompt —
is adopted by exactly four types: `String`, `Array`, `Prompt`, and
`Optional`. There is no image path into the model. A `Prompt` cannot carry a
photograph.

**Conclusion: Apple Foundation Models cannot analyse a refrigerator image on
this SDK.** Not "poorly" — not at all.

### What it does offer

| | |
|---|---|
| Minimum iOS | 26.0 (matches our deployment target) |
| Platforms | iOS, macOS, visionOS; **unavailable** on tvOS/watchOS |
| Input | Text only |
| Structured output | Yes — `@Generable` / `@Guide` macros, schema-constrained decoding |
| Offline | Yes, on-device |
| Availability gate | `SystemLanguageModel.availability` → `.available` or `.unavailable(.deviceNotEligible / .appleIntelligenceNotEnabled / .modelNotReady)` |
| Context limit | Finite — `GenerationError.exceededContextWindowSize` exists |

Hardware eligibility is Apple Intelligence's, not ours to query directly: per
Apple's published requirements that means roughly iPhone 15 Pro and later.
**We have not verified this on a device**, and the only correct way to handle
it in code is to branch on `availability` rather than on a device-model list.

### Where it *is* useful

Text-only is a real constraint but not a useless one. Foundation Models is a
good fit for the **OCR post-processing** step: turning
`"ГЕРКУЛЕС 500 МАННАЯ КРУПА"` into a structured ingredient guess via
`@Generable`, entirely offline, with no image ever involved. That is a text
problem, which is exactly what the framework does.

It must stay **optional**: on an ineligible device the pipeline has to fall
back to deterministic string matching, because `deviceNotEligible` is a
normal outcome, not an error.

### External multimodal VLM — not recommended, and not measured

| | Apple Vision (on-device) | External VLM (GPT-4o / Claude class) |
|---|---|---|
| Measured here | **Yes** | **No** |
| Offline | Yes | No |
| Privacy | Image never leaves device | Fridge interiors sent to a third party |
| Latency | ~9 ms classify | 1–5 s round trip |
| Cost | £0 | Per-image, recurring |
| Ingredient breadth | 1,303 classes, fixed | Open-ended, far better on protein/dairy |

A VLM would almost certainly fix the protein and dairy gap — that is what
these models are good at. But it inverts the project's stated constraint
("no cloud AI dependencies", on-device only), sends photographs of users'
homes to a third party, and costs money per scan.

**I have not measured one.** Doing so would require sending the evaluation
images to an external API, which is a decision about data egress and spending
that belongs to you, not to me. The table above is from published
characteristics, not measurement, and is marked as such. If you want it
measured, say so and I will run the same 11 images and the same metric.

---

## 3. Model comparison

Same 11 annotated images, same metric as `evaluate_vocabulary.py`
(`recall = |expected ∩ detected| / |expected|`, per image, set-based), same
annotation file. Reproduce with `tools/vision-eval/compare_candidates.py`.

| Candidate | Recall | Prec | FP | fruit | veg | meat | seafood | dairy | pantry |
|---|---|---|---|---|---|---|---|---|---|
| YOLO-World @0.40 (shipped) | 26.3% | 55.6% | 8 | 44% | 40% | 0% | 0% | 0% | **25%** |
| Apple Vision @0.30 | 42.1% | 72.7% | 6 | 69% | 60% | 0% | 17% | 20% | 0% |
| Apple Vision @0.10 | 55.3% | 44.7% | 26 | 75% | 80% | **50%** | 33% | 40% | 0% |
| Union (Vision @0.30) | 44.7% | 54.8% | 14 | 69% | 60% | 0% | 17% | 20% | 25% |
| Union (Vision @0.10) | **57.9%** | 39.3% | 34 | 75% | 80% | 50% | 33% | 40% | 25% |
| **Agreement (AND)** | 23.7% | **100%** | **0** | 44% | 40% | 0% | 0% | 0% | 0% |

### What this says

**A naive union is the wrong design.** Merging both detectors' output raises
recall from 42.1% to 44.7% — one extra true positive — while more than
doubling false positives (6 → 14) and dropping precision below either system
alone. Recall is not free.

**Agreement is remarkably clean.** Zero false positives across the set. The
caveat matters and is not small: that is 9 agreements on 11 images. 100% on a
sample this size means "no counter-example yet", not "never wrong". It is
enough to justify treating agreement as a *higher* tier; it is not enough to
justify writing to the Pantry without confirmation.

**The two systems fail differently, which is why tiering works.** YOLO-World
is the only candidate that scores on pantry items (25%); Apple Vision is the
only one that scores on seafood and dairy. Apple Vision at 0.10 is the only
thing that has ever scored on meat (50%).

**Apple Vision still cannot do packaged goods** (0% pantry at every
threshold). It returns `container` and `cardboard_box`, not the product.

### OCR covers exactly the gap — and self-gates

`VNRecognizeTextRequest` over the same images:

| Image | Lines | Sample |
|---|---|---|
| `shelf_packaged` | 29 | `ГЕРКУЛЕС`, `МАННАЯ КРУПА`, `МАНКА` (oats, semolina) |
| `supermarket` | 18 | `BAKERY`, `FRUITS - ΦΡΟΥΤΑ`, `ICE CREAM`, `CocaCola`, `Heineken` |
| `tapas_cheese` | 4 | `König Ludwig`, `Weissbier` |
| **all 8 others** | **0** | — |

Zero text on every unpackaged-food image, 29 lines on the grocery shelf. OCR
is **self-gating**: it fires only when packaging is present, so it can run
unconditionally without polluting results for loose produce. 30 languages are
supported at `.accurate` on this machine, including Cyrillic and CJK.

### Non-accuracy comparison

| | YOLO-World | YOLO11n | Apple Vision | Apple FM | External VLM |
|---|---|---|---|---|---|
| Bounding boxes | **Yes** | **Yes** | No | n/a | Varies |
| Offline | Yes | Yes | Yes | Yes | **No** |
| Binary size | 24 MB | 5.3 MB | **0** | **0** | **0** |
| Latency | ~3 FPS budget | ~3 FPS | ~9 ms † | n/a | 1–5 s |
| Licence | **AGPL-3.0** | **AGPL-3.0** | Apple SDK | Apple SDK | Commercial |
| Hardware gate | None | None | None | Apple Intelligence | None |
| Image input | Yes | Yes | Yes | **No** | Yes |
| Measured here | Yes | Yes | Yes | n/a | **No** |

† macOS, this machine, median over 11 images, after warm-up. **Not an iPhone
measurement.** Treat as an order of magnitude, not a figure.

Apple Vision scoring better *and* weighing 0 MB *and* having no AGPL
obligation is the most consequential line in this table. It does not replace
YOLO-World — no boxes — but it means the 24 MB model is no longer carrying
the identification work.

---

## 4. Proposed hybrid architecture

Design principle: **YOLO-World answers "where", Apple Vision answers "what",
OCR answers "what brand", and the user answers "is that right".**

```
                    LIVE  (Controller, continuous, unchanged)
  WebRTC frames ──► RemoteVideoFrameTap ──► YOLO-World ──► boxes on screen
                      3 FPS, 1 in flight                   (spatial only)
                                 │
                       user taps "Scan shelf"
                                 ▼
                    CAPTURE  (one high-resolution still)
       request full-res frame over the existing data channel
                                 │
         ┌───────────────────────┼───────────────────────┐
         ▼                       ▼                       ▼
   YOLO-World            VNClassifyImage          VNRecognizeText
   (boxes + terms)       (identity, 1303)         (package labels)
         │                       │                       │
         └───────────┬───────────┘                       │
                     ▼                                   ▼
            IngredientNormalizer                 text → ingredient
          (existing policy, extended)          (deterministic match;
                     │                          Foundation Models to
                     │                          structure it when
                     │                          available, optional)
                     └─────────────┬─────────────────────┘
                                   ▼
                        CONFIDENCE TIERING
              ┌────────────────────┼────────────────────┐
              ▼                    ▼                    ▼
       Tier A: agreed        Tier B: single       Tier C: ambiguous
       both recognisers      one recogniser       generic / low conf
       0 FP measured         ~45-73% prec         "Red Meat", "?"
       pre-ticked            unticked             unticked + flagged
              └────────────────────┼────────────────────┘
                                   ▼
                        HUMAN REVIEW SHEET
                    user confirms / edits / rejects
                                   ▼
                     Pantry write  (NOT IMPLEMENTED)
```

### Why capture a still rather than classify the live frames

- `VNClassifyImageRequest` has no bounding boxes, so there is nothing to draw
  per-frame; running it live would add cost with no visible benefit.
- A still can be full-resolution. Live WebRTC frames are bandwidth-adapted and
  may be 480p during congestion.
- OCR at ~80–400 ms is far too slow for a 3 FPS live budget but entirely fine
  as a one-shot.
- The live path stays exactly as it is today, so this is additive.

### Tiering rules

| Tier | Rule | Measured | UI |
|---|---|---|---|
| **A** | YOLO-World **and** Vision name the same ingredient | 0 FP / 9 (small sample) | Pre-ticked, green |
| **B** | Exactly one names it, above its own threshold | 45–73% precision | Listed, **unticked** |
| **C** | Generic (`red_meat`), or below trust threshold | — | Unticked, `?`, "confirm species" |
| **D** | OCR text matched a product term | unmeasured | Unticked, shows matched text |

Nothing is ever auto-added. Tier A is pre-ticked in a sheet the user still has
to accept — that is a default, not a write.

### What to reuse unchanged

`RemoteVideoFrameTap`, `YOLOFoodDetectionService`, `DetectionGeometry`,
`YOLODetectionOverlay`, `IngredientTaxonomy`, `IngredientNormalizer`,
`IngredientDetectorFactory`, the YOLO11n fallback, and the existing
data-channel photo capture. The hybrid adds recognisers beside them; it
removes nothing.

---

## 5. Minimal migration plan

Deliberately small. Each stage is independently useful and independently
revertible.

### Stage 1 — Apple Vision recogniser behind the existing protocol (~1 day)

Add `AppleVisionIngredientRecognizer` conforming to the existing
`FoodRecognitionService` shape, wrapping `VNClassifyImageRequest` with the
identifier→ingredient map already written and tested in
`tools/vision-eval/score_vision.py`. Port that map into Swift with the same
three-way split (ingredient / wrong-food / ignored-hypernym).

*Exit:* unit tests over the same 11 images reproduce 42.1% / 72.7% in Swift.
If Swift and Python disagree, stop — that is the Vision-vs-PIL preprocessing
question from the last round, and it needs answering before anything is tuned.

### Stage 2 — Capture-and-identify flow (~1–2 days)

A "Scan shelf" button on the Controller that pulls one high-resolution still
through the existing data channel, runs all three recognisers, and shows a
read-only result sheet with the tier labels. No Pantry write.

*Exit:* works end to end on two devices; tiers render correctly.

### Stage 3 — OCR for packaged goods (~1 day)

`VNRecognizeTextRequest` on the same still, deterministic matching against
ingredient terms and a small brand list. Foundation Models used **only** to
structure the matched text, behind an `availability` check with a plain-string
fallback.

*Exit:* `shelf_packaged` yields at least one correct pantry item. Current
pantry recall across all candidates is 0–25%; anything above that is progress.

### Stage 4 — Review sheet (~1–2 days)

Checkbox list, Tier A pre-ticked, edit and reject, "confirm species" for
generics. Still no write — the sheet's confirm action is a no-op stub.

*Exit:* a user can review and correct a full scan.

### Stage 5 — Pantry write (**explicitly out of scope**)

Not in this plan. Wire the sheet's confirm action to the Pantry only on an
explicit decision, after Stages 1–4 have been used on real fridges.

### Decision point after Stage 1

If Apple Vision reproduces its numbers in Swift, **consider whether the 24 MB
YOLO-World model is still worth its weight.** It would then be contributing
bounding boxes and 25% pantry recall, for 24 MB and an AGPL obligation.
Alternatives: keep it (live boxes are a real feature), or drop to YOLO11n for
boxes (5.3 MB, same licence problem), or use
`VNGenerateObjectnessBasedSaliencyImageRequest` for label-free regions and let
Vision do all identification (0 MB, no AGPL).

Not a decision to take now — it depends on Stage 1's result.

### Rollback

Stages 1–4 are additive. Deleting the new files and the "Scan shelf" button
returns to today's behaviour. The live detection path is untouched throughout.

---

## 6. Limitations

1. **11 images.** Every number here comes from the same small set. Treat
   rankings as direction and absolute values as rough. The ordering
   (Vision > YOLO-World) is consistent across all four thresholds, which is
   mildly reassuring; it is not a benchmark.
2. **100% agreement precision is 9 data points.** Do not build anything that
   assumes it holds at scale.
3. **Latency is macOS, not iPhone.** Apple Vision on an A-series chip will
   differ. No device measurement exists.
4. **Vision hallucinates exotic fruit.** On `fruits_mixed` it reports papaya,
   kiwi, lychee, rambutan, durian and mangosteen; visual inspection confirms
   none are present. These are scored as false positives — an earlier version
   of the scorer ignored them, which flattered Vision's precision by ~15
   points. Fixed, and worth remembering: Vision's long tail is unreliable.
5. **Annotation granularity.** `fruits_mixed` visibly contains a cantaloupe
   that the annotation does not list; `melon` and `cantaloupe` are both mapped
   to `watermelon`, which is slightly generous. Annotations were not changed,
   because they are shared with the already-published YOLO-World numbers.
6. **No external VLM was measured** — see §2.
7. **Apple Intelligence hardware eligibility is unverified**, taken from
   Apple's published requirements.
8. **OCR→ingredient matching is unmeasured.** OCR *finds text* reliably
   (29 lines on a packed shelf); turning that text into correct ingredients is
   Stage 3's job and has no numbers yet.
9. **The AGPL question from the last round is still open** and is unaffected
   by any of this, unless YOLO-World is dropped entirely.

---

## 7. Reproducing

```bash
# Apple Vision + OCR over the evaluation images (macOS, no venv needed)
cd tools/vision-eval
swiftc -O classify.swift -o classify
./classify ../yolo-export/eval/images > vision_results.json
python3 score_vision.py --report results_apple_vision.json

# All candidates side by side, including the hybrid rules
source ../yolo-export/.venv/bin/activate
python compare_candidates.py

# Vision's full 1303-class taxonomy
swiftc -O taxonomy.swift -o taxonomy && ./taxonomy > vision_taxonomy.txt
```

Committed evidence: `vision_results.json` (raw output),
`results_apple_vision.json`, `results_comparison.json`, `vision_taxonomy.txt`.
