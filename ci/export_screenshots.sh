#!/usr/bin/env bash
# Copy the ScreenshotTests PNGs out of a result bundle, named by attachment
# (for example 02-data-selection-light.png), and print each image's size.
# Usage: ci/export_screenshots.sh <result-bundle-path> <output-dir>
# A missing bundle is a warning, not a failure: the test step reports that.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <result-bundle-path> <output-dir>" >&2
  exit 2
fi
RESULT_BUNDLE="$1"
OUT_DIR="$2"

if [ ! -d "$RESULT_BUNDLE" ]; then
  echo "::warning::No result bundle at $RESULT_BUNDLE; no screenshots to export."
  exit 0
fi

RAW_DIR="$(mktemp -d)"
trap 'rm -rf "$RAW_DIR"' EXIT
mkdir -p "$OUT_DIR"
xcrun xcresulttool export attachments --path "$RESULT_BUNDLE" --output-path "$RAW_DIR"

# The runner's /usr/bin/python3 is 3.9: keep the syntax old.
/usr/bin/python3 - "$RAW_DIR" "$OUT_DIR" <<'PY'
import json
import os
import re
import shutil
import sys

raw_dir, out_dir = sys.argv[1], sys.argv[2]
count = 0
with open(os.path.join(raw_dir, "manifest.json")) as manifest:
    tests = json.load(manifest)
for test in tests:
    for attachment in test.get("attachments", []):
        exported = attachment["exportedFileName"]
        if not exported.lower().endswith(".png"):
            continue
        # "02-data-selection-light_0_<UUID>.png" -> "02-data-selection-light.png"
        name = re.sub(
            r"_\d+_[0-9A-Fa-f-]{36}(\.\w+)$", r"\1", attachment["suggestedHumanReadableName"]
        )
        shutil.copyfile(os.path.join(raw_dir, exported), os.path.join(out_dir, name))
        count += 1
print("Exported %d screenshots to %s" % (count, out_dir))
PY

# App Store Connect takes only exact sizes and no alpha channel: print both.
for image in "$OUT_DIR"/*.png; do
  [ -e "$image" ] || continue
  info=$(sips -g pixelWidth -g pixelHeight -g hasAlpha "$image" | awk '/pixel|hasAlpha/ {printf "%s ", $2}')
  set -- $info
  echo "$(basename "$image"): $1 x $2, alpha: $3"
done
