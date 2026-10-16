#!/usr/bin/env python3
"""
Evaluate a vocabulary against the annotated ingredient images.

**Image-level** evaluation: for each photo we recorded which ingredients are
visibly present, and measure whether the model finds them and what it invents.
This is deliberately not mAP - we have no hand-drawn boxes, and claiming box
level metrics from presence annotations would be dishonest.

Reported per ingredient category:
  recall          expected ingredients that were detected
  false positives ingredients reported that are not in the photo
  precision       detections that correspond to something actually present

Decoy terms (person, plate, knife, …) are never counted as ingredients; they
exist so non-food objects have somewhere to go instead of being forced into a
food class. `--count-decoys` reports how often they absorbed something.

    python evaluate_vocabulary.py --model M.mlpackage --vocabulary V.json
"""

import argparse
import ast
import json
from collections import defaultdict
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
EVAL = HERE / "eval"


def load(path):
    return json.loads(Path(path).read_text())


def detect(mlmodel, labels, image, conf, iou):
    out = mlmodel.predict({"image": image, "iouThreshold": iou, "confidenceThreshold": conf})
    confidence, coordinates = out["confidence"], out["coordinates"]
    results = []
    if confidence.size:
        for row, box in zip(confidence, coordinates):
            k = int(row.argmax())
            results.append((labels[k], float(row[k]), [float(v) for v in box]))
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--vocabulary", type=Path, default=HERE / "ingredient_vocabulary.json")
    parser.add_argument("--thresholds", type=float, nargs="+", default=[0.25, 0.30, 0.35, 0.40])
    parser.add_argument("--iou", type=float, default=0.45)
    parser.add_argument("--report", type=Path, default=None)
    parser.add_argument("--label", default=None, help="Name for this variant in the output.")
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

    variant = args.label or args.model.stem
    print(f"\n=== {variant}  ({len(labels)} terms) ===")

    report = {"variant": variant, "terms": len(labels), "thresholds": {}}

    for threshold in args.thresholds:
        per_cat = defaultdict(lambda: {"expected": 0, "found": 0, "fp": 0, "detections": 0})
        decoy_hits = 0
        fp_examples = defaultdict(list)

        for name, ann in annotations.items():
            path = EVAL / "images" / f"{name}.jpg"
            if not path.exists():
                continue
            image = Image.open(path).convert("RGB").resize((size, size))
            raw = detect(mlmodel, labels, image, threshold, args.iou)

            ingredients, decoys = [], 0
            for term, score, _ in raw:
                entry = by_term.get(term)
                if entry is None:
                    continue
                if entry["category"] == "decoy":
                    decoys += 1
                else:
                    ingredients.append(entry["ingredient"])
            decoy_hits += decoys

            expected = set(ann["present"])
            detected = set(ingredients)
            category = ann["category"]

            per_cat[category]["expected"] += len(expected)
            per_cat[category]["found"] += len(expected & detected)
            # Anything named that is not visibly in the photo.
            spurious = detected - expected
            per_cat[category]["fp"] += len(spurious)
            per_cat[category]["detections"] += len(detected)
            for s in sorted(spurious)[:3]:
                fp_examples[category].append(f"{name}:{s}")

        print(f"\n  threshold {threshold:.2f}")
        print(f"    {'category':11} {'recall':>14} {'unique dets':>12} {'false pos':>10}")
        totals = {"expected": 0, "found": 0, "fp": 0}
        rows = {}
        for category in ("fruit", "vegetable", "meat", "seafood", "dairy", "pantry"):
            s = per_cat.get(category)
            if not s:
                continue
            recall = s["found"] / s["expected"] if s["expected"] else 0.0
            print(f"    {category:11} {s['found']:3d}/{s['expected']:<3d} ({recall*100:5.1f}%) "
                  f"{s['detections']:12d} {s['fp']:10d}")
            rows[category] = {"recall": round(recall, 3), **s}
            for key in totals:
                totals[key] += s[key]
        overall = totals["found"] / totals["expected"] if totals["expected"] else 0.0
        precision = (totals["found"] / (totals["found"] + totals["fp"])
                     if (totals["found"] + totals["fp"]) else 0.0)
        print(f"    {'OVERALL':11} {totals['found']:3d}/{totals['expected']:<3d} ({overall*100:5.1f}%) "
              f"{'':12} {totals['fp']:10d}   precision {precision*100:.1f}%  decoys absorbed {decoy_hits}")
        report["thresholds"][str(threshold)] = {
            "perCategory": rows, "overallRecall": round(overall, 3),
            "precision": round(precision, 3), "falsePositives": totals["fp"],
            "decoyAbsorbed": decoy_hits,
            "falsePositiveExamples": {k: v[:6] for k, v in fp_examples.items()},
        }

    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
