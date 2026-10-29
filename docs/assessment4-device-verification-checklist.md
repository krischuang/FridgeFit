# FridgeFit — physical device verification checklist

Everything that needs real hardware, split into what is **automated** and
what has to be done **by hand**.

The governing rule: a check that was not performed is recorded as
**NOT VERIFIED**, never as passed. A green simulator run proves nothing about
on-device Apple Intelligence — the iOS 26 simulator reports the model as
`.available` while having no assets installed, and a `respond` call there
never returns.

---

## 1. Automated — `tools/device-verification/run-device-checks.sh`

```bash
tools/device-verification/run-device-checks.sh            # auto-detect a device
tools/device-verification/run-device-checks.sh <udid>     # a specific one
```

With no iPhone connected it prints `NOT VERIFIED` for every device-only
check and exits 0. It does not fail, and it does not pretend.

| Check | Suite | Needs hardware? |
|---|---|---|
| CoreML models bundled and compiled | `DevicePackagingTests` | No |
| Detector factory resolves (with fallback) | `DevicePackagingTests` | No |
| `NSCameraUsageDescription` present | `DevicePackagingTests` | No |
| Vision OCR runs without error | `DeviceVisionTests` | No |
| Apple Intelligence genuinely `.available` | `DeviceAppleIntelligenceTests` | **Yes** |
| Receipt interpretation returns real items | `DeviceAppleIntelligenceTests` | **Yes** |
| Recipe suggestions return real ideas | `DeviceAppleIntelligenceTests` | **Yes** |
| Model failure degrades, does not hang | `DeviceAppleIntelligenceTests` | **Yes** |
| Camera hardware present | `DeviceCameraTests` | **Yes** |
| Camera authorization reportable | `DeviceCameraTests` | **Yes** |

### Prerequisites

- iPhone 15 Pro / 16 / 17 family (Apple Intelligence needs A17 Pro or newer).
- **Settings → Apple Intelligence & Siri → on**, and the model download
  finished. Until it finishes, availability reports `modelNotReady` and the
  suite records NOT VERIFIED with that reason.
- Device paired, **unlocked**, and trusting this Mac.
- A signing team. The script passes one on the command line and **does not
  modify `project.pbxproj`**; override with `DEVELOPMENT_TEAM=XXXX`.

---

## 2. Manual — cannot be automated

A test process cannot answer a system permission prompt, photograph a
receipt, or pull a device off the network. These are the steps, each with
the outcome to look for.

### 2.1 Receipt OCR quality (real paper)

1. Print or obtain 3 real grocery receipts (different retailers).
2. My Fridge → Smart Scan → photograph each.
3. **Expect:** most product lines recognised; quantities and units sensible;
   non-food lines (totals, payment, loyalty) excluded.
4. **Record:** items detected vs items on the receipt, per receipt.

> Known limit: the interpretation step is bounded at 20s per batch and 45s
> per receipt. A receipt that exceeds the budget keeps what was read and the
> review screen shows exactly those items — a short list is a visible short
> list, not a silent truncation.

### 2.2 Recipe suggestion output

1. Add 5–8 real ingredients to the pantry.
2. Recipes → Find recipes.
3. **Expect:** cookable dishes that use the pantry; missing ingredients
   listed honestly rather than hidden.
4. **Red flag:** invented ingredients, or a recipe claiming an ingredient is
   in the pantry when it is not. (The pantry is re-derived by
   `SuggestRecipesFromPantryUseCase`, so the model cannot override it — but
   check the displayed result anyway.)

### 2.3 Model unavailable / failure

1. Settings → Apple Intelligence & Siri → **off**.
2. Smart Scan, and Recipes → Find recipes.
3. **Expect:** an explained unavailable state naming Apple Intelligence,
   with manual entry (scan) and the recipe catalogue (suggestions) still
   reachable. **No spinner that never ends.**
4. Turn it back on.

### 2.4 Camera permissions

1. Delete the app, reinstall (resets permission state).
2. Smart Scan → **Don't Allow**.
3. **Expect:** `CameraAccessPrompt` explaining what is blocked, with a
   working "Open Settings" button.
4. Grant from Settings, return to the app.
5. **Expect:** the camera works without a relaunch.

### 2.5 Background / foreground

1. Start a receipt scan; background the app mid-scan; return after ~30s.
2. **Expect:** either a completed scan or an explained error. Not a frozen
   spinner, not a crash.
3. Repeat with Camera Mode connected between two devices.
4. **Expect:** the session reconnects or reports it is disconnected.

### 2.6 Memory and thermals

1. Instruments → Allocations + Thermal State.
2. Camera Mode, sustained detection for 5 minutes.
3. **Expect:** memory plateaus rather than climbing without bound; no jetsam
   termination.
4. **Record:** peak footprint and thermal state.

### 2.7 Offline

1. Airplane mode.
2. Browse pantry, add an item, edit a budget, open Discover.
3. **Expect:** pantry and budget work normally — they are on-device SwiftData.
   Discover explains it is unavailable. Nothing claims a save it did not make.
4. Restore the network.
5. **Expect:** no duplicated writes on reconnect.

### 2.8 Account deletion on device

> With the Cloud Functions backend **not deployed** (the shipping default),
> this exercises the on-device deletion path.

1. Create a throwaway account; add pantry items, a budget and a saved recipe.
2. Profile → Settings → Delete Account → confirm.
3. **Expect:** confirmation dialog; progress; success only when finished;
   returned to the login screen.
4. Try to sign in again. **Expect:** failure.
5. Sign in as a *different* account on the same device.
   **Expect:** that account's data is intact.

---

## 3. Recording results

| Check | Result | Device / iOS | Date | Notes |
|---|---|---|---|---|
| Automated suite | | | | paste the script's table |
| 2.1 Receipt OCR quality | | | | n of m lines |
| 2.2 Recipe suggestions | | | | |
| 2.3 Model unavailable | | | | |
| 2.4 Camera permissions | | | | |
| 2.5 Background/foreground | | | | |
| 2.6 Memory and thermals | | | | peak MB |
| 2.7 Offline | | | | |
| 2.8 Account deletion | | | | |

Use **PASS**, **FAIL**, or **NOT VERIFIED**. Leave NOT VERIFIED rather than
guessing; an untested row is information, a fabricated one is not.
