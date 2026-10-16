#!/usr/bin/env python3
"""Compare every available recogniser on one shared annotation set.

Candidates:
  yolo-world      YOLO-World v2 (small), 113-term vocabulary, Core ML
  yolo11n         The COCO fallback, 10 edible classes
  apple-vision    VNClassifyImageRequest (results from classify.swift)
  hybrid          Union of yolo-world and apple-vision

Metric is identical to tools/yolo-export/evaluate_vocabulary.py:
    recall = |expected & detected| / |expected|, per image, set based.

The hybrid row is the point of this script: the proposal is that YOLO-World
supplies spatial information and Apple Vision supplies identity, so what
matters is whether their union covers more than either alone - and what it
costs in false positives.
"""

from __future__ import annotations

import argparse
import collections
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "yolo-export"))

HERE = pathlib.Path(__file__).resolve().parent
YOLO = HERE.parent / "yolo-export"
EVAL = YOLO / "eval"

from score_vision import INGREDIENT as VISION_MAP, WRONG_FOOD  # noqa: E402

CATEGORIES = ("fruit", "vegetable", "meat", "seafood", "dairy", "pantry")


def load(path):
    return json.loads(pathlib.Path(path).read_text())


def yolo_sets(model_path, vocabulary_path, threshold, iou=0.45):
    """Per-image set of ingredient terms the YOLO model reports."""
    import coremltools as ct
    from PIL import Image

    vocab = load(vocabulary_path)
    terms = vocab["terms"] if isinstance(vocab, dict) else vocab
    by_term = {t["term"]: t for t in terms}
    labels = [t["term"] for t in terms]

    model = ct.models.MLModel(str(model_path))
    out = {}
    for image_path in sorted(EVAL.glob("images/*")):
        if image_path.suffix.lower() not in {".jpg", ".jpeg", ".png"}:
            continue
        image = Image.open(image_path).convert("RGB").resize((640, 640))
        prediction = model.predict(
            {"image": image, "iouThreshold": iou, "confidenceThreshold": threshold}
        )
        confidence, _ = prediction["confidence"], prediction["coordinates"]
        found = set()
        if confidence.size:
            for row in confidence:
                k = int(row.argmax())
                if float(row[k]) < threshold:
                    continue
                entry = by_term.get(labels[k])
                if entry and entry["category"] != "decoy":
                    found.add(entry["ingredient"])
        out[image_path.stem] = found
    return out


def vision_sets(results_path, threshold):
    results = load(results_path)
    out = {}
    for name, image in results.items():
        found = set()
        for det in image["classifications"]:
            if det["confidence"] < threshold:
                continue
            ident = det["identifier"]
            if ident in VISION_MAP:
                found.add(VISION_MAP[ident])
            elif ident in WRONG_FOOD:
                found.add(f"!{ident}")  # concrete but wrong food claim
        out[name] = found
    return out


def score(detected_by_image, annotations, label):
    per_cat = collections.defaultdict(
        lambda: {"expected": 0, "found": 0, "fp": 0}
    )
    for name, annotation in annotations.items():
        detected = detected_by_image.get(name, set())
        expected = set(annotation["present"])
        category = annotation["category"]
        found = expected & detected
        per_cat[category]["expected"] += len(expected)
        per_cat[category]["found"] += len(found)
        per_cat[category]["fp"] += len(detected - expected)

    rows, totals = {}, {"expected": 0, "found": 0, "fp": 0}
    for category in CATEGORIES:
        stats = per_cat.get(category)
        if not stats:
            continue
        rows[category] = (
            stats["found"] / stats["expected"] if stats["expected"] else 0.0
        )
        for key in totals:
            totals[key] += stats[key]
    recall = totals["found"] / totals["expected"] if totals["expected"] else 0.0
    precision = (totals["found"] / (totals["found"] + totals["fp"])
                 if (totals["found"] + totals["fp"]) else 0.0)
    return {
        "label": label, "perCategory": rows, "recall": recall,
        "precision": precision, "found": totals["found"],
        "expected": totals["expected"], "falsePositives": totals["fp"],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--yolo-world", default=str(
        HERE.parent.parent / "FridgeFit/Resources/FridgeFitIngredients.mlpackage"))
    parser.add_argument("--yolo-threshold", type=float, default=0.40)
    parser.add_argument("--vision-threshold", type=float, default=0.30)
    parser.add_argument("--report", default=str(HERE / "results_comparison.json"))
    args = parser.parse_args()

    annotations = load(EVAL / "annotations.json")

    print(f"running yolo-world at {args.yolo_threshold:.2f} ...")
    yolo = yolo_sets(args.yolo_world, YOLO / "ingredient_vocabulary.json",
                     args.yolo_threshold)
    print(f"running apple-vision at {args.vision_threshold:.2f} ...")
    vision = vision_sets(HERE / "vision_results.json", args.vision_threshold)

    hybrid = {k: yolo.get(k, set()) | vision.get(k, set())
              for k in set(yolo) | set(vision)}

    # A permissive Vision pass, to see what recall is available at all.
    vision_lo = vision_sets(HERE / "vision_results.json", 0.10)
    # Agreement: both recognisers independently name the same ingredient.
    agree = {k: yolo.get(k, set()) & vision_lo.get(k, set())
             for k in set(yolo) | set(vision_lo)}

    candidates = [
        score(yolo, annotations, f"yolo-world @{args.yolo_threshold:.2f}"),
        score(vision, annotations, f"apple-vision @{args.vision_threshold:.2f}"),
        score(vision_lo, annotations, "apple-vision @0.10"),
        score(hybrid, annotations, "hybrid union (v@0.30)"),
        score({k: yolo.get(k, set()) | vision_lo.get(k, set())
               for k in set(yolo) | set(vision_lo)},
              annotations, "hybrid union (v@0.10)"),
        score(agree, annotations, "hybrid agreement (AND)"),
    ]

    header = f"{'candidate':26} {'recall':>14} {'prec':>7} {'FP':>4}  " + \
             "  ".join(f"{c[:4]:>5}" for c in CATEGORIES)
    print("\n" + header)
    print("-" * len(header))
    for row in candidates:
        cats = "  ".join(
            f"{row['perCategory'].get(c, 0.0)*100:4.0f}%" for c in CATEGORIES
        )
        print(f"{row['label']:26} {row['found']:3d}/{row['expected']:<3d} "
              f"({row['recall']*100:5.1f}%) {row['precision']*100:6.1f}% "
              f"{row['falsePositives']:4d}  {cats}")

    pathlib.Path(args.report).write_text(json.dumps(
        {"candidates": candidates,
         "perImage": {k: sorted(v) for k, v in hybrid.items()}}, indent=2))
    print(f"\nwrote {args.report}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
