# Apple Vision in the Simulator — Graceful Degradation

Tapping **Analyse Ingredients** on the iPhone 17 Pro Simulator (iOS 26.1)
showed `Image classification failed: Failed to create espresso context.` and
nothing else. This records what was actually wrong, the fix, and what is still
unverified.

- **Date:** 14 October 2026
- **Tests:** 695 passing, 4 expected skips, Debug and Release device builds clean

---

## 1. Where the error came from, and why it killed everything

`VNClassifyImageRequest` cannot run in the iOS Simulator. That was already
known and documented in
[`hybrid-stage1-results.md`](hybrid-stage1-results.md) §7, verified with a
20-line reproduction containing no FridgeFit code.

What was *not* handled is what that failure did to the rest of the pipeline.
In `SnapshotIngredientAnalyzer.analyze`:

```swift
let raw = try detector.detect(in: image, orientation: orientation)   // 1. succeeded
let detections = normalizer.normalize(raw, source: source)
let regions = regionClassifier.classifyRegions(...)                  // 2. errors swallowed
let scene = try classifier.classify(upright, orientation: .up)       // 3. THREW
let packaging = (try? textReader.read(...)) ?? .empty                // 4. never reached
```

One `try` on line 3 propagated out of the method and discarded:

- the **YOLO detections from step 1, which had already succeeded**
- the OCR in step 4, which was never reached and would have worked

So the user saw an error message instead of the detection results the app had
already computed. The classifier being unavailable is a limitation; throwing
away everything else was the defect.

A second, quieter problem: `RegionIngredientClassifier` caught every per-crop
error and wrote it to the log. On a real device where every crop failed, the
app would have behaved exactly like a device with nothing in frame.

---

## 2. The fix

### A capability state, probed rather than guessed

`ClassificationCapability` has three cases, not two:

| Case | Meaning | Treatment |
|---|---|---|
| `.available` | A probe classification succeeded | Full hybrid pipeline |
| `.unavailableInSimulator(detail)` | Probe failed, and we are in the Simulator | Degrade quietly to YOLO-only |
| `.failed(detail)` | Probe failed where it should have worked | **Report in full** |

The distinction matters in both directions. Collapsing them would either cry
wolf on every simulator run, or silently hide a genuine on-device failure.

Capability is established by **running one 32×32 classification once**, not by
`#if targetEnvironment(simulator)` alone. A compile-time check would be a
guess that stays wrong forever if a future simulator gains support; the probe
notices. The compile-time check is used only to *classify* a failure once it
has happened.

### The classifier refuses rather than returning empty

```swift
guard capability.isAvailable else {
    throw VisionClassificationError.classifierUnavailable(capability)
}
```

An empty result means "looked and found nothing" — a claim about the image.
Unavailability is a claim about the platform. Returning empty would let the UI
report "no ingredients" for a photo nothing ever examined.

### The analyzer degrades instead of aborting

Scene classification is no longer `try`. It is skipped entirely when the
capability is unavailable (so an unsupported platform costs zero Vision
requests rather than one failure per box), and caught when it fails. OCR is
caught separately, because it is a different Vision request that works in the
Simulator and must not be gated on something that does not.

Every analysis now carries a `ClassificationOutcome` recording which
recognisers ran, how many regions were attempted, how many failed, and the
first failure message.

### Nothing is invented

With no classifier there are no region results, so every fused claim is
`.singleSource` with `sources == .detector` and `classifierConfidence == nil`.
`test_noAgreementIsInventedWithoutAClassifier` asserts all of that: zero
agreed, zero conflicting, no confidence attributed to a classifier that never
ran, and every row flagged for review.

### In the UI

- Controller summary: **"Apple Vision classification unavailable in Simulator"**
  plus a **"YOLO-only — every row needs review"** chip, shown *above* the tier
  counts so "2 single" is read in the right light.
- Review sheet: a section headed **"YOLO-only results"** explaining that
  nothing was cross-checked by a second method.
- A limitation uses `info.circle` and secondary colour; a genuine fault uses
  `exclamationmark.triangle.fill` and orange.

Review, editing, manual addition and the Pantry save all work unchanged. No
recognition output is written to the Pantry automatically — single-source rows
are never pre-ticked, so a degraded analysis starts with **nothing** accepted.

---

## 3. What the simulator can now be used for

| | Works in Simulator |
|---|---|
| WebRTC signalling and connection | yes |
| YOLO-World detection (live and on the still) | yes |
| Snapshot capture over the data channel | yes |
| Packaging OCR | yes |
| Ingredient review, editing, manual entry | yes |
| Pantry persistence | yes |
| **Apple Vision classification** | **no — degrades to YOLO-only** |

---

## 4. Tests

`ClassificationCapabilityTests` — 15 tests:

- a simulator limitation is not a fault, and keeps its detail
- a real failure is a fault, and its reason reaches the user
- the probe agrees with what the API actually does here, checked against an
  independent probe rather than against itself
- an unavailable classifier throws rather than returning empty
- a device failure is not downgraded to "unavailable"
- region failures are counted and surfaced, not swallowed
- **the analysis does not throw** — the actual reported bug
- YOLO results survive an unavailable classifier
- no agreement, conflict or confidence is invented
- OCR still runs without the classifier
- an empty detection result is still a valid analysis
- a degraded analysis still supports review, correction and manual addition

The end-to-end tests use `fruits_mixed.jpg` from the bundled evaluation set
rather than a synthetic shape. The synthetic orange disc scores 0.363 through
Vision — below the shipped 0.40 display threshold — so the production
normaliser correctly filters it out, and a test using it would be measuring
the fixture rather than the fix.

---

## 5. The grey video preview — investigated, not solved

Reported separately: the Controller shows **Connected** and **Video live** but
no visible video.

### What "Video live" actually means

`isReceivingVideo` is set from `WebRTCSessionCoordinator.Event.videoConfirmed`,
which is emitted from `PeerConnectionEvent.firstRemoteFrameRendered`, which
comes from `FirstFrameSentinel` — an `RTCVideoRenderer` attached to the remote
track. So it fires on a **real decoded frame reaching a renderer**. It is not
derived from ICE state, and it is not derived from anything to do with Apple
Vision.

### What has been ruled out, with evidence

A hypothesis that `RTCMTLVideoView` simply does not work in the Simulator was
**tested and not confirmed**:

```
DIAG metalDevice: present
DIAG RTCMTLVideoView subviews: 1
DIAG subview types: ["MTKView"]
DIAG renderFrame did not crash
```

Metal is available, the view builds its `MTKView`, and feeding it a frame does
not crash. So that explanation is not supported and is not being asserted.

Also ruled out: Apple Vision. The classifier runs on the *captured still*, not
the live track, and never touches the renderer.

### What would identify it

The problem needs a two-device setup to reproduce, which is not available here
(see §6). Rather than guess, the Controller now shows a frame counter:

> `Frames received: 142 (47 analysed, 95 skipped)`

Counted by `RemoteVideoFrameTap`, a second `RTCVideoRenderer` on the same
track as the on-screen view. That distinguishes the two possibilities that
"Video live" cannot:

- **A rising count with a blank preview** → the track is delivering frames to
  renderers and the on-screen view is not drawing them. A renderer problem;
  next step would be the `RTCMTLVideoView` layout/size path, or trying
  `RTCEAGLVideoView` as a comparison.
- **A count stuck at zero or very low** → frames are not arriving at all after
  the first. A transport, encoder or keyframe problem; `videoConfirmed`
  latches on the *first* frame and is never revisited, so one frame followed
  by silence looks identical to a healthy stream.

The counter only updates while detection is running, since that is what pumps
it. If live detection boxes are drawn over the grey area, that on its own is
proof frames are arriving and decodable.

**No WebRTC signalling, SDP, ICE or Firestore rule was changed.** There is no
evidence yet pointing at any of them, and the brief asks for none without it.

---

## 6. What remains unverified on physical iPhones

**No compatible devices are connected.**

```
$ xcrun devicectl list devices
K's Apple Vision Pro   …   unavailable
iPhone                 …   unavailable   iPhone 15 Pro
```

Both paired but unavailable, and the Controller/Camera flow needs two iPhones
where only one is known to this machine at all.

### Specifically unverified

1. **Apple Vision classification has never executed on a physical iPhone.**
   Not once, at any stage. It cannot run in the Simulator, and the Mac
   Catalyst harness is macOS. Every accuracy figure in these documents
   (42.1% / 72.7% full-image, 80.0% crop-based, 57.9% / 56.4% fused) comes
   from Mac Catalyst or Python. **The device path is unproven.**
2. **The `.available` branch of the new capability probe** has only been
   exercised on Mac Catalyst. On a device it should return `.available`; if it
   returns `.failed`, that is a real finding and the UI will now say so.
3. **The `.failed` branch has never fired for real.** It is covered by tests
   that inject the state, not by an observed device failure.
4. **Whether the hybrid pipeline actually beats YOLO-only on device** — the
   entire premise of the hybrid design.
5. **The grey video preview** (§5), including which of the two diagnoses the
   frame counter indicates.
6. Latency, thermals and memory for classification on an A-series chip.

### Device checklist for this change

- [ ] Analyse Ingredients on a device: confirm **no** "unavailable in
      Simulator" notice appears
- [ ] Confirm `ClassificationOutcome.capability == .available`, and that
      agreed/conflicting tiers appear (they cannot in the Simulator)
- [ ] Force a classifier failure (e.g. under memory pressure) and confirm it
      is reported as a fault in full, not downgraded
- [ ] Confirm region-classification failures surface as
      "N of M regions failed", not silence
- [ ] Read the frame counter while the preview is blank and record which
      diagnosis it indicates (§5)

Record results here under a new "On-device measurements" heading. Until that
section exists, device behaviour is unverified and should be described that
way.
