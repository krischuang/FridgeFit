# Receipt demo fast path

A verified, persistent, exact-image cache in front of receipt recognition, so
one prepared receipt reaches the review screen immediately while every other
receipt continues to go through Apple Intelligence unchanged.

## Why a receipt scan takes ten seconds

`ScanReceiptUseCase` runs four stages. Only one of them is slow:

| Stage | Component | Cost |
| --- | --- | --- |
| OCR | `VisionReceiptTextRecognizer` | tens of ms |
| Line cleanup | `ReceiptLineParser` | negligible |
| **Interpretation** | **`AppleReceiptIngredientInterpreter`** | **~10 s** |
| Validation and canonicalisation | `ReceiptItemNormalizer` | negligible |

The interpreter sends parsed lines to `SystemLanguageModel` in batches of
twelve, each batch in a fresh `LanguageModelSession`. That is where the time
goes, and for a given picture it produces the same answer every time — which
is exactly the shape of thing worth caching.

## Cache identity: canonical pixels, not file bytes

The cache key is **not** the picked file's SHA-256.

`ReceiptScannerView` loads a photo through
`PhotosPicker` → `loadTransferable(type: Data.self)` → `UIImage(data:)`, and
what comes back is whatever representation the Photos library chose to hand
over. Re-exporting, an iCloud Photos sync, or an edit that changes nothing
visible can all change those bytes while the picture stays identical. A file
hash would miss the match and the demo would fall back to a ten-second scan.

`ReceiptImageFingerprint` instead hashes the picture:

1. Draw once into a fixed bitmap format — sRGB, 8 bits per channel,
   premultiplied RGBA, tightly packed rows. This pins colour space and memory
   layout, so a 16-bit, Display-P3 or alpha-first source cannot change the
   answer by being *stored* differently.
2. Remap to upright from the photo's EXIF orientation, as a pure index
   permutation — no interpolation, no second colour conversion — so the same
   photo tagged `.up` and `.right` agrees with itself.
3. SHA-256 over a domain-separated preimage of the algorithm version, the
   upright dimensions and the upright pixel bytes.

Matching is **exact**. No downscaling, no perceptual hash, no tolerance. A
different Coles receipt, a crop, a re-photograph, or one changed pixel all
produce a different fingerprint and go to the model. A cache that could answer
approximately is a cache that can answer for a receipt nobody verified.

The source PNG supplied for this demonstration hashes to
`5edbb57bdd219f692feea6f133f3c8ae8fe7afdc41457e811cfb280214e23de8`. That
identifies the *file on disk*; it is not the cache key, and nothing in the app
depends on it.

## What is and is not stored

Stored: the pantry candidates and the excluded items, exactly as the pipeline
produced them, plus a schema version, a pipeline version and the preparation
timestamp.

Not stored:

- **`isAlreadyInPantry`.** It is a fact about the pantry at the time of the
  scan, not about the receipt, and the pantry changes. It is recomputed from
  the live pantry on every hit — which is also what stops a replay from
  offering to add something the user already has, and why no duplicate pantry
  records appear.
- **Empty results.** `save` refuses them, so a failed analysis can never
  become a permanently fast failure.
- **The receipt image.** Neither the photo nor any precomputed result is in
  the repository or in any build.

## Invalidation

An entry carries `schemaVersion` (the file layout) and `pipelineVersion` (OCR,
parsing, prompt, normalisation, canonicalisation). If either differs from the
running build's, the entry reads as a **miss** and the scan proceeds normally.
Change `ReceiptRecognitionPipeline.version` whenever a change could alter a
result. Unreadable files and undecodable JSON behave the same way: a cache is
an optimisation and is never a reason for a scan to fail.

## Transparency

A replay is never presented as fresh analysis.

- `ReceiptScanOutcome.source` is `.verifiedCache` on a hit and travels through
  to `ReceiptScannerViewModel.recognitionSource`.
- The review screen says so: *"Reused the saved result from the last time this
  exact photo was analysed. You can still edit everything below."*
- DEBUG diagnostics print `RECOGNITION CACHE HIT` with the key, the
  preparation time and the pipeline version, and the engine banner says
  "no model invocation" rather than naming Foundation Models.

The result remains fully editable — name, category, quantity, unit, selection
— before anything reaches the pantry, through the same
`AddDetectedIngredientsUseCase`.

## Preparing the demo

Scanning **never** writes to the cache. If it did, the first scan of any
receipt would be persisted unreviewed. Writing is confined to a DEBUG-only
flow a person runs and inspects.

1. Put the receipt photo in the demo device's photo library. Use the same
   image you will pick during the demo — AirDrop or Files, not a screenshot
   or a re-crop.
2. Build and run the **Debug** configuration on that device, with Apple
   Intelligence enabled in Settings.
3. Open **Smart Scan Capture** and tap the **hammer** icon in the navigation
   bar. (DEBUG only; the button does not exist in Release.)
4. Tap **Choose Demo Receipt** and pick the photo. The canonical fingerprint
   appears immediately.
5. Tap **Prepare Coles Demo Receipt**. This runs the real pipeline and takes
   the normal scan time. That is expected — it happens before the demo.
6. Read the result. Every detected item is listed with its quantity, category
   and source line, followed by any discrepancies against the reference
   receipt. Two are worth understanding:
   - **Blocking** — a detected quantity equal to the line total, i.e. a price
     read as a quantity. This cannot be cached.
   - **Review** — a pack size that disagrees with the reference, a missing
     item, an unexpected image size. Legitimate answers; you decide.
7. If you are satisfied, tap **Accept and Cache This Result**.
8. The banner should now read **DEMO CACHE READY** with the cache key and
   preparation time.
9. **Verify persistence:** force-quit the app, relaunch, and reopen the
   screen. It re-reads from disk, so a banner still reading READY is proof
   the entry survived.
10. Rehearse: pick the same photo through the normal Import flow. The review
    screen should appear immediately, with the reuse note visible.

The reference values in `ColesDemoReceiptExpectation` are a **checklist for
the operator, never a source of data**. Nothing from them is written to the
cache — the entry holds exactly what the model produced. A missing item stays
missing rather than being filled in.

### Quantities, pack sizes and prices

`COLS TOMATOES 1KG    3.60` states a **pack size** of 1 kg and a **line total**
of $3.60. It does not state a unit price, and it does not state how much the
user now has in their kitchen — a pantry quantity is something the user
confirms on the review screen, and `ReceiptItemDraft` leaves it blank when the
receipt did not say.

On a cleanly read line the deterministic `ReceiptQuantityParser` wins outright,
so a model proposing `3.60` cannot get it onto the candidate. The blocking
check exists for the case where OCR mangles the pack size (`1KG` read as
`IKG`), the parser finds nothing, and the model's number is used instead —
at which point $3.60 really can become "3.6 kg of tomatoes". Both behaviours
are pinned by tests.

## Measured latency

Instrumentation records fingerprint duration, cache lookup duration and total
scan duration (`ReceiptScanMetrics`), plus time from `scan()` to the review
screen being presented (`ReceiptScannerViewModel.lastScanLatency`). In DEBUG
these print to the Xcode console as `RECEIPT SCAN TIMING` and
`REVIEW PRESENTED`.

Measured on the **iPhone 17 Pro simulator**, at the demo receipt's real
971 × 1619 resolution:

| Path | Time to review presented |
| --- | --- |
| Verified cache hit | **0.014 – 0.016 s** |
| Full pipeline (model stubbed at 250 ms) | 0.271 – 0.273 s |

The cache-hit figure is dominated by fingerprinting ~1.57 M pixels; the store
read is a single small JSON file.

**These are simulator numbers and are not a device verification.** A device
will be slower, though the path contains no I/O or model work that would
change its order of magnitude, and in the real demo the dominant cost is
likely to be `PhotosPicker` handing over the image rather than anything here.
To get the real figure, run the Debug build on the demo device, pick the
prepared receipt, and read `REVIEW PRESENTED` from the console.

## Scope

Other receipts are untouched. A different Coles receipt, a Woolworths or Aldi
receipt, a restaurant receipt, a re-photograph, or a crop of the demo receipt
all miss the cache and run the full Apple Intelligence pipeline. Image
selection, OCR, parsing, quantity handling, confirmation, pantry persistence,
error messages, cancellation and retry are all unchanged, and a
`ScanReceiptUseCase` built without a cache — still the default — behaves
exactly as it did before.
