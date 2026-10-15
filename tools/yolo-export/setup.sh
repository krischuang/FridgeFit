#!/usr/bin/env bash
#
# Reproducible YOLO11n -> Core ML export for FridgeFit.
#
#     cd tools/yolo-export && ./setup.sh
#
# Writes FridgeFit/Resources/YOLO11n.mlpackage from the official Ultralytics
# pretrained COCO weights. Nothing is trained or fine-tuned here.
#
# Needs Python 3.11 or 3.12: torch has no wheels for 3.13/3.14 at the pinned
# version. Override with PYTHON=python3.11 ./setup.sh
set -euo pipefail
cd "$(dirname "$0")"

PYTHON="${PYTHON:-python3.12}"

if ! command -v "$PYTHON" >/dev/null 2>&1; then
    echo "error: $PYTHON not found. Install it, or run: PYTHON=python3.11 ./setup.sh" >&2
    exit 1
fi

if [ ! -d .venv ]; then
    echo "Creating venv with $PYTHON ..."
    "$PYTHON" -m venv .venv
fi

# shellcheck disable=SC1091
source .venv/bin/activate

python -m pip install --quiet --upgrade pip
python -m pip install --quiet -r requirements.txt

python export_yolo11n.py "$@"
