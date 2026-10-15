#!/usr/bin/env python3
"""
Threshold sweep over the *display policy*, not over raw model output.

`evaluate_vocabulary.py` measures what the model says. This measures what the
Controller would actually draw, which is a different question: the app drops
decoys, collapses ambiguous classes onto a generic ingredient, suppresses
overlapping boxes and caps the count. A threshold can only be chosen against
the end of that chain.

The policy implemented here mirrors `IngredientNormalizer` /
`DetectionFilterPolicy` term for term. When one changes the other has to, or
the numbers stop describing the app.

**Evaluation is image-level presence**, like the existing harness: the eval set
has recorded which ingredients are visible per photo, not hand-drawn boxes.
Claiming mAP off presence annotations would be dishonest, so:

    TP  displayed ingredient that is in the photo
    FP  displayed ingredient that is not
    FN  ingredient in the photo that nothing displayed

Box counts are reported separately from ingredient identities, because
"how many rectangles are on screen" is the UI question and "how many distinct
ingredients were named" is the accuracy question.

    python sweep_display_policy.py --report experiments/display_sweep.json
"""

import argparse
import ast
import json
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
EVAL = HERE / "eval"
REPO = HERE.parent.parent
# The model and vocabulary the app actually ships, not the staging copies.
INSTALLED_MODEL = REPO / "FridgeFit" / "Resources" / "FridgeFitIngredients.mlpackage"
INSTALLED_VOCAB = REPO / "FridgeFit" / "Resources" / "ingredient_vocabulary.json"

# Mirrors IngredientNormalizer.Configuration / DetectionFilterPolicy.
DUPLICATE_IOU = 0.55       # within one ingredient identity
CROSS_CLASS_IOU = 0.70     # between different ingredient identities
DECOY_IOU = 0.60           # decoy covering a food box
TRUST_THRESHOLD = 0.60     # at or above this, shown without a review flag
MAX_INGREDIENTS = 12
# Boxes any single ingredient identity may occupy in the frame budget. The
# point is not to hide repeats - it is to stop one well-detected ingredient
# consuming every slot and starving the rest out of the overlay.
MAX_BOXES_PER_INGREDIENT = 3
# The model's own NMS, as the app configures the Core ML pipeline.
MODEL_IOU = 0.45


def load(path):
    return json.loads(Path(path).read_text())


# ---------------------------------------------------------------- geometry


def iou(a, b):
    """IoU of two [cx, cy, w, h] boxes, matching CGRect-based IoU in Swift."""
    ax0, ax1 = a[0] - a[2] / 2, a[0] + a[2] / 2
    ay0, ay1 = a[1] - a[3] / 2, a[1] + a[3] / 2
    bx0, bx1 = b[0] - b[2] / 2, b[0] + b[2] / 2
    by0, by1 = b[1] - b[3] / 2, b[1] + b[3] / 2
    ix = max(0.0, min(ax1, bx1) - max(ax0, bx0))
    iy = max(0.0, min(ay1, by1) - max(ay0, by0))
    inter = ix * iy
    union = a[2] * a[3] + b[2] * b[3] - inter
    return inter / union if union > 0 else 0.0


# ---------------------------------------------------------------- inference


def detect(mlmodel, labels, image, conf, model_iou=MODEL_IOU):
    """Raw detections as (term, confidence, box) above `conf`.

    The threshold is handed to the Core ML pipeline rather than applied
    afterwards, because the export applies it *before* its baked-in NMS -
    post-filtering a low-threshold run would let boxes that the app never sees
    suppress boxes that it does.
    """
    out = mlmodel.predict(
        {"image": image, "iouThreshold": model_iou, "confidenceThreshold": conf}
    )
    confidence, coordinates = out["confidence"], out["coordinates"]
    results = []
    if confidence.size:
        for row, box in zip(confidence, coordinates):
            k = int(row.argmax())
            results.append((labels[k], float(row[k]), [float(v) for v in box]))
    return results


# ---------------------------------------------------------------- the policy


def normalize(raw, by_term, display_threshold, *,
              cross_class, decoy_veto, per_ingredient_cap=None):
    """Raw detections -> what the overlay would draw.

    Returns a list of dicts with `ingredient`, `confidence`, `box`,
    `requires_review`, so caller can separate "shown" from "shown as trusted".
    """
    decoys, candidates = [], []
    for term, score, box in raw:
        entry = by_term.get(term)
        if entry is None:
            continue
        if score < display_threshold:
            continue
        if entry["category"] == "decoy":
            decoys.append({"term": term, "confidence": score, "box": box})
            continue
        ambiguous = bool(entry.get("requiresReview"))
        ingredient = (entry.get("genericFallback") or entry["ingredient"]) if ambiguous \
            else entry["ingredient"]
        candidates.append({
            "ingredient": ingredient,
            "term": term,
            "confidence": score,
            "box": box,
            "category": entry["category"],
            # Ambiguous classes are always flagged; otherwise the trust
            # threshold decides.
            "requires_review": ambiguous or score < TRUST_THRESHOLD,
        })

    candidates.sort(key=lambda c: -c["confidence"])

    # A decoy covering the same pixels with more confidence is the model's own
    # statement that the region is not food. Dropping the food box there is a
    # suppression rule, not a relabelling.
    if decoy_veto:
        kept = []
        for c in candidates:
            vetoed = any(
                d["confidence"] > c["confidence"] and iou(d["box"], c["box"]) > DECOY_IOU
                for d in decoys
            )
            if not vetoed:
                kept.append(c)
        candidates = kept

    # Same ingredient, overlapping boxes: one object reported twice by two
    # vocabulary terms that normalise together.
    kept = []
    for c in candidates:
        if any(k["ingredient"] == c["ingredient"] and iou(k["box"], c["box"]) > DUPLICATE_IOU
               for k in kept):
            continue
        kept.append(c)

    # Different ingredients, near-identical boxes: one physical object cannot
    # be two ingredients, so the weaker claim goes. Deliberately a much higher
    # IoU than the same-ingredient rule - a tomato on a lettuce leaf overlaps
    # a lot and is two real things.
    if cross_class:
        survivors = []
        for c in kept:
            if any(s["ingredient"] != c["ingredient"] and iou(s["box"], c["box"]) > CROSS_CLASS_IOU
                   for s in survivors):
                continue
            survivors.append(c)
        kept = survivors

    # The frame budget. A flat top-N by confidence lets one ingredient with
    # many instances take every slot, so a per-ingredient budget is applied
    # first. Mirrors `DetectionDisplayFilter.applyPerIngredientBudget`.
    if per_ingredient_cap is not None:
        seen = defaultdict(int)
        budgeted = []
        for c in kept:
            if seen[c["ingredient"]] >= per_ingredient_cap:
                continue
            seen[c["ingredient"]] += 1
            budgeted.append(c)
        kept = budgeted

    return kept[:MAX_INGREDIENTS], len(decoys)


# ---------------------------------------------------------------- scoring


def score(annotations, per_image, label):
    """Image-level presence metrics over one policy's displayed output."""
    per_cat = defaultdict(lambda: {"expected": 0, "tp": 0, "fp": 0, "fn": 0, "boxes": 0})
    totals = {"expected": 0, "tp": 0, "fp": 0, "fn": 0, "boxes": 0}
    high_conf_errors = []
    fp_examples = defaultdict(list)
    images = 0

    for name, ann in sorted(annotations.items()):
        shown = per_image.get(name)
        if shown is None:
            continue
        images += 1
        expected = set(ann["present"])
        named = {c["ingredient"] for c in shown}
        category = ann["category"]

        tp = len(expected & named)
        fp_set = named - expected
        fn_set = expected - named

        s = per_cat[category]
        s["expected"] += len(expected)
        s["tp"] += tp
        s["fp"] += len(fp_set)
        s["fn"] += len(fn_set)
        s["boxes"] += len(shown)

        for wrong in sorted(fp_set):
            fp_examples[category].append(f"{name}:{wrong}")
            # A wrong claim the UI would present as settled fact - no review
            # flag, no dashed box. These are the expensive errors.
            unflagged = [c for c in shown
                         if c["ingredient"] == wrong and not c["requires_review"]]
            if unflagged:
                best = max(unflagged, key=lambda c: c["confidence"])
                high_conf_errors.append({
                    "image": name,
                    "ingredient": wrong,
                    "term": best["term"],
                    "confidence": round(best["confidence"], 3),
                })

    for s in per_cat.values():
        for key in totals:
            totals[key] += s[key]

    precision = totals["tp"] / (totals["tp"] + totals["fp"]) if (totals["tp"] + totals["fp"]) else 0.0
    recall = totals["tp"] / totals["expected"] if totals["expected"] else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else 0.0

    rows = {}
    for category in ("fruit", "vegetable", "meat", "seafood", "dairy", "pantry"):
        s = per_cat.get(category)
        if not s:
            continue
        rows[category] = {
            "recall": round(s["tp"] / s["expected"], 3) if s["expected"] else 0.0,
            "expected": s["expected"], "tp": s["tp"], "fp": s["fp"], "fn": s["fn"],
            "boxes": s["boxes"],
        }

    return {
        "policy": label,
        "precision": round(precision, 3),
        "recall": round(recall, 3),
        "f1": round(f1, 3),
        "truePositives": totals["tp"],
        "falsePositives": totals["fp"],
        "falseNegatives": totals["fn"],
        "displayedBoxes": totals["boxes"],
        "avgBoxesPerImage": round(totals["boxes"] / images, 2) if images else 0.0,
        "highConfidenceMisclassifications": len(high_conf_errors),
        "highConfidenceExamples": sorted(
            high_conf_errors, key=lambda e: -e["confidence"]
        )[:12],
        "perCategory": rows,
        "falsePositiveExamples": {k: v[:6] for k, v in fp_examples.items()},
        "images": images,
    }


# ---------------------------------------------------------------- driver


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--model", type=Path, default=INSTALLED_MODEL)
    parser.add_argument("--vocabulary", type=Path, default=INSTALLED_VOCAB)
    parser.add_argument("--thresholds", type=float, nargs="+",
                        default=[0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80])
    parser.add_argument("--report", type=Path, default=None)
    args = parser.parse_args()

    import coremltools as ct
    from PIL import Image

    doc = load(args.vocabulary)
    by_term = {e["term"]: e for e in doc["terms"]}
    annotations = load(EVAL / "annotations.json")

    mlmodel = ct.models.MLModel(str(args.model))
    names = ast.literal_eval(mlmodel.user_defined_metadata["names"])
    labels = [names[k] for k in sorted(names, key=int)]
    size = mlmodel.get_spec().description.input[0].type.imageType.width

    images = {}
    for name in annotations:
        path = EVAL / "images" / f"{name}.jpg"
        if path.exists():
            images[name] = Image.open(path).convert("RGB").resize((size, size))

    print(f"\n=== display-policy sweep: {len(labels)} terms, {len(images)} images ===")

    # Policy variants.
    #
    # "before" is the flat top-12-by-confidence cap the app shipped with, so
    # every other row is a measured delta against the thing being replaced.
    # "after" is the shipped policy. The last two are the rules that were
    # measured and *rejected*; they stay in the sweep so the rejection is
    # reproducible rather than asserted.
    variants = {
        "before (flat cap)": dict(cross_class=False, decoy_veto=False),
        "after (box budget)": dict(cross_class=False, decoy_veto=False,
                                   per_ingredient_cap=MAX_BOXES_PER_INGREDIENT),
        "rejected: +crossClassNMS": dict(cross_class=True, decoy_veto=False,
                                         per_ingredient_cap=MAX_BOXES_PER_INGREDIENT),
        "rejected: +decoyVeto": dict(cross_class=False, decoy_veto=True,
                                     per_ingredient_cap=MAX_BOXES_PER_INGREDIENT),
    }

    report = {
        "model": args.model.name,
        "terms": len(labels),
        "imageCount": len(images),
        "modelIoU": MODEL_IOU,
        "policyConstants": {
            "duplicateIoU": DUPLICATE_IOU, "crossClassIoU": CROSS_CLASS_IOU,
            "decoyIoU": DECOY_IOU, "trustThreshold": TRUST_THRESHOLD,
            "maximumIngredients": MAX_INGREDIENTS,
            "maximumBoxesPerIngredient": MAX_BOXES_PER_INGREDIENT,
        },
        "thresholds": {},
    }

    for threshold in args.thresholds:
        raw_by_image = {
            name: detect(mlmodel, labels, image, threshold)
            for name, image in images.items()
        }
        report["thresholds"][f"{threshold:.2f}"] = {}
        print(f"\n  threshold {threshold:.2f}")
        print(f"    {"policy":26} {'P':>6} {'R':>6} {'F1':>6} "
              f"{'TP':>4} {'FP':>4} {'FN':>4} {'box/img':>8} {'hiConfErr':>10}")
        for label, options in variants.items():
            displayed, decoys = {}, 0
            for name, raw in raw_by_image.items():
                shown, hits = normalize(raw, by_term, threshold, **options)
                displayed[name] = shown
                decoys += hits
            result = score(annotations, displayed, label)
            result["decoyHits"] = decoys
            report["thresholds"][f"{threshold:.2f}"][label] = result
            print(f"    {label:26} {result['precision']:6.3f} {result['recall']:6.3f} "
                  f"{result['f1']:6.3f} {result['truePositives']:4d} "
                  f"{result['falsePositives']:4d} {result['falseNegatives']:4d} "
                  f"{result['avgBoxesPerImage']:8.2f} "
                  f"{result['highConfidenceMisclassifications']:10d}")

    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
        print(f"\n  wrote {args.report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
