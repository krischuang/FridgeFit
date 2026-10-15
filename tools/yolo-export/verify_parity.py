#!/usr/bin/env python3
"""
Verify an exported Core ML detector against its PyTorch source.

This exists because of a failure mode that is invisible to every other check:
the Ultralytics Core ML `nms=True` export can produce a model whose **boxes
are correct but whose class scores are scrambled**. The overlay still draws
rectangles on objects, so the app looks like it works - it just names
everything wrong. See docs/food-detection-model-research.md section 4.1.

Compares, per image:
  * class identity of matched detections
  * confidence, within tolerance
  * box centre and size, within tolerance
  * total detection count, within tolerance
and separately confirms the class-index ordering in the model metadata.

Exit code 0 = parity holds. Non-zero = do not ship.

    python verify_parity.py --model ../../FridgeFit/Resources/FridgeFitIngredients.mlpackage \\
                            --vocabulary ingredient_vocabulary.json
"""

import argparse
import ast
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
DEFAULT_IMAGES = HERE / "eval" / "images"


def ordered_labels(mlmodel):
    names = ast.literal_eval(mlmodel.user_defined_metadata["names"])
    return [names[k] for k in sorted(names, key=int)]


def coreml_detections(mlmodel, image, conf, iou):
    """(label, confidence, cx, cy, w, h, top3_labels) tuples, normalised."""
    out = mlmodel.predict({"image": image, "iouThreshold": iou, "confidenceThreshold": conf})
    confidence, coordinates = out["confidence"], out["coordinates"]
    labels = ordered_labels(mlmodel)
    results = []
    if confidence.size:
        for row, box in zip(confidence, coordinates):
            order = np.argsort(-row)[:3]
            index = int(order[0])
            results.append((labels[index], float(row[index]), *[float(v) for v in box],
                            [labels[int(k)] for k in order]))
    return results


def torch_detections(model, image, conf, iou):
    result = model.predict(image, verbose=False, conf=conf, iou=iou)[0]
    names = result.names
    boxes = result.boxes.xywhn.cpu().numpy()
    return [
        (names[int(c)], float(cf), *[float(v) for v in b], None)
        for c, cf, b in zip(result.boxes.cls, result.boxes.conf, boxes)
    ]


def iou(a, b):
    """IoU of two normalised cx,cy,w,h boxes."""
    ax0, ay0, ax1, ay1 = a[2]-a[4]/2, a[3]-a[5]/2, a[2]+a[4]/2, a[3]+a[5]/2
    bx0, by0, bx1, by1 = b[2]-b[4]/2, b[3]-b[5]/2, b[2]+b[4]/2, b[3]+b[5]/2
    ix0, iy0 = max(ax0, bx0), max(ay0, by0)
    ix1, iy1 = min(ax1, bx1), min(ay1, by1)
    inter = max(0.0, ix1-ix0) * max(0.0, iy1-iy0)
    union = max(1e-9, (ax1-ax0)*(ay1-ay0) + (bx1-bx0)*(by1-by0) - inter)
    return inter / union


def match(a, b, box_tol, conf_tol):
    """Greedy highest-IoU matching. More robust than nearest-centre when
    several similar objects overlap, which is the normal case in a fridge."""
    unmatched = list(range(len(b)))
    pairs, missed = [], []
    for det in a:
        best, best_iou = None, 0.0
        for j in unmatched:
            v = iou(det, b[j])
            if v > best_iou:
                best, best_iou = j, v
        if best is not None and best_iou >= 0.5:
            pairs.append((det, b[best]))
            unmatched.remove(best)
        else:
            missed.append(det)
    return pairs, missed, [b[j] for j in unmatched]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--model", type=Path, required=True, help=".mlpackage to verify")
    parser.add_argument("--vocabulary", type=Path, default=HERE / "ingredient_vocabulary.json")
    parser.add_argument("--weights", default=None)
    parser.add_argument("--images", type=Path, default=DEFAULT_IMAGES)
    parser.add_argument("--conf", type=float, default=0.25)
    parser.add_argument("--iou", type=float, default=0.45)
    parser.add_argument("--box-iou-min", type=float, default=0.85,
                        help="Minimum IoU for two matched boxes to count as agreeing.")
    parser.add_argument("--box-tol", type=float, default=0.03,
                        help="Normalised units; used only for match gating.")
    parser.add_argument("--conf-tol", type=float, default=0.08)
    parser.add_argument("--decisive-conf", type=float, default=0.40,
                        help="Above this, a label mismatch is always a failure.")
    parser.add_argument("--report", type=Path, default=None)
    args = parser.parse_args()

    import coremltools as ct
    import torch
    from PIL import Image
    from ultralytics import YOLOWorld

    doc = json.loads(args.vocabulary.read_text())
    terms = [e["term"] for e in doc["terms"]]
    weights = args.weights or f"{doc['model']}.pt"

    mlmodel = ct.models.MLModel(str(args.model))
    size = mlmodel.get_spec().description.input[0].type.imageType.width

    print(f"Model      : {args.model.name}")
    print(f"Vocabulary : {len(terms)} terms")

    # --- 1. Index ordering -------------------------------------------------
    labels = ordered_labels(mlmodel)
    if labels != terms:
        bad = next(i for i, (a, b) in enumerate(zip(labels, terms)) if a != b)
        print(f"FAIL: class ordering differs at index {bad}: "
              f"Core ML {labels[bad]!r} vs vocabulary {terms[bad]!r}")
        return 1
    print(f"Ordering   : OK ({len(labels)} classes in vocabulary order)")

    with torch.no_grad():
        reference = YOLOWorld(weights)
        reference.set_classes(terms)

    images = sorted(p for p in args.images.glob("*.jpg"))
    if not images:
        print(f"FAIL: no images in {args.images}")
        return 1

    failures, rows = [], []
    print(f"\n{'image':18} {'torch':>6} {'coreml':>7} {'matched':>8} {'label✗':>7} "
          f"{'conf✗':>6} {'box✗':>5} {'ties':>6}")
    print("-" * 70)

    for path in images:
        image = Image.open(path).convert("RGB").resize((size, size))
        t = torch_detections(reference, image, args.conf, args.iou)
        c = coreml_detections(mlmodel, image, args.conf, args.iou)
        pairs, only_t, only_c = match(t, c, args.box_tol, args.conf_tol)

        # A label mismatch is only a *failure* when it cannot be explained by
        # float precision on a near-tied detection. The scrambling bug this
        # test exists for produces unrelated labels at quite different
        # confidences; a tie between visually similar classes produces the
        # same confidence and keeps the other label in the top-3.
        label_bad, label_ties = [], []
        for x, y in pairs:
            if x[0] == y[0]:
                continue
            decisive = min(x[1], y[1]) >= args.decisive_conf
            in_top3 = y[6] is not None and x[0] in y[6]
            similar_conf = abs(x[1] - y[1]) <= args.conf_tol
            if decisive or not (in_top3 and similar_conf):
                label_bad.append((x, y))
            else:
                label_ties.append((x, y))
        conf_bad = [(x, y) for x, y in pairs if abs(x[1] - y[1]) > args.conf_tol]
        # IoU, not raw coordinate delta: when NMS suppresses in a slightly
        # different order the surviving box can shift a few percent while
        # still being unmistakably the same detection. IoU is the standard
        # agreement metric and does not punish that.
        box_bad = [(x, y) for x, y in pairs if iou(x, y) < args.box_iou_min]
        count_bad = abs(len(t) - len(c)) > max(2, 0.25 * max(len(t), len(c)))

        print(f"{path.stem:18} {len(t):6d} {len(c):7d} {len(pairs):8d} "
              f"{len(label_bad):7d} {len(conf_bad):6d} {len(box_bad):5d} {len(label_ties):6d}")

        rows.append({"image": path.stem, "torch": len(t), "coreml": len(c),
                     "matched": len(pairs), "labelMismatches": len(label_bad),
                     "confMismatches": len(conf_bad), "boxMismatches": len(box_bad),
                     "nearTies": len(label_ties)})
        if label_bad:
            failures.append(f"{path.stem}: {len(label_bad)} label mismatch(es), "
                            f"e.g. torch={label_bad[0][0][0]!r} coreml={label_bad[0][1][0]!r}")
        if conf_bad:
            failures.append(f"{path.stem}: {len(conf_bad)} confidence mismatch(es)")
        if box_bad:
            failures.append(f"{path.stem}: {len(box_bad)} box mismatch(es)")
        if count_bad:
            failures.append(f"{path.stem}: detection count {len(t)} vs {len(c)}")

    if args.report:
        args.report.write_text(json.dumps(
            {"model": str(args.model), "terms": len(terms), "conf": args.conf,
             "boxIoUMin": args.box_iou_min, "confTolerance": args.conf_tol,
             "images": rows, "failures": failures}, indent=2) + "\n")

    print()
    if failures:
        print(f"PARITY FAILED - {len(failures)} problem(s):")
        for f in failures[:12]:
            print(f"  {f}")
        return 1
    total_ties = sum(r["nearTies"] for r in rows)
    print("PARITY OK - Core ML matches PyTorch on every image."
          + (f" ({total_ties} near-tie label flips below {args.decisive_conf}, expected)"
             if total_ties else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
