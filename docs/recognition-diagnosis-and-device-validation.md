# Recognition Diagnosis, Video Debugging and Device Validation

Two reported problems — a blank grey video preview, and eggs being recognised
as oranges — investigated with the real models and real photographs.

- **Date:** 14 October 2026
- **Tests:** 703 passing, 4 expected skips, Debug and Release device builds clean
- **Physical-device testing:** still none (§6)

---

## 1. Where the "orange" comes from

Traced per stage with the shipped models, using the new `explain` mode of the
Mac Catalyst harness (`tools/vision-eval/swift-harness`). Every number below
is real output from the app's own code.

### `eggs_carton.jpg` — expected `egg`, `egg_carton`

| Stage | Output |
|---|---|
| **1. YOLO-World raw** | `orange 0.827`, `orange 0.732`, `orange 0.720`, `apple 0.439`, `apple 0.437`, `apple 0.421` |
| **2. After normalisation** | three `orange` **with `review=none`**, three `apple` flagged `lowConfidence` |
| **3. Apple Vision full-image** | **`egg_carton 0.963`** (raw identifier `carton`) — **correct** |
| **4. Apple Vision per-crop** | mostly nothing; `kiwi 0.118`, `egg_carton 0.372` |
| **5. Fusion** | 3× `orange` singleSource, 2× `apple` singleSource, 1× `egg_carton` conflicting |
| **6. OCR** | no text |

**The orange originates entirely in YOLO-World.** Apple Vision gets this image
*right*, with high confidence, and is outvoted by six detector boxes.

This is not a mapping bug. `orange` is a legitimate vocabulary term, the boxes
sit on the actual eggs (6 eggs, 6 boxes), and the Core ML export is
parity-verified against PyTorch. The model genuinely cannot tell an egg from
a small orange sphere — which is exactly what the Stage 1 research recorded
("a carton of eggs → `orange` 0.73") and what the per-category measurement
has said all along: **0% recall on dairy/eggs**.

### Two more images, for context

| Image | YOLO-World | Apple Vision |
|---|---|---|
| `beef_raw` | `kitchen knife 0.940` (decoy ✓), **`bread loaf 0.929`** → shown as `Bread Loaf`, `review=none` | `red_meat 0.122` — correct, far too low to use |
| `chicken_raw` | `plate 0.932` (decoy ✓), `kitchen knife 0.890` (decoy ✓), `carrot 0.428` | `red_meat` only, very low |

The decoy mechanism is working — plates and knives are absorbed as intended.
The failure is narrower than "recognition is poor": **where no decoy fits,
YOLO-World emits a confident food label for food it was never able to
recognise.**

### Why it is presented as certain

`IngredientNormalizer` marks anything above `trustThreshold` (0.60) as
needing no review. That threshold had never been validated against outcomes,
so it was measured (`harness … bands`):

| Confidence band | right | wrong | precision |
|---|---|---|---|
| 0.40–0.50 | 5 | 5 | 50.0% |
| 0.50–0.60 | 8 | 5 | 61.5% |
| 0.60–0.70 | 7 | 3 | 70.0% |
| 0.70–0.80 | 9 | 4 | 69.2% |
| 0.80–1.00 | 12 | 2 | 85.7% |

| Bucket | precision |
|---|---|
| marked "no review needed" (≥ 0.60) | **75.7%** (28 right, 9 wrong) |
| marked "please confirm" (< 0.60) | 56.5% (13 right, 10 wrong) |

Confidence *is* informative — the bands rise monotonically — so the threshold
is not nonsense. But **"no review needed" is wrong about one time in four**,
and the egg carton sits in the best band (0.80+) and is still wrong.

**Recommendation, not applied here:** stop labelling any single-detector claim
as needing no review. The live overlay is the only place this surfaces — the
review sheet already requires review for everything single-source, and the
pantry already refuses anything unticked, so no incorrect ingredient can reach
storage from this. Changing it is a policy decision with user-visible effect
and a wide test blast radius; it is flagged rather than taken unilaterally.

**No egg→orange mapping was added**, and none should be. The model is wrong
about a whole category, not about one pair of labels; a lookup would hide the
symptom on one image and leave the other 92 ingredient terms unguarded.

---

## 2. The grey video preview — what is now instrumented

### What was ruled out, with evidence

- **Apple Vision.** The classifier runs on the captured still, never on the
  live track, and never touches the renderer.
- **The detection overlay covering the video.** `YOLODetectionOverlay` draws
  strokes and labels inside a `GeometryReader`; the only `Color.black` in that
  file is inside a `#Preview`.
- **`RTCMTLVideoView` being unsupported in the Simulator.** Tested directly:
  Metal device present, the view builds its `MTKView`, `renderFrame` does not
  crash. Not confirmed, so not asserted.

### What "Video live" actually means

`isReceivingVideo` ← `videoConfirmed` ← `firstRemoteFrameRendered` ←
`FirstFrameSentinel`, an `RTCVideoRenderer` on the remote track. It fires on a
genuinely decoded frame — and then **latches forever**. One frame followed by
silence is indistinguishable from a healthy stream.

### The two counters, and what they distinguish

Reproducing this needs two iPhones, which are not available (§6). So rather
than guess, the Controller now reports **both** halves of the path:

```
Frames received: 142 (47 analysed, 95 skipped)          ← RemoteVideoFrameTap
Drawn: 138 frames · 720x1280 rot 90° · view 300x400     ← the on-screen view
```

These are different renderers on the same track, which is the point:

| Observation | Diagnosis | Next step |
|---|---|---|
| Received rising, **Drawn stuck at 0** | The on-screen view was never attached, or is attached to a stale track | Renderer attachment: `WebRTCVideoView.updateUIView`, and the fact that the view is only created *after* `isLive` turns true |
| Both rising, preview still blank | Frames are delivered and not drawn | `view` size in the same line — a zero or tiny view is a layout fault, not a video fault. Then frame dimensions and rotation |
| Received stuck or barely moving | Frames stopped after the first | Track `isEnabled`, sender state, keyframe/PLI, `RTCPeerConnection` stats |
| Neither appears | Detection is off (it pumps the counters) | Enable Food Detection |

`InstrumentedVideoView` subclasses `RTCMTLVideoView` and calls
`super.renderFrame` **first and unconditionally**, so the instrumentation
cannot itself be the reason something fails to draw. It also records the last
frame's dimensions and rotation, and the view's own bounds — the three things
Task 1 asks to check, reported together.

**No WebRTC signalling, SDP, ICE or Firestore rule was changed.** Nothing in
the evidence points at any of them.

---

## 3. Single-iPhone recognition validation (new)

The remote-camera flow needs two iPhones, which made the thing most in need of
device testing — whether Apple Vision works on hardware — the hardest to
reach. There is now a path that needs one device and no network.

**Remote Camera → "Analyse a photo from this iPhone" → Choose Photo.**

Available both with no connection (under the camera list) and during a live
session. It runs the identical pipeline: the same YOLO-World model, the same
`AppleVisionIngredientClassifier`, the same `DetectionFusionService`, the same
review sheet, the same pantry save. Nothing is stubbed and the result is not
marked differently — a photo is a photo.

Covered by `LocalImageAnalysisTests` (8 tests): the real pipeline runs, the
photo becomes the displayed snapshot, a second photo invalidates the first
result, it works with no session, the result records which recognisers ran,
an undecodable photo is reported, and overlapping requests do not run twice.

---

## 4. Diagnostics and how to capture them

All logging is `OSLog` under subsystem `com.Fridge.FridgeFit`. Every
interpolated value is a count, a duration, an enum case or a framework error
string — **no image data, no ingredient names, no user or device identifiers.**

| Category | Line | Carries |
|---|---|---|
| `YOLO` | `MODEL stage=load …` | model name, load ms, threshold, class count, or the Core ML error |
| `VisionClassifier` | `CAPABILITY probe=… probeMs=…` | the probed capability and how long it took |
| `RemoteCamera` | `VIDEO stage=firstFrame result=ok` | first decoded frame |
| `RemoteCamera` | `CAPTURE stage=complete …` | payload bytes and round-trip ms |
| `SnapshotAnalysis` | `ANALYSIS stage=complete …` | per-stage ms (detect/scene/crop/ocr), capability, box counts, tier counts, region attempts and failures, text lines, failure messages |
| `SnapshotAnalysis` | `ANALYSIS stage=detect\|classify\|ocr result=failed` | which stage failed, and the error |

### Running on a physical iPhone

1. **Trust and signing.** Xcode → FridgeFit target → Signing & Capabilities →
   select your team. On the phone: Settings → General → VPN & Device
   Management → trust the developer certificate.
2. **Install.** Connect by cable, choose the device in Xcode's destination
   menu, ⌘R. Or `xcodebuild -scheme FridgeFit -configuration Release
   -destination 'platform=iOS,name=<device>' -allowProvisioningUpdates build`.
3. **Capture logs while it runs** — from the Mac, with the device connected:

   ```bash
   # Live, filtered to this app's instrumentation
   log stream --device --predicate 'subsystem == "com.Fridge.FridgeFit"' --style compact

   # Just the pipeline stages
   log stream --device --predicate \
     'subsystem == "com.Fridge.FridgeFit" AND (category == "SnapshotAnalysis" OR category == "VisionClassifier" OR category == "YOLO")'

   # After the fact, last 30 minutes, to a file
   log collect --device --last 30m --output fridgefit.logarchive
   ```

   Console.app (Window → Devices) shows the same stream with a filter field.

4. **The first thing to look for** is one line:

   ```
   CAPABILITY probe=available probeMs=12 vocabulary=91
   ```

   `probe=available` on a device is the single most important unverified fact
   in this project (§6). If it reports `failed(...)`, that is a real finding
   and the UI will now say so rather than degrading silently.

---

## 5. Status of each reported problem

### Confirmed fixes

- **Simulator analysis no longer fails outright.** The classifier error used
  to propagate and discard already-computed YOLO results; it now degrades to
  YOLO-only. (Previous round; 15 tests.)
- **Region-classification failures are no longer swallowed** into a log line;
  they are counted and surfaced as "N of M regions failed".
- **A platform limitation and a real fault are distinguishable**, and reported
  differently.
- **Single-iPhone validation path added**, removing the two-device blocker for
  device testing of Apple Vision.

### Diagnosed but unresolved

- **The grey preview.** Instrumented on both halves of the render path with a
  decision table (§2), but **not reproduced and not fixed** — it needs two
  devices. The instrumentation is the deliverable, not a fix.

### Model quality limitations (not defects)

- **Eggs → oranges originates in YOLO-World**, confirmed per stage. Apple
  Vision gets that image right and is outvoted. Consistent with the
  long-standing measurement of **0% recall on meat, seafood and dairy**.
- **Raw beef → `bread loaf 0.929`**, presented as needing no review.
- **"No review needed" is only 75.7% precise.** Confidence is informative but
  the top band is still 85.7%, and the egg carton is in it. Recommendation in
  §1; deliberately not applied unilaterally.
- Overall hybrid precision remains **56.4%**, which is why human confirmation
  is mandatory and why nothing reaches the pantry unticked.

---

## 6. Requires physical iPhone hardware

**No compatible devices are connected, so none of this has been done.**

```
$ xcrun devicectl list devices
K's Apple Vision Pro   …   unavailable
iPhone                 …   unavailable   iPhone 15 Pro
```

**No claim of iOS device validation is made anywhere in this repository.**

### Needs one iPhone (now unblocked by §3)

- [ ] `CAPABILITY probe=available` — Apple Vision running on hardware **at
      all**, for the first time
- [ ] Analyse a photo of eggs: confirm Apple Vision reports `egg_carton` and
      YOLO-World reports `orange`, matching §1 on device
- [ ] Whether the hybrid actually beats YOLO-only on device — the premise of
      the whole design
- [ ] Classification latency, memory and thermals on an A-series chip
- [ ] Review, correct, and save to the pantry; confirm items appear in Pantry
- [ ] `ANALYSIS stage=complete` timings for a real photo

### Needs two iPhones

- [ ] The grey preview: read both counters and follow §2's table
- [ ] Live YOLO boxes aligned over real video, in both orientations
- [ ] Capture round-trip duration from `CAPTURE stage=complete`
- [ ] Disconnect/reconnect, and a second capture during analysis

Record results here under a new "On-device measurements" heading. Until that
section exists, device behaviour is unverified and should be described that
way.
