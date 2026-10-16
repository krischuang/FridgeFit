#!/usr/bin/env python3
"""
Export YOLO-World v2 (small) to Core ML with FridgeFit's ingredient vocabulary.

Uses the official Ultralytics pretrained open-vocabulary checkpoint - nothing
is trained or fine-tuned. `set_classes` bakes CLIP text embeddings for our
vocabulary into the weights, after which the text encoder is dropped and what
remains is an ordinary fixed-class detector that Vision can decode.

The vocabulary is read from `ingredient_vocabulary.json`, which the iOS app
bundles as well. One file, one ordering, so Core ML class indices and the
app's taxonomy cannot drift apart.

    ./setup.sh                      # venv + deps + this script
    python export_ingredient_detector.py --vocabulary ingredient_vocabulary.json

IMPORTANT: the vocabulary is fixed at export time. Changing the terms means
re-running this and shipping a new model; it cannot be changed at runtime.
"""

import argparse
import json
import shutil
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_VOCAB = Path(__file__).resolve().parent / "ingredient_vocabulary.json"
DEFAULT_DEST = REPO_ROOT / "FridgeFit" / "Resources" / "FridgeFitIngredients.mlpackage"
# The app reads the same file to build its taxonomy.
DEFAULT_VOCAB_DEST = REPO_ROOT / "FridgeFit" / "Resources" / "ingredient_vocabulary.json"


def load_vocabulary(path: Path):
    doc = json.loads(path.read_text())
    terms = [entry["term"] for entry in doc["terms"]]
    if len(terms) != len(set(terms)):
        raise SystemExit("error: vocabulary contains duplicate terms")
    return doc, terms


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vocabulary", type=Path, default=DEFAULT_VOCAB)
    parser.add_argument("--weights", default=None,
                        help="Ultralytics checkpoint; defaults to the vocabulary's `model` field.")
    parser.add_argument("--imgsz", type=int, default=None)
    parser.add_argument("--destination", type=Path, default=DEFAULT_DEST)
    parser.add_argument("--skip-install", action="store_true",
                        help="Do not copy the result into the app bundle (for experiments).")
    args = parser.parse_args()

    import torch
    from ultralytics import YOLOWorld

    doc, terms = load_vocabulary(args.vocabulary)
    weights = args.weights or f"{doc['model']}.pt"
    imgsz = args.imgsz or doc.get("imageSize", 640)

    print(f"Vocabulary : {args.vocabulary.name} ({len(terms)} terms, version {doc['version']})")
    print(f"Weights    : {weights} (pretrained, not fine-tuned)")
    print(f"Input size : {imgsz}")

    # `set_classes` must run under no_grad, and the model has to be saved
    # afterwards so the baked-in embeddings survive into the export.
    with torch.no_grad():
        model = YOLOWorld(weights)
        model.set_classes(terms)
        staged = Path(f"_staged_{args.vocabulary.stem}.pt")
        model.save(str(staged))

    exported = Path(YOLOWorld(str(staged)).export(format="coreml", nms=True, imgsz=imgsz))
    size_mb = sum(f.stat().st_size for f in exported.rglob("*") if f.is_file()) / 1e6
    print(f"Exported   : {exported} ({size_mb:.1f} MB)")

    # Report what the app will see, and check the ordering survived.
    import coremltools as ct

    mlmodel = ct.models.MLModel(str(exported))
    spec = mlmodel.get_spec()
    outputs = [o.name for o in spec.description.output]
    print(f"Outputs    : {outputs}")
    if set(outputs) != {"confidence", "coordinates"}:
        raise SystemExit(f"error: expected a Vision-decodable detector, got {outputs}")

    import ast
    names = ast.literal_eval(mlmodel.user_defined_metadata["names"])
    ordered = [names[k] for k in sorted(names, key=int)]
    if ordered != terms:
        raise SystemExit(
            "error: Core ML class order does not match the vocabulary.\n"
            f"  first mismatch at {next(i for i,(a,b) in enumerate(zip(ordered, terms)) if a != b)}"
        )
    print(f"Order      : verified, {len(ordered)} classes match the vocabulary exactly")

    if args.skip_install:
        print("Skipping install (--skip-install).")
        return 0

    args.destination.parent.mkdir(parents=True, exist_ok=True)
    if args.destination.exists():
        shutil.rmtree(args.destination)
    shutil.copytree(exported, args.destination)
    shutil.copyfile(args.vocabulary, DEFAULT_VOCAB_DEST)
    print(f"Installed  : {args.destination}")
    print(f"             {DEFAULT_VOCAB_DEST}")
    print("\nNow run verify_parity.py before shipping - a Core ML export can have")
    print("correct boxes and scrambled labels, and only parity testing catches it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
