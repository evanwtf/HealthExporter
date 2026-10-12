#!/usr/bin/env bash
# Run the HealthExporterTests unit tests on a throwaway iOS simulator.
# Usage: ci/run_ios_tests.sh <result-bundle-path>
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <result-bundle-path>" >&2
  exit 2
fi
RESULT_BUNDLE="$1"

# The runner admin manages the installed Xcode. Do not switch it here.
xcode-select -p
xcodebuild -version

# After an Xcode upgrade the user-domain CoreSimulator daemon can keep the old
# framework loaded, and every simctl call fails with "CoreSimulator is out of
# date". Restart it so it reloads against the selected Xcode.
launchctl kickstart -k "gui/$(id -u)/com.apple.CoreSimulator.CoreSimulatorService" || true

# `xcrun simctl` does not fail when it cannot reach CoreSimulatorService: it
# waits forever. That happens when no GUI session is logged in on the runner,
# or when an Xcode upgrade leaves the daemon wedged. One such call once held
# the only macOS runner for the whole 6-hour job timeout. macOS has no
# `timeout(1)`, so run each probe in the background with a 30-second watchdog.
probe_simctl() {
  local pid waited=0
  xcrun simctl list devicetypes >/dev/null 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge 30 ]; then
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
}

simctl_ready=""
for _ in {1..10}; do
  if probe_simctl; then
    simctl_ready=1
    break
  fi
  sleep 1
done

if [ -z "$simctl_ready" ]; then
  echo "::error::CoreSimulator is not responding. The usual cause is an Xcode upgrade with no 'sudo xcodebuild -runFirstLaunch'; the other is no GUI session on the runner. See docs/macos-runner-recovery.md, section 8."
  exit 1
fi

# Newest "iPhone N Pro"; else the first iPhone device type.
DEVICE_TYPE_ID=$(xcrun simctl list devicetypes -j | /usr/bin/python3 -c '
import json, re, sys
types = json.load(sys.stdin).get("devicetypes", [])
iphones = [t for t in types if t.get("name", "").startswith("iPhone")]
pros = [t for t in iphones if re.fullmatch(r"iPhone \d+ Pro", t["name"])]
pros.sort(key=lambda t: int(t["name"].split()[1]))
pick = pros[-1] if pros else (iphones[0] if iphones else None)
if pick is None:
    sys.exit("No iPhone simulator device type available")
print(pick["identifier"])
')

RUNTIME_ID=$(xcrun simctl list runtimes available -j | /usr/bin/python3 -c '
import json, sys
runtimes = [
    r for r in json.load(sys.stdin).get("runtimes", [])
    if r.get("isAvailable")
    and r.get("identifier", "").startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
]
if not runtimes:
    sys.exit("No iOS simulator runtime available")
runtimes.sort(key=lambda r: tuple(int(p) for p in r["version"].split(".")))
print(runtimes[-1]["identifier"])
')

echo "Device type: $DEVICE_TYPE_ID"
echo "Runtime:     $RUNTIME_ID"

SIMULATOR_ID=$(xcrun simctl create "HealthExporter CI $$" "$DEVICE_TYPE_ID" "$RUNTIME_ID")
trap 'xcrun simctl delete "$SIMULATOR_ID" || true' EXIT
echo "Simulator:   $SIMULATOR_ID"

xcrun simctl boot "$SIMULATOR_ID"
xcrun simctl bootstatus "$SIMULATOR_ID" -b

# xcodebuild refuses to overwrite an existing result bundle.
rm -rf "$RESULT_BUNDLE"

# Unit tests use Swift Testing; only ScreenshotTests uses XCTest. xcodebuild
# prints a separate summary for each framework, so print one total from the
# result bundle. The script exits with the xcodebuild status.
status=0
xcodebuild test \
  -project HealthExporter.xcodeproj \
  -scheme HealthExporter \
  -destination "id=$SIMULATOR_ID" \
  -only-testing:HealthExporterTests \
  -resultBundlePath "$RESULT_BUNDLE" \
  CODE_SIGNING_ALLOWED=NO || status=$?

if [ -d "$RESULT_BUNDLE" ]; then
  SUMMARY=$(xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" --compact \
    | /usr/bin/python3 -c '
import json, sys
s = json.load(sys.stdin)
print("Test summary: {} tests, {} passed, {} failed, {} skipped, {} expected failures (result: {})".format(
    s.get("totalTestCount", 0), s.get("passedTests", 0), s.get("failedTests", 0),
    s.get("skippedTests", 0), s.get("expectedFailures", 0), s.get("result", "unknown")))
') || SUMMARY="Test summary: could not read $RESULT_BUNDLE"
  echo "$SUMMARY"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "$SUMMARY" >> "$GITHUB_STEP_SUMMARY"
  fi
fi

exit "$status"
