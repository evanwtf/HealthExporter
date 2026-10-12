#!/usr/bin/env bash
# Check the Swift sources with SwiftFormat and SwiftLint.
# Usage: ci/lint_swift.sh
# Run it from any directory. It installs a missing tool with Homebrew.
# It runs both tools, then exits non-zero if either tool failed.
set -uo pipefail

cd "$(dirname "$0")/.."

for tool in swiftformat swiftlint; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    brew install "$tool" || exit 1
  fi
done

swiftformat --version
swiftlint version

status=0
swiftformat HealthExporter HealthExporterTests --lint --cache ignore || status=$?
swiftlint lint --strict --config .swiftlint.yml --no-cache || status=$?
exit "$status"
