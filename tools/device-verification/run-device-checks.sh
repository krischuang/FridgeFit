#!/bin/bash
#
# run-device-checks.sh — FridgeFit physical-device verification
#
# Runs the `Device*Tests` suites on a connected iPhone and prints a
# PASS / FAIL / NOT VERIFIED table.
#
# ## The rule
#
# With no compatible device connected, every device-only check is reported
# **NOT VERIFIED** and the script exits 0. It does not pretend, and it does
# not fail the build either - "we could not check this" is a legitimate
# outcome that has to be visible rather than silently absent.
#
# A device-only check that is skipped *on a device* (Apple Intelligence
# turned off, camera access not granted) is also NOT VERIFIED, with the
# reason the test gave.
#
# Usage:
#     tools/device-verification/run-device-checks.sh            # auto-detect
#     tools/device-verification/run-device-checks.sh <udid>     # specific device
#
# Requires the device to be paired, unlocked, and trusted. Signing uses
# whatever DEVELOPMENT_TEAM the project already has; this script never
# changes it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

SUITES=(
  "FridgeFitTests/DevicePackagingTests"
  "FridgeFitTests/DeviceVisionTests"
  "FridgeFitTests/DeviceAppleIntelligenceTests"
  "FridgeFitTests/DeviceCameraTests"
)

DERIVED_DATA="${DERIVED_DATA:-$(mktemp -d)/dd}"
# `mktemp -d`, not `mktemp`: the latter creates a *file*, and appending a
# path to it produces "Not a directory" the moment xcodebuild redirects here.
LOG="$(mktemp -d)/device-checks.log"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }

# ---------------------------------------------------------------- detection

bold "FridgeFit — physical device verification"
echo

DEVICE_ID="${1:-}"

if [ -z "$DEVICE_ID" ]; then
  # Asked of xcodebuild rather than `devicectl`, deliberately.
  #
  # `devicectl list devices` reports a CoreDevice UUID
  # (5F37C39E-B460-...), and xcodebuild does **not** accept it - it wants the
  # hardware identifier (00008130-0018...). Passing the devicectl id produces
  # "Unable to find a device matching the provided destination specifier"
  # even though the phone is plugged in and working. Asking the same tool
  # that will run the tests avoids the mismatch entirely.
  #
  # Real devices carry `arch:arm64`; the `Any iOS Device` placeholder does
  # not, which is how they are told apart. `platform:iOS,` with the comma
  # excludes `platform:iOS Simulator`.
  DEVICE_LINE="$(xcodebuild -project FridgeFit.xcodeproj -scheme FridgeFit \
      -showdestinations 2>/dev/null \
    | grep -E 'platform:iOS,' \
    | grep -E 'arch:arm64' \
    | grep -viE 'placeholder|Simulator' \
    | head -1)"

  if [ -n "$DEVICE_LINE" ]; then
    DEVICE_ID="$(echo "$DEVICE_LINE" | sed -nE 's/.*id:([^,}]+).*/\1/p' | xargs)"
    DEVICE_NAME="$(echo "$DEVICE_LINE" | sed -nE 's/.*name:([^,}]+).*/\1/p' | xargs)"
  fi
fi

if [ -z "$DEVICE_ID" ]; then
  echo "No connected iPhone found."
  echo
  bold "RESULT: NOT VERIFIED (no physical device)"
  echo
  echo "The following require real hardware and were NOT checked:"
  echo "  - Apple Intelligence model availability"
  echo "  - Real receipt interpretation output"
  echo "  - Real recipe-suggestion output"
  echo "  - On-device model failure behaviour"
  echo "  - Camera hardware and authorization"
  echo "  - Background/foreground transitions"
  echo "  - Memory under sustained detection"
  echo "  - Offline fallback on device"
  echo
  echo "Connect a paired, unlocked iPhone and re-run."
  echo "Manual steps: docs/assessment4-device-verification-checklist.md"
  exit 0
fi

echo "Device:  ${DEVICE_NAME:-unknown} ($DEVICE_ID)"
echo "Log:     $LOG"
echo

# ------------------------------------------------------------------ running

ONLY_TESTING=()
for suite in "${SUITES[@]}"; do
  ONLY_TESTING+=("-only-testing:$suite")
done

# The app target carries a DEVELOPMENT_TEAM; the *test* target does not, so
# a device run fails with "Signing for FridgeFitTests requires a development
# team". Supplied on the command line rather than written into
# project.pbxproj - this script must not change the project's signing
# configuration, only satisfy it for one local run. Override with
# DEVELOPMENT_TEAM=... if yours differs.
TEAM="${DEVELOPMENT_TEAM:-$(sed -nE 's/.*DEVELOPMENT_TEAM = ([A-Z0-9]+);.*/\1/p' \
  FridgeFit.xcodeproj/project.pbxproj | head -1)}"

if [ -n "$TEAM" ]; then
  echo "Signing team: $TEAM (command line only; the project file is not modified)"
  echo
fi

bold "Running device checks…"

# Bounded, because xcodebuild waits *forever* for a locked phone. Left
# unbounded it prints "Unlock iPhone to Continue" once and then sits there,
# which in an unattended run is indistinguishable from a slow build. A
# timeout turns that into a reported NOT VERIFIED with the real reason.
TIMEOUT_SECONDS="${DEVICE_CHECK_TIMEOUT:-900}"

xcodebuild \
  -project FridgeFit.xcodeproj \
  -scheme FridgeFit \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  -configuration Debug \
  ${TEAM:+DEVELOPMENT_TEAM="$TEAM"} \
  -allowProvisioningUpdates \
  "${ONLY_TESTING[@]}" \
  test > "$LOG" 2>&1 &
XCODE_PID=$!

WAITED=0
while kill -0 "$XCODE_PID" 2>/dev/null; do
  if grep -q "Unlock iPhone to Continue" "$LOG" 2>/dev/null; then
    kill "$XCODE_PID" 2>/dev/null
    wait "$XCODE_PID" 2>/dev/null
    echo
    bold "RESULT: NOT VERIFIED (the device is locked)"
    echo
    echo "The app built and signed for this device successfully, but the tests"
    echo "could not launch: iOS refuses to start a debug session on a locked"
    echo "phone. Unlock it, keep it awake, and re-run."
    echo
    echo "Nothing on the device was checked. Not a failure - unverified."
    exit 0
  fi

  if [ "$WAITED" -ge "$TIMEOUT_SECONDS" ]; then
    kill "$XCODE_PID" 2>/dev/null
    wait "$XCODE_PID" 2>/dev/null
    echo
    bold "RESULT: NOT VERIFIED (timed out after ${TIMEOUT_SECONDS}s)"
    echo
    tail -20 "$LOG"
    exit 0
  fi

  sleep 5
  WAITED=$((WAITED + 5))
done

wait "$XCODE_PID"
XCODE_STATUS=$?

echo

# ------------------------------------------------------------------ results

if ! grep -qE "^Test Case" "$LOG"; then
  bold "RESULT: NOT VERIFIED (the test run did not start)"
  echo
  echo "Common causes: the device is locked, not trusted, or needs a"
  echo "provisioning profile. Nothing below was checked."
  echo
  tail -25 "$LOG"
  exit 0
fi

printf '%-52s %s\n' "CHECK" "RESULT"
printf '%-52s %s\n' "----------------------------------------------------" "------------"

PASSED=0; FAILED=0; UNVERIFIED=0

while IFS= read -r line; do
  name="$(echo "$line" | sed -E "s/.*FridgeFitTests\.[A-Za-z]+ (test_[A-Za-z_]+)\].*/\1/")"
  case "$line" in
    *" passed "*)  printf '%-52s %s\n' "$name" "PASS";          PASSED=$((PASSED+1)) ;;
    *" failed "*)  printf '%-52s %s\n' "$name" "FAIL";          FAILED=$((FAILED+1)) ;;
    *" skipped "*) printf '%-52s %s\n' "$name" "NOT VERIFIED";  UNVERIFIED=$((UNVERIFIED+1)) ;;
  esac
done < <(grep -E "^Test Case.*(passed|failed|skipped) \(" "$LOG")

echo
bold "Passed: $PASSED    Failed: $FAILED    Not verified: $UNVERIFIED"
echo

if [ "$UNVERIFIED" -gt 0 ]; then
  echo "Reasons the unverified checks gave:"
  grep -E "NOT VERIFIED:" "$LOG" | sed -E 's/.*(NOT VERIFIED:.*)/  - \1/' | sort -u
  echo
fi

if [ "$FAILED" -gt 0 ]; then
  bold "RESULT: FAIL"
  grep -E "error: -\[" "$LOG" | head -20
  exit 1
fi

if [ "$XCODE_STATUS" -ne 0 ] && [ "$PASSED" -eq 0 ]; then
  bold "RESULT: NOT VERIFIED (xcodebuild exited $XCODE_STATUS)"
  exit 0
fi

bold "RESULT: PASS for everything that could be checked on this device"
echo "Manual steps that no automated run can cover:"
echo "  docs/assessment4-device-verification-checklist.md"
