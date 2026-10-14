#!/bin/bash
#
# Builds the Swift evaluation harness from the real app sources.
#
# Target is Mac Catalyst, not macOS: the recogniser files import UIKit, and
# Catalyst provides it alongside a Vision classifier that actually runs.
# `VNClassifyImageRequest` fails in the iOS simulator with "Failed to create
# espresso context", which is why the XCTest suite skips those tests and this
# harness exists.
#
# Run from the repository root:
#   ./tools/vision-eval/swift-harness/build.sh && ./tools/vision-eval/swift-harness/harness \
#       FridgeFit/Resources tools/yolo-export/eval/images tools/yolo-export/eval/annotations.json

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HERE="$ROOT/tools/vision-eval/swift-harness"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

# Every file below is the app's own source. Nothing is duplicated; Shim.swift
# supplies one unrelated enum (IngredientCategory) so the pantry domain does
# not have to be dragged in for a single switch.
SOURCES=(
  "$ROOT/FridgeFit/Domain/Models/RemoteCamera/IngredientTaxonomy.swift"
  "$ROOT/FridgeFit/Domain/Models/RemoteCamera/DetectedObject.swift"
  "$ROOT/FridgeFit/Domain/Models/RemoteCamera/DetectedIngredient.swift"
  "$ROOT/FridgeFit/Domain/Models/RemoteCamera/VisionIngredientMap.swift"
  "$ROOT/FridgeFit/Domain/Models/RemoteCamera/FusedIngredient.swift"
  "$ROOT/FridgeFit/Domain/Protocols/IngredientClassifying.swift"
  "$ROOT/FridgeFit/Domain/Protocols/FrameDetecting.swift"
  "$ROOT/FridgeFit/Domain/Errors/YOLODetectionError.swift"
  "$ROOT/FridgeFit/Data/RemoteCamera/AppleVisionIngredientClassifier.swift"
  "$ROOT/FridgeFit/Data/RemoteCamera/DetectionRegionCropper.swift"
  "$ROOT/FridgeFit/Data/RemoteCamera/RegionIngredientClassifier.swift"
  "$ROOT/FridgeFit/Data/RemoteCamera/PackagedFoodTextReader.swift"
  "$ROOT/FridgeFit/Data/RemoteCamera/YOLOFoodDetectionService.swift"
  "$ROOT/FridgeFit/UseCases/IngredientNormalizer.swift"
  "$ROOT/FridgeFit/UseCases/DetectionFusionService.swift"
  "$ROOT/FridgeFit/Data/RemoteCamera/IngredientDetectorFactory.swift"
  "$HERE/Shim.swift"
  "$HERE/main.swift"
)

swiftc -O \
  -target arm64-apple-ios18.0-macabi \
  -sdk "$SDK" \
  -Fsystem "$SDK/System/iOSSupport/System/Library/Frameworks" \
  -I "$SDK/System/iOSSupport/usr/lib/swift" \
  -L "$SDK/System/iOSSupport/usr/lib/swift" \
  "${SOURCES[@]}" \
  -o "$HERE/harness"

echo "built $HERE/harness"
