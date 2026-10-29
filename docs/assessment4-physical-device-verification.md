# FridgeFit — physical device verification

Real-hardware verification run. Supersedes the NOT VERIFIED device section of
`docs/assessment4-final-production-verification.md`, which was written when
the phone was locked.

**No Git or GitHub operations were performed.**

---

## 1. Device and environment

| Property | Value | How established |
|---|---|---|
| Model | iPhone 15 Pro (`iPhone16,1`) | `xcrun devicectl device info details` |
| iOS | **26.6.1** | same |
| Developer Mode | **enabled** | `developerModeStatus: enabled` |
| Connection | **wired** | `transportType: wired` |
| Pairing / trust | paired and trusted | state `connected`; a debug session launched |
| Unlocked | yes | tests launched; a locked device fails preflight with `com.apple.dt.deviceprep Code=-3` |
| Apple Intelligence | **enabled, model available** | `test_appleIntelligence_isAvailable` passed on device |
| Signing | Team `V6V6VZ2F4Z`, passed on the command line | `project.pbxproj` **not modified** |
| Host | Xcode 26.1 (17B55), Swift 6.2.1 | `xcodebuild -version` |

The iPhone 15 Pro is A17 Pro, which is the minimum for Apple Intelligence.

---

## 2. Command

```bash
tools/device-verification/run-device-checks.sh
```

Auto-detected the device through `xcodebuild -showdestinations`, built,
signed, installed and ran four suites on the phone.

---

## 3. Automated results — 10 PASS, 0 FAIL, 4 NOT VERIFIED

| Check | Result | Evidence |
|---|---|---|
| Apple Intelligence genuinely available | **VERIFIED PASS** | passed on device; skips on simulator |
| **Real receipt interpretation generates** | **VERIFIED PASS** | passed in **8.193 s**; asserts non-empty items from real model output |
| **Real recipe suggestions generate** | **VERIFIED PASS** | passed in **4.450 s**; asserts non-empty, named recipes with ingredients |
| Model failure degrades, does not hang | **VERIFIED PASS** | 1 ms deadline returned promptly on device |
| Camera hardware present | **VERIFIED PASS** | `isSourceTypeAvailable(.camera)` true |
| Camera authorization reportable | **VERIFIED PASS** | status read; access already granted on this device |
| `NSCameraUsageDescription` present | **VERIFIED PASS** | read from the installed bundle |
| CoreML models bundled and compiled | **VERIFIED PASS** | `.mlmodelc` found in the device bundle |
| Detector factory resolves with fallback | **VERIFIED PASS** | 2.472 s; non-empty taxonomy |
| Vision OCR runs without error | **VERIFIED PASS** | 0.291 s on device |
| Background / foreground transitions | **NOT VERIFIED** | needs a manual session |
| Memory and thermals under load | **NOT VERIFIED** | needs Instruments |
| Offline (airplane mode) | **NOT VERIFIED** | needs a manual session |
| Receipt OCR quality on real paper | **NOT VERIFIED** | needs printed receipts |

Script output:

```
Passed: 10    Failed: 0    Not verified: 4
RESULT: PASS for everything that could be checked on this device
```

### What the two generation timings mean

These are the headline results, and they are **real model output, not mocks**.
`test_appleIntelligence_reallyGenerates` feeds the sample receipt through
`ReceiptLineParser` into `AppleReceiptIngredientInterpreter` and fails unless
the model returns at least one interpreted item. It returned in 8.193 s.
`test_recipeSuggestions_reallyGenerate` asks for recipes from a
three-ingredient pantry and fails unless each suggestion has a name and
ingredients. It returned in 4.450 s.

Both skip with `NOT VERIFIED` on the simulator, which reports the model as
`.available` while having no assets. The previous report recorded them as
NOT VERIFIED; they are now verified.

---

## 4. Still requiring a human

Four checks cannot be automated. Precise steps are in
`docs/assessment4-device-verification-checklist.md`; the short version:

1. **Receipt OCR quality** — photograph three real receipts through Smart
   Scan; record items detected against items printed.
2. **Background/foreground** — start a scan, background the app for ~30 s,
   return. Expect a completed scan or an explained error, never a frozen
   spinner.
3. **Memory and thermals** — Instruments Allocations + Thermal State, Camera
   Mode for 5 minutes. Expect a plateau, no jetsam.
4. **Offline** — airplane mode; pantry and budget keep working (local
   SwiftData), Discover explains itself, nothing claims a save it did not
   make.

A fifth needs **two** iPhones and is not covered by the single-device run:
Camera Mode peer-to-peer streaming, which is also the path that triggers the
newly added **Local Network** permission (see the privacy audit).

---

## 5. Why the earlier run reported nothing

The first attempt failed preflight:

```
Error Domain=com.apple.dt.deviceprep Code=-3 "Unlock iPhone to Continue"
```

The build and code-signing had already succeeded; iOS simply refuses to start
a debug session on a locked phone, and `xcodebuild` then waits indefinitely.
Two defects in the runner were fixed as a result, both recorded in the
previous report: `grep 'available'` also matched `unavailable`, and
`devicectl` UUIDs are not the identifiers `xcodebuild` accepts.

---

## 6. Verdict

| | |
|---|---|
| Device-automatable checks | **10 / 10 PASS** |
| Real on-device Apple Intelligence | **VERIFIED PASS** |
| Manual-only checks | **4 NOT VERIFIED** |
| Two-device Camera Mode | **NOT VERIFIED** (one device available) |

No simulator or mock output is presented anywhere as evidence of
physical-device AI behaviour.
