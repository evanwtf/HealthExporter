# Testing Guide

## Overview

HealthExporter uses XCTest unit tests that run automatically in GitHub CI on every push and pull request.

## Test Structure

Tests live in `HealthExporterTests/` (sibling to the main `HealthExporter/` source folder):

| File | What it tests |
|------|--------------|
| `A1CCSVBytePinningTests.swift` | Byte-identical A1C CSV rows: `%` and `mmol/mol` units, comma/quote CSV escaping, two-decimal precision, ascending sort |
| `CSVDocumentTests.swift` | `CSVDocument` content storage, UTF-8 round-trip, invalid encoding detection |
| `CSVGeneratorTests.swift` | CSV generation for weight, steps, glucose, lab results, and vitals; unit conversion; registry-driven precision; output formatting |
| `DateRangeOptionTests.swift` | `DateRangeOption` enum cases, raw values, `displayName` |
| `DayRangeSummaryFormatterTests.swift` | Date range summary text formatting |
| `ExportErrorTests.swift` | All `ExportError.errorDescription` branches with/without underlying errors |
| `ExportLogicTests.swift` | Export enablement (including labs and vitals), date range calculation, record limits, data availability, filename generation, `resolveLabMetrics` panel/favorite union and dedup |
| `ExportPreviewEstimateTests.swift` | Row count rounding, byte estimation, confirmation threshold |
| `FHIRLabResultParserTests.swift` | FHIR JSON parsing — LOINC matching, missing fields, invalid data |
| `GlucoseSampleTests.swift` | `GlucoseSampleMgDl` init — values ≥20 accepted, values <20 rejected |
| `HealthKitQueryHelpersTests.swift` | Authorization type sets (with/without labs and vitals), day-aligned date ranges, `filterLabResultsByDateRange`, simulator-only test data helpers |
| `HealthMetricConfigTests.swift` | `HealthMetrics` static properties and `LOINCCode` constants |
| `LabMetricRegistryTests.swift` | `LabPanel` cases, `LabMetric.id == loincCode`, registry uniqueness, lookup by LOINC, panel grouping |
| `LabResultSampleTests.swift` | `LabResultSample` memberwise init, default empty source, FHIR init with known/unknown LOINC, missing observation handling |
| `SettingsEnumTests.swift` | Raw values, displayName, dateFormat, isUTC for all settings enums |
| `SettingsManagerTests.swift` | Default values, persisted reads (including lab and vital selections), invalid raw value fallbacks, legacy `exportA1C` → favorites migration |
| `VitalMetricRegistryTests.swift` | Vital metric cases, HealthKit identifiers, blood-pressure component expansion, unit conversion |

## Running Tests Locally

### In Xcode
1. Open `HealthExporter.xcodeproj`
2. Select **Product → Test** (⌘U)
3. Results appear in the Test Navigator (⌘6)

### From the command line
```bash
# Run tests against a specific simulator UUID to avoid duplicate-name collisions.
# Use `xcrun simctl list devices available` to find an ID on your machine.
xcodebuild test \
  -project HealthExporter.xcodeproj \
  -scheme HealthExporter \
  -destination 'id=<SIMULATOR-UUID>' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  | xcpretty
```

## GitHub Actions CI

The workflow is defined in `.github/workflows/ios-tests.yml` and triggers on:
- Pushes to `main` or `add_tests`
- Pull requests targeting `main`

### Required setup — none for public repos

For a **public repository**, no secrets or environment variables are needed. The workflow uses `CODE_SIGNING_ALLOWED=NO` so no Apple Developer account is required to run simulator tests.

### Optional setup for private repos or custom runners

| Setting | Purpose |
|---------|---------|
| `DEVELOPMENT_TEAM` build override | Only needed if you add entitlements-gated features to the test target |

### Xcode version

The workflow automatically picks the newest installed Xcode on the runner:
```yaml
XCODE=$(find /Applications -name "Xcode*.app" -maxdepth 1 -type d | sort -rV | head -1)
sudo xcode-select -s "$XCODE"
```

The project requires **Xcode 26.x** (for the iOS 26.0 deployment target). GitHub's `macos-15` runner should have this installed. If the runner only has an older Xcode, the build will fail with a deployment-target error — in that case, update `runs-on` in the workflow to a newer runner image (e.g. `macos-15-xlarge` or a future `macos-26`).

### xcpretty

The workflow pipes `xcodebuild` output through `xcpretty` for readable CI logs. If `xcpretty` is not pre-installed on the runner, add:
```yaml
- name: Install xcpretty
  run: gem install xcpretty
```
before the "Run tests" step.

## Adding New Tests

1. Create a new `*Tests.swift` file in `HealthExporterTests/`
2. The `PBXFileSystemSynchronizedRootGroup` in the Xcode project picks it up automatically — no `.pbxproj` edits needed for additional test files.
3. Use `@testable import HealthExporter` to access internal types.

## Manual Verification Matrix

The following items **intentionally remain outside CI unit tests** and require manual or device-based verification:

### HealthKit Authorization
- Real HealthKit authorization dialogs (grant/deny/partial)
- Authorization state persistence across app launches
- Behavior when HealthKit is unavailable (e.g. iPad without HealthKit)
- Real HealthKit vital samples, including blood-pressure pairs and oxygen saturation percentages

### Clinical Health Records
- Real Clinical Health Records availability and entitlement
- Actual lab record retrieval from health providers (e.g. A1C)
- FHIR resource parsing with real clinical data (unit tests cover synthetic JSON)

### File Export Integration
- `.fileExporter()` integration with the iOS Files picker
- Export to iCloud Drive, local storage, third-party file providers
- Correct filename display and file content in the saved CSV

### Simulator vs Device Differences
- HealthKit data generated via `generateTestData()` (simulator only)
- HealthKit read authorization behavior (simulator grants silently; device shows dialogs)
- Clinical Records entitlement (device only — simulator cannot request clinical data)

### SwiftUI View Behavior
- Splash screen animation timing (2-second delay)
- Settings sheet presentation and dismissal
- Navigation flow: Launch → DataSelection → Export
- Loading overlay during export preparation

### Known Test Limitations
- **`SettingsManager` cannot be instantiated in tests** due to a Combine/`@Published` malloc crash when a second instance is created alongside the app's `@main` `@StateObject`. Tests exercise the same logic through `UserDefaults` directly. A fix would require changing the test target to not use the app as `TEST_HOST`, or restructuring `SettingsManager` to avoid the `$property.dropFirst().sink()` pattern.
- **`HealthKitManager` fetch methods** are tightly coupled to `HKHealthStore` and callback-based queries. The pure query construction logic is tested via `HealthKitQueryHelpers`; actual data fetching requires a device with HealthKit data.
