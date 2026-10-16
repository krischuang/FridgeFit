#!/usr/bin/env python3
"""Score Apple's built-in Vision classifier against the shared annotation set.

Uses exactly the metric from ``tools/yolo-export/evaluate_vocabulary.py`` so
the numbers are directly comparable to the YOLO-World and YOLO11n results:

    recall    = |expected & detected| / |expected|     (per image, set based)
    precision = found / (found + falsePositives)
    falsePos  = |detected - expected|

The only addition is a three-way split of Vision's taxonomy, which is
necessary because ``VNClassifyImageRequest`` returns a *hierarchical,
multi-label* result rather than a flat list of object classes:

  INGREDIENT  a concrete ingredient claim. Credited when it is in the
              annotation, penalised as a false positive when it is not.
  WRONG_FOOD  a concrete food claim that is not in our ingredient vocabulary
              at all ("brownie", "guacamole"). Always penalised - these are
              exactly the confident-but-wrong answers we care about.
  IGNORED     hypernyms and scene labels ("food", "fruit", "structure",
              "tableware", "plate", "people"). Neither credited nor
              penalised. These are not ingredient claims, and scoring them
              would be meaningless in both directions. This is the direct
              analogue of the decoy terms in the YOLO-World vocabulary.

Any identifier not listed below is treated as IGNORED and reported in the
``unmapped`` section, so nothing is silently discarded.
"""

from __future__ import annotations

import argparse
import collections
import json
import pathlib
import sys

# The mapping lives in vision_ingredient_map.json, which is also bundled into
# the app as FridgeFit/Resources/vision_ingredient_map.json and parsed by
# VisionIngredientMap.swift. One file, both consumers - so Swift and Python can
# never disagree about what "meat" means.
#
# Generic-to-generic mappings are deliberate and conservative: Vision's "meat"
# maps to our own generic "red_meat" and NOT to "chicken", because a hypernym
# must not be read as a species claim. Those entries carry requiresReview.
_MAP = json.loads((pathlib.Path(__file__).parent / "vision_ingredient_map.json").read_text())
INGREDIENT = {e["identifier"]: e["ingredient"] for e in _MAP["ingredients"]}
WRONG_FOOD = set(_MAP["wrongFood"])
IGNORED = set(_MAP["ignored"])


def main() -> int:
    here = pathlib.Path(__file__).parent
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", default=str(here / "vision_results.json"))
    parser.add_argument(
        "--annotations",
        default=str(here.parent / "yolo-export" / "eval" / "annotations.json"),
    )
    parser.add_argument(
        "--thresholds", nargs="+", type=float,
        default=[0.10, 0.20, 0.30, 0.40],
    )
    parser.add_argument("--report")
    args = parser.parse_args()

    results = json.loads(pathlib.Path(args.results).read_text())
    annotations = json.loads(pathlib.Path(args.annotations).read_text())

    unmapped: collections.Counter[str] = collections.Counter()
    for image in results.values():
        for det in image["classifications"]:
            name = det["identifier"]
            if name not in INGREDIENT and name not in WRONG_FOOD and name not in IGNORED:
                unmapped[name] += 1

    report = {"candidate": "apple-vision-classify", "thresholds": {}}

    for threshold in args.thresholds:
        per_cat = collections.defaultdict(
            lambda: {"expected": 0, "found": 0, "fp": 0, "detections": 0}
        )
        fp_examples = collections.defaultdict(list)
        hits = collections.defaultdict(list)

        for name, annotation in annotations.items():
            image = results.get(name)
            if image is None:
                continue

            detected, wrong = set(), set()
            for det in image["classifications"]:
                if det["confidence"] < threshold:
                    continue
                ident = det["identifier"]
                if ident in INGREDIENT:
                    detected.add(INGREDIENT[ident])
                elif ident in WRONG_FOOD:
                    wrong.add(ident)

            expected = set(annotation["present"])
            category = annotation["category"]
            found = expected & detected
            spurious = (detected - expected) | wrong

            per_cat[category]["expected"] += len(expected)
            per_cat[category]["found"] += len(found)
            per_cat[category]["fp"] += len(spurious)
            per_cat[category]["detections"] += len(detected)
            for item in sorted(found):
                hits[category].append(f"{name}:{item}")
            for item in sorted(spurious)[:3]:
                fp_examples[category].append(f"{name}:{item}")

        print(f"\n  threshold {threshold:.2f}")
        print(f"    {'category':11} {'recall':>14} {'unique dets':>12} {'false pos':>10}")
        totals = {"expected": 0, "found": 0, "fp": 0}
        rows = {}
        for category in ("fruit", "vegetable", "meat", "seafood", "dairy", "pantry"):
            stats = per_cat.get(category)
            if not stats:
                continue
            recall = stats["found"] / stats["expected"] if stats["expected"] else 0.0
            print(f"    {category:11} {stats['found']:3d}/{stats['expected']:<3d} "
                  f"({recall*100:5.1f}%) {stats['detections']:12d} {stats['fp']:10d}")
            rows[category] = {"recall": round(recall, 3), **stats,
                              "hits": hits[category]}
            for key in totals:
                totals[key] += stats[key]

        overall = totals["found"] / totals["expected"] if totals["expected"] else 0.0
        precision = (totals["found"] / (totals["found"] + totals["fp"])
                     if (totals["found"] + totals["fp"]) else 0.0)
        print(f"    {'OVERALL':11} {totals['found']:3d}/{totals['expected']:<3d} "
              f"({overall*100:5.1f}%) {'':12} {totals['fp']:10d}   "
              f"precision {precision*100:.1f}%")
        report["thresholds"][f"{threshold:.2f}"] = {
            "perCategory": rows, "overallRecall": round(overall, 3),
            "precision": round(precision, 3), "falsePositives": totals["fp"],
            "falsePositiveExamples": {k: v[:6] for k, v in fp_examples.items()},
        }

    latency = [(v["classifyMs"], v["ocrMs"]) for v in results.values()]
    classify_ms = sorted(x[0] for x in latency)
    ocr_ms = sorted(x[1] for x in latency)
    median = lambda xs: xs[len(xs) // 2]
    print(f"\n  latency (macOS, this machine): classify median {median(classify_ms):.1f} ms "
          f"(max {classify_ms[-1]:.1f}), OCR median {median(ocr_ms):.1f} ms (max {ocr_ms[-1]:.1f})")
    report["latencyMs"] = {
        "classifyMedian": round(median(classify_ms), 1),
        "classifyMax": round(classify_ms[-1], 1),
        "ocrMedian": round(median(ocr_ms), 1),
        "ocrMax": round(ocr_ms[-1], 1),
    }

    ocr_hits = {k: len(v["ocrLines"]) for k, v in results.items() if v["ocrLines"]}
    print(f"  OCR produced text on {len(ocr_hits)}/{len(results)} images: {ocr_hits}")
    report["ocrLineCounts"] = ocr_hits

    if unmapped:
        print(f"\n  unmapped identifiers (treated as IGNORED): {dict(unmapped)}")
        report["unmapped"] = dict(unmapped)

    if args.report:
        pathlib.Path(args.report).write_text(json.dumps(report, indent=2))
        print(f"\n  wrote {args.report}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
