# Real-Time YOLO Food Detection on the Controller

The Controller iPhone runs a pretrained YOLO11n model over the live WebRTC
video it receives from the Camera iPhone, and draws bounding boxes on the food
it finds — on device, with no network call.

- **Date:** 12 October 2026
- **Model:** YOLO11n (COCO, 80 classes), Ultralytics pretrained weights
- **Runtime:** Core ML + Vision, `computeUnits = .all`
- **Toolchain:** Xcode 26.1, Swift 6.2.1, iOS SDK 26.1, deployment target iOS 26.0

> **Superseded for the model, not the pipeline (13 October 2026).** The
> Controller now runs a 113-term YOLO-World v2 ingredient detector instead of
> COCO YOLO11n — see
> [`general-ingredient-detection.md`](general-ingredient-detection.md).
> Everything in *this* document still describes the live code: the frame tap,
> the 3 FPS throttle, the one-inference-in-flight guard, the Vision request
> setup and the coordinate mapping are all unchanged, and YOLO11n remains the
> tested fallback.

---

## 1. Status

| Item | Result |
|---|---|
| Pretrained YOLO11n exported to Core ML | **Done** — 5.2 MB `.mlpackage`, reproducible script |
| Model bundled and compiled by Xcode | **Done** — `YOLO11n.mlmodelc` (5.3 MB) in the device app |
| Real inference on a known image | **PASS** — detects "orange" at 94%, box in the right place |
| Frame consumer on the live track | **Done** — second `RTCVideoRenderer`, no screenshots |
| Bounding-box overlay | **PASS** — verified by pixel inspection, not just arithmetic |
| Controller UI: toggle, status, count | **Done** |
| Simulator + device builds (Debug & Release) | **PASS** — no new warnings |
| Automated tests | **PASS** — 516 tests, 0 failures, stable over 3 runs |
| **Two physical iPhones, end to end** | **NOT TESTED** — no device available (§10) |

> The live two-device run has **not** been performed. No iPhone is connected
> to this machine (`xcrun devicectl list devices` reports the only paired
> handset as `unavailable`), so nothing is claimed about real streamed video,
> on-device frame rates, thermals or battery. Everything else below was
> actually executed.

---

## 2. Model

### Which model, and where the weights come from

**YOLO11n** — the nano variant, 2.6 M parameters, 6.5 GFLOPs. Chosen because
it is the smallest current-generation YOLO and runs comfortably on the Neural
Engine, leaving the H.264 decode and Metal rendering alone.

Weights are the official Ultralytics release, downloaded by the export script:

```
https://github.com/ultralytics/assets/releases/download/v8.3.0/yolo11n.pt
```

Nothing is trained or fine-tuned. These are stock COCO weights.

### Export

```bash
cd tools/yolo-export
./setup.sh                 # needs Python 3.11 or 3.12
```

Creates a venv, installs pinned dependencies, downloads the checkpoint, and
writes `FridgeFit/Resources/YOLO11n.mlpackage`.

Pinned in `requirements.txt`:

```
ultralytics==8.3.40
coremltools==8.1
torch==2.5.1
torchvision==0.20.1
```

Python 3.11 or 3.12 specifically: torch has no wheels for 3.13/3.14 at this
version. Override with `PYTHON=python3.11 ./setup.sh`.

The export uses `nms=True`, which matters:

```python
model.export(format="coreml", nms=True, imgsz=640)
```

That bakes non-max suppression into the Core ML pipeline and produces the
`confidence` + `coordinates` output pair Vision recognises as an object
detector. Vision then returns `VNRecognizedObjectObservation`s with boxes
already decoded and suppressed. Without it we would get raw `(1, 84, 8400)`
tensors and have to hand-roll anchor decoding and NMS in Swift.

Verified interface of the exported model:

```
input   image: imageType 640x640
input   iouThreshold: double
input   confidenceThreshold: double
output  confidence: multiArray
output  coordinates: multiArray
classes: 80 (all COCO, including the 10 food classes)
```

### Bundling

The `.mlpackage` lives at `FridgeFit/Resources/YOLO11n.mlpackage`. Because the
app target uses a file-system-synchronised group, Xcode picks it up with no
project-file edits and runs its Core ML build rule:

```
CoreMLModelCompile … FridgeFit.app/ … YOLO11n.mlpackage
  → FridgeFit.app/YOLO11n.mlmodelc
```

Confirmed present in the **device** Release build at 5.3 MB. The app loads
`YOLO11n.mlmodelc`; a test asserts the compiled form is what gets found, so a
build-rule regression fails rather than silently falling back.

### Licensing — read this before shipping

Ultralytics YOLO11 and its pretrained weights are **AGPL-3.0**. That is a
strong copyleft licence: distributing an application that includes these
weights can oblige you to release the application's source under AGPL-3.0.
Ultralytics sells a commercial Enterprise licence for closed-source use.

This is fine for coursework, a prototype or an internal demo. **It is not
automatically fine for App Store distribution.** Before shipping, either:

- obtain an Ultralytics Enterprise licence, or
- swap in a permissively-licensed detector (e.g. an Apple-provided Vision
  model, or a model you train yourself on a permissive dataset), or
- release the app under AGPL-3.0.

The COCO *dataset* annotations are CC BY 4.0, which is separate from the
Ultralytics code/weights licence.

Swapping models is a one-line change: `Configuration.modelName`, plus matching
class labels in `COCOFoodClass`.

---

## 3. Frame pipeline

### Where frames come from

```
Camera iPhone                Controller iPhone
──────────────               ─────────────────────────────────────────────
AVCaptureSession             RTCPeerConnection
   │                              │  decoded RTCVideoFrame
   └─ H.264 ──── WebRTC ────►     ├──────────────► RTCMTLVideoView  (draws)
                                  ├──────────────► FirstFrameSentinel
                                  └──────────────► RemoteVideoFrameTap
                                                        │
                                                   (background queue)
                                                        ▼
                                              YOLOFoodDetectionService
                                                   Vision + Core ML
                                                        │
                                                        ▼  @MainActor
                                              RemoteCameraViewModel.detections
                                                        │
                                                        ▼
                                              YOLODetectionOverlay
```

`RemoteVideoFrameTap` is a second `RTCVideoRenderer` attached to the same
`RTCVideoTrack` the video view is drawing — the trick `FirstFrameSentinel`
already used. WebRTC fans each decoded frame out to every attached renderer,
so this costs the video pipeline one extra callback and nothing else.

**Not a screenshot of the SwiftUI view.** Rendering the view to an image would
capture the already-cropped, scaled, composited result, put a full readback on
the main thread every frame, and tie inference to the screen refresh rate.

Nothing in the camera-side capture pipeline, signalling, SDP, ICE or media
transport was touched.

### Keeping the video smooth

`renderFrame` runs on a WebRTC decoder thread, where anything slow stalls
playback. It therefore does almost nothing — two checks under a lock, then
either drop the frame or hand it to a background queue:

| Rule | Behaviour |
|---|---|
| **Throttle** | Frames arriving sooner than 1/3 s after the last *started* inference are dropped. Against 30 FPS video that is nine frames in ten. |
| **One in flight** | If an inference is running, drop. There is no queue, so a slow device falls behind on detections instead of accumulating stale frames. |
| **Newest wins** | Dropped frames are discarded, not buffered, so whatever gets through is the most recent frame. |
| **Priority** | Serial `DispatchQueue` at `.utility` QoS — explicitly below playback. |

The retained `RTCVideoFrame` keeps its pixel buffer alive for the duration of
the inference, so WebRTC cannot recycle it underneath Vision.

Results are delivered to the main actor only at the end, as one
`DetectionFrame`.

### Pixel formats

The fast path is `RTCCVPixelBuffer` → its `CVPixelBuffer`, used in place with
no copy. That is what VideoToolbox's hardware H.264 decoder produces, which is
what two iPhones negotiate.

Software-decoded VP8/VP9 produces an I420 buffer instead, which is **not**
supported: converting it would mean a per-frame colour-space conversion on the
CPU. It is reported as `YOLODetectionError.unsupportedPixelFormat`, once, and
detection switches itself off while video keeps playing. See §9.

### Lifecycle

| Event | What happens |
|---|---|
| Remote track arrives | `adoptRemoteVideoTrack` publishes it and attaches the tap |
| Toggle off | Tap stays attached but idle; detections cleared |
| Toggle on | Resumes without reloading the model or re-attaching |
| Disconnect | Tap cancelled, removed from the track, detections cleared |
| Session ended by peer | Same |
| Reconnect / camera switch | Old tap removed from the old track before the new one is attached |
| Backgrounding | `RemoteCameraView` already stops the session on `scenePhase`, which tears detection down with it |

Cancellation is checked again *after* inference returns, so a result computed
under a session that has since ended is discarded rather than painted over the
next one.

---

## 4. Coordinate mapping

This is the part that decides whether boxes land on objects or merely
somewhere plausible. Three coordinate systems have to be reconciled.

**1. Rotation.** `RTCVideoFrame.rotation` says how far the buffer must be
turned to display upright. That rotation is handed to Vision as a
`CGImagePropertyOrientation`, so Vision's output is already in display space
and the overlay needs no rotation of its own:

| `RTCVideoRotation` | `CGImagePropertyOrientation` | Displayed size |
|---|---|---|
| `_0` | `.up` (1) | w × h |
| `_90` | `.right` (6) | **h × w** |
| `_180` | `.down` (3) | w × h |
| `_270` | `.left` (8) | **h × w** |

**2. Vision → SwiftUI.** Vision normalises to the oriented image with the
origin **bottom-left**; SwiftUI's origin is **top-left**. Hence the flip:

```swift
let flippedY = 1 - boundingBox.maxY
```

`maxY` rather than `minY` — flipping turns the box's top edge into its bottom
edge. Getting this wrong mirrors every box vertically, which looks correct for
a centred object and badly wrong for anything else.

**3. `.scaleAspectFill`.** The video is scaled to *cover* the view and centred,
so it is generally larger than the view with the overflow cropped:

```swift
scale     = max(viewW / srcW, viewH / srcH)
displayed = srcSize * scale
origin    = (viewSize - displayed) / 2        // negative: video starts off-view
rect      = origin + normalisedBox * displayed
```

Scaling the normalised rect onto the view's bounds — the obvious
implementation — is wrong whenever the video and the view differ in aspect
ratio, which is almost always. A dedicated test pins that difference down.

Boxes entirely inside the cropped-away region are dropped; boxes straddling
the edge are clamped.

**Mirroring:** the remote view is never mirrored (only Camera Mode's local
front-camera preview is), so no horizontal flip is applied. Tests assert boxes
are not mirrored in either axis.

### Why `.scaleFill` for the model input

`VNCoreMLRequest.imageCropAndScaleOption = .scaleFill`.

`.scaleFit` letterboxes, which matches YOLO's training preprocessing and is
marginally more accurate — but Vision does not consistently compensate for the
padding when mapping boxes back, so detections land offset from the object.
`.centerCrop` would discard the edges of the frame entirely.

`.scaleFill` stretches to the square input, so a normalised box maps linearly
onto the whole frame and means exactly what the geometry assumes. For a
feature whose entire job is drawing boxes in the right place, that
predictability beats the small accuracy difference.

---

## 5. Supported food classes

COCO has 80 classes and exactly **ten** are edible. All ten are supported:

```
apple · banana · broccoli · cake · carrot · donut · hot dog · orange · pizza · sandwich
```

Everything else the model reports — person, car, bowl, cup, bottle, fork,
dining table — is filtered out before it reaches the UI.

**What is deliberately absent:** milk, eggs, cheese, butter, yoghurt, meat,
lettuce, and most of what is actually in a fridge. The pretrained COCO model
cannot detect them, so the app does not claim to. A test asserts those strings
are *not* treated as food, specifically to stop anyone adding them later
without a model that can back them up.

Tableware is not food. A bowl in a fridge photo is a bowl.

Detecting real fridge contents needs a differently-trained model, which is out
of scope for this iteration. `Configuration.allowedLabels` is the one place to
change.

### Confidence

Default threshold **0.45**, configurable via
`YOLOFoodDetectionService.Configuration`. Applied in Swift on top of the
model's own baked-in NMS threshold (0.25 from the export) — raising it is
always effective; lowering it below 0.25 has no effect because the pipeline
already suppressed those. At most 12 boxes per frame, highest confidence
first.

---

## 6. Files

### Added

| File | Purpose |
|---|---|
| `tools/yolo-export/setup.sh` | Reproducible export entry point |
| `tools/yolo-export/export_yolo11n.py` | Downloads pretrained weights, exports Core ML, reports the interface |
| `tools/yolo-export/requirements.txt` | Pinned dependencies |
| `FridgeFit/Resources/YOLO11n.mlpackage` | The exported model (5.2 MB) |
| `FridgeFit/Domain/Models/RemoteCamera/DetectedObject.swift` | `DetectedObject`, `DetectionFrame`, `DetectionStatus`, `COCOFoodClass` |
| `FridgeFit/Domain/Models/RemoteCamera/DetectionGeometry.swift` | Coordinate mapping and frame orientation |
| `FridgeFit/Domain/Errors/YOLODetectionError.swift` | Detection failure cases |
| `FridgeFit/Domain/Protocols/FrameDetecting.swift` | Detector abstraction, for testing the tap |
| `FridgeFit/Data/RemoteCamera/YOLOFoodDetectionService.swift` | Core ML + Vision inference, filtering |
| `FridgeFit/Data/RemoteCamera/RemoteVideoFrameTap.swift` | `RTCVideoRenderer` frame consumer, throttling, concurrency |
| `FridgeFit/Views/RemoteCamera/YOLODetectionOverlay.swift` | The boxes |

### Modified

| File | Change |
|---|---|
| `FridgeFit/ViewModels/RemoteCameraViewModel.swift` | Detection state, toggle, tap lifecycle; `adoptRemoteVideoTrack` extracted so track handover happens in one place |
| `FridgeFit/Views/RemoteCamera/RemoteCameraView.swift` | Overlay on the video, plus the toggle/status/count row |

Unchanged: all signalling, SDP, ICE, media transport, the Camera-side capture
pipeline, Firebase rules, the Pantry, and the existing Controller navigation.
Capture Photo, Switch Remote Camera, Disconnect and Reconnect all behave
exactly as before.

### Tests added

| Suite | Tests | Covers |
|---|---:|---|
| `YOLOFoodDetectionServiceTests` | 24 | Model loading, **real inference**, class and confidence filtering |
| `RemoteVideoFrameTapTests` | 22 | Throttling, one-in-flight, cancellation, rotation, error handling |
| `YOLODetectionGeometryTests` | 18 | Y-flip, aspect-fill crop, rotation, degenerate input |
| `RemoteCameraDetectionTests` | 16 | Toggle, disconnect/reconnect cleanup, missing-model reporting |
| `YOLODetectionOverlayTests` | 9 | **Pixel-level** box placement, no mirroring |

**516 tests total, 0 failures**, stable over three consecutive runs.

Two pre-existing `WebRTCLoopbackTests` races were also fixed: the data-channel
probe checked the controller's end then sent from the camera, and messages
sent before the far end attached its delegate were dropped. Both only surfaced
once the longer suite changed the timing.

---

## 7. What the tests actually prove

The inference tests run the **real bundled model**, not a stub.

`test_realInferenceFindsAnOrangeInTheKnownImage` renders a 640×640 white image
with a solid orange disc spanning 0.3125–0.6875, runs it through Core ML, and
asserts:

- the label is `orange`, confidence > 0.45 (observed: **94%**)
- the box centre is at (0.5, 0.5) ± 0.08
- the box is 0.375 ± 0.12 on each axis

That last part is what pins the coordinate convention down end to end — if
Vision's output were being misread, the centre would not land in the middle.
The image was chosen after verifying against the Ultralytics checkpoint that
this model reliably calls it an orange, so the expectation is grounded rather
than hopeful.

`YOLODetectionOverlayTests` renders the overlay and inspects pixels: a box
appears at the computed position, nothing appears far from it, and the layout
is not mirrored in either axis.

An end-to-end visual check was also run during development — the real model's
real box drawn over the real image, in a deliberately non-square view to
exercise aspect-fill. The box bounded the orange tightly, labelled
"Orange 94%".

---

## 8. Performance

Measured: nothing, on real hardware. Designed for:

- **~3 FPS inference** against 30 FPS video — roughly nine frames in ten
  dropped before any work is done.
- **YOLO11n at 640×640** is ~6.5 GFLOPs; on an A16/A17-class Neural Engine
  that is single-digit milliseconds. The throttle, not the model, is the
  limiter.
- **Zero-copy input**: the decoded `CVPixelBuffer` goes straight to Vision.
- **One allocation per result**: a `DetectionFrame` of at most 12 boxes.
- **Model loaded once** per view-model, not per session.
- Detections update more slowly than the video, which is explicitly the
  preferred trade — stable playback first.

Unverified on device: actual inference latency, sustained frame rate, thermal
behaviour, battery cost. See §10.

---

## 9. Error handling

| Situation | Behaviour |
|---|---|
| Model missing from the bundle | Status **Unavailable** with "run tools/yolo-export/setup.sh"; video unaffected |
| Model fails to load | Status **Unavailable** with the reason |
| Unsupported pixel format (I420) | Reported once, sampling stops, video keeps playing |
| Frame conversion failure | Logged, frame skipped, tap continues |
| Inference throws | Logged, frame skipped, tap continues |
| **Zero food detected** | **Not an error** — empty overlay, status stays *Detecting* |
| Disconnect | Tap detached, boxes cleared |
| Camera switch / reconnect | Tap moved to the new track, boxes cleared |
| Backgrounding | Session stops, which stops detection |

Terminal failures are reported **once**, not three times a second.
Recoverable ones (a single bad frame) keep the tap alive.

**No mock detections are ever shown.** If the model cannot run, the UI says so
and draws nothing.

---

## 10. Testing on two physical iPhones — NOT YET DONE

No device was available, so these steps have not been executed.

### Prerequisites

1. Firestore rules deployed (done — see `webrtc-remote-camera-testing.md` §4).
2. `tools/yolo-export/setup.sh` run, so the model is in the bundle.
3. Two iPhones on iOS 26.0+, same Firebase account, same Wi-Fi.
4. `LOCAL_DEVELOPMENT_TEAM` set in `Secrets.xcconfig`.

### Steps

1. Run on both devices. Sign in to the same account.
2. **Camera iPhone:** Profile → Connected Devices → **Camera Mode**. Grant
   camera access. Leave the screen open.
3. **Controller iPhone:** Profile → Connected Devices → **Remote Camera**.
   Select the camera. Wait for live video.
4. **Food Detection** is on by default; the indicator should go green and read
   *Detecting*.
5. Point the camera iPhone at a **banana, apple or orange** — the classes this
   model is most reliable on. A green box with the label and confidence should
   appear within roughly a third of a second.

### What to check

| Check | Expected |
|---|---|
| Box alignment | Tight around the object, tracking as it moves |
| Rotation | Rotate the camera iPhone — boxes stay aligned in both orientations |
| Video smoothness | No visible stutter with detection on |
| Toggle off | Boxes vanish immediately, video continues |
| Toggle on | Boxes return |
| Non-food | A person or a cup produces **no** box |
| Capture Photo | Still works; snapshot unaffected by detection |
| Switch Remote Camera | Boxes clear, then resume on the new lens |
| Disconnect | Boxes clear, indicator leaves *Detecting* |
| Reconnect | Detection resumes |
| Background the Controller | Session ends; returning requires reconnect |

### Worth measuring while there

- Inference latency (`com.Fridge.FridgeFit` / `YOLO` in the console)
- Whether 3 FPS feels right, or should be tuned via
  `RemoteVideoFrameTap.defaultMinimumInterval`
- Device temperature and battery over ~10 minutes
- Whether 0.45 is the right threshold in real kitchen lighting

---

## 11. Known limitations

**COCO has ten food classes.** No milk, eggs, cheese, or most real fridge
contents. This is a property of the pretrained weights, not a bug, and the app
is explicit about it rather than guessing.

**AGPL-3.0 weights.** See §2 — relevant before any App Store distribution.

**Software-decoded video is unsupported.** VP8/VP9 yields I420 buffers rather
than `CVPixelBuffer`s. Two iPhones negotiate hardware H.264, so this should
not arise, but if it does the app reports it and keeps playing video. Adding a
conversion path is the fix if it ever matters.

**`.scaleFill` distorts the model input** on non-square frames — a deliberate
trade for exact coordinate mapping (§4). Accuracy on strongly non-square
frames is slightly below a letterboxed pipeline.

**Detections lag the video** by up to a third of a second plus inference time.
Intentional; playback has priority.

**No tracking between frames.** Each frame is detected independently, so boxes
can flicker on marginal detections. A short animation smooths it; proper
tracking (e.g. `VNTrackObjectRequest`) was out of scope.

**Nothing is written to the Pantry.** Detection is display-only, as specified.

**Not measured on hardware.** Latency, frame rate, thermals and battery are
unverified (§10).

**Simulator caveat.** Detection works in the Simulator against a synthetic
track, but there is no camera, so a full two-device run cannot be simulated.
