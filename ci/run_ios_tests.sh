#!/usr/bin/env bash
# Run the HealthExporterTests unit tests on a throwaway iOS simulator.
# Usage: ci/run_ios_tests.sh <result-bundle-path>
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <result-bundle-path>" >&2
  exit 2
fi
RESULT_BUNDLE="$1"

xcode-select -p
xcodebuild -version

# After an Xcode upgrade the user-domain CoreSimulator daemon can keep the old
# framework loaded, and every simctl call fails with "CoreSimulator is out of
# date". Restart it so it reloads against the selected Xcode.
launchctl kickstart -k "gui/$(id -u)/com.apple.CoreSimulator.CoreSimulatorService" || true
for _ in {1..30}; do
  if xcrun simctl list devicetypes >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

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

xcodebuild test \
  -project HealthExporter.xcodeproj \
  -scheme HealthExporter \
  -destination "id=$SIMULATOR_ID" \
  -only-testing:HealthExporterTests \
  -resultBundlePath "$RESULT_BUNDLE" \
  CODE_SIGNING_ALLOWED=NO
