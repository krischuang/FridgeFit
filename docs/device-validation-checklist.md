# Physical-Device Validation Checklist

**Nothing in this checklist has been executed.** It exists because every
result so far — 567 unit tests, the parity harness, the evaluation set — was
produced on a simulator or on macOS, and none of it can confirm the things
that only break on real hardware over a real network.

Requires **two physical iPhones** (iOS 26.0+), both signed into the same
FridgeFit account, on the same Wi-Fi to start with.

---

## 0. What has actually been verified (so you know what not to re-test)

| Verified | How | Where |
|---|---|---|
| Both models + vocabulary ship in the device build | Inspected `Release-iphoneos/FridgeFit.app` | `FridgeFitIngredients.mlmodelc` 24 MB, `YOLO11n.mlmodelc` 5.3 MB, `ingredient_vocabulary.json` present |
| Debug and Release device builds compile | `xcodebuild -destination generic/platform=iOS` | exit 0, no new warnings |
| Core ML output matches PyTorch | `verify_parity.py` | 11/11 images, 0 mismatches |
| Class order matches the vocabulary | `IngredientTaxonomyTests` reads `.mlmodelc` metadata | passing |
| Inference, labels and box coordinates | Real model through Vision on a generated frame | `IngredientDetectorFactoryTests` |
| Overlay geometry | `ImageRenderer` pixel assertions | `YOLODetectionOverlayTests` |

**App size is now 65 MB** (from ~41 MB), of which 29 MB is models. Worth
confirming against App Store cellular-download limits before release.

---

## 1. Build and install

- [ ] Release build installs on both devices (`-allowProvisioningUpdates`)
- [ ] First launch does not stall on model load — `MLModel` compilation happens
      at build time (`.mlmodelc`), so this should be fast; if it is not,
      something is recompiling at runtime
- [ ] Confirm on-device storage footprint matches the 65 MB expectation

## 2. Detector selection and fallback

- [ ] Controller status row shows **"YOLO-World"**, not "YOLO11n"
- [ ] No fallback warning banner is visible
- [ ] Category chips appear when produce is in frame
- [ ] Force the fallback (rename the model in a scratch build) and confirm the
      Controller still detects the 10 COCO classes and shows the warning with
      a readable reason — the fallback is tested in the simulator but has
      never run on hardware

## 3. Coordinate alignment — the highest-risk area

This is where simulator testing is least convincing, because the simulator
never produces rotated frames from a real camera. `RemoteVideoFrameTap`
derives `orientedSize` from `frame.width`/`frame.height` plus
`RTCVideoRotation`, so a mismatch shows up as boxes that are offset,
mirrored, or scaled wrongly.

Put a single distinctive object (an orange works) in a known position and
check the box tracks it:

- [ ] Camera device **portrait**, Controller portrait
- [ ] Camera device **landscape left**, then **landscape right** — the most
      likely failure, since this is where `RTCVideoRotation` is non-zero
- [ ] Camera device **upside down**
- [ ] Rotate the Camera device *while streaming* — boxes must re-align within
      a frame or two, not stay stuck in the old orientation
- [ ] Object near each **edge** and each **corner**, not just centre — centre
      bugs hide scale errors
- [ ] Confirm no **mirroring**: move the object right, the box must move right
- [ ] Switch the Camera device to the **front camera** if that path exists —
      front cameras are mirrored and are a classic source of flipped boxes

**Known risk:** `RTCMTLVideoView` renders aspect-fill and `DetectionGeometry`
assumes aspect-fill centre-crop. If WebRTC renegotiates to a different
resolution mid-call (adaptive bitrate does this under congestion), the source
aspect ratio changes. Watch for boxes drifting after a network dip.

- [ ] Deliberately degrade the network (move away from the router) and check
      boxes stay aligned after the stream resolution drops

## 4. Performance and thermals

Nothing below has been measured on an iPhone. The 24 MB model is ~4.6× the
size of YOLO11n, and `computeUnits = .all`.

- [ ] Detection sustains **~3 FPS** (the throttle target) rather than falling
      behind — `RemoteVideoFrameTap.statistics` exposes processed/dropped
- [ ] Video playback stays smooth; the frame tap drops rather than queues, so
      a slow model should degrade detection rate, **not** video
- [ ] Run **10 minutes continuously** and watch for thermal throttling
      (Xcode → Debug navigator → Energy / thermal state)
- [ ] Check memory: only one detector should ever be instantiated — confirm
      both models are not resident simultaneously
- [ ] Battery drain over 10 minutes on the Controller
- [ ] Repeat on the **oldest supported device** available, not just the newest

## 5. Detection quality in the real world

The evaluation set is 11 stock photographs. A fridge interior is different:
poor lighting, occlusion, odd angles, items in packaging.

- [ ] Produce in a real fridge — expect roughly the measured 40–44% recall,
      and confirm it is not dramatically worse under fridge lighting
- [ ] **Confirm the known failures reproduce on device**: raw meat, fish,
      cheese and eggs should either be missed or mislabelled. If they
      suddenly work, the on-device preprocessing differs from the evaluation
      harness and the numbers need redoing
- [ ] Items flagged for review render with the dashed orange box and `?`
- [ ] Ambiguous meat shows **"Red Meat"/"Poultry"**, never a species
- [ ] Decoys (hands, plates, knives) never appear as ingredients
- [ ] An empty fridge shelf produces no boxes

## 6. Threshold re-tuning (expected to be needed)

The 0.40 display threshold was tuned against the Python/PIL preprocessing
path. Vision's `.scaleFill` resampling scores differently — on a synthetic
fixture, coremltools gave 0.537 where Vision gave 0.363 on an identical box.

- [ ] Log raw confidences on device for ~20 real fridge items
- [ ] Compare the distribution against the evaluation-set distribution
- [ ] If on-device scores are systematically lower, re-run the threshold sweep
      against on-device numbers rather than shipping a threshold tuned on the
      wrong preprocessing path

## 7. Regression — the rest of the app

The detection work should not have touched any of this, but it shares a
process:

- [ ] Camera Mode still streams
- [ ] Remote photo capture over the data channel still works
- [ ] Pantry add/edit/delete unaffected
- [ ] Receipt scanning unaffected
- [ ] Sign-in/sign-out unaffected
- [ ] Connected Devices list shows presence correctly

## 8. Record the results

Write measured numbers into `docs/general-ingredient-detection.md` §4 under a
new "On-device measurements" heading. Until that section exists, the honest
status of device performance remains **unverified**, and should be described
that way in any report.
