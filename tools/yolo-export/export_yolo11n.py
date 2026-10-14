#!/usr/bin/env python3
"""
Export pretrained YOLO11n (COCO) to Core ML for FridgeFit's Controller.

Downloads the official Ultralytics pretrained weights - no training, no
fine-tuning - and exports them to an .mlpackage with NMS baked in, which is
what lets Vision decode the output into VNRecognizedObjectObservation
directly instead of us hand-rolling box decoding.

Usage:  ./setup.sh          (creates the venv and runs this)
"""

import argparse
import shutil
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DESTINATION = REPO_ROOT / "FridgeFit" / "Resources" / "YOLO11n.mlpackage"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--weights", default="yolo11n.pt",
                        help="Pretrained Ultralytics checkpoint (downloaded if absent).")
    parser.add_argument("--imgsz", type=int, default=640,
                        help="Square input size baked into the Core ML model.")
    parser.add_argument("--destination", type=Path, default=DESTINATION)
    args = parser.parse_args()

    from ultralytics import YOLO

    print(f"Loading pretrained weights: {args.weights}")
    model = YOLO(args.weights)

    # nms=True bakes non-max suppression into the Core ML pipeline and emits
    # the `confidence` + `coordinates` output pair Vision recognises as an
    # object detector. Without it we would get raw tensors and have to decode
    # and NMS by hand in Swift.
    print(f"Exporting to Core ML (imgsz={args.imgsz}, nms=True)…")
    exported = Path(model.export(format="coreml", nms=True, imgsz=args.imgsz))
    print(f"Exported: {exported}")

    args.destination.parent.mkdir(parents=True, exist_ok=True)
    if args.destination.exists():
        shutil.rmtree(args.destination)
    shutil.copytree(exported, args.destination)
    print(f"Installed into the app bundle source tree: {args.destination}")

    # Report what the app will actually see at runtime.
    import coremltools as ct

    mlmodel = ct.models.MLModel(str(args.destination))
    spec = mlmodel.get_spec()
    print("\n--- Core ML interface ---")
    for provided in spec.description.input:
        print(f"input  {provided.name}: {provided.type.WhichOneof('Type')}")
    for produced in spec.description.output:
        print(f"output {produced.name}: {produced.type.WhichOneof('Type')}")
    labels = mlmodel.user_defined_metadata.get("classes", "")
    print(f"classes: {len(labels.split(',')) if labels else 'see metadata'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
