# Testing Guide

## Overview

HealthExporter uses Swift Testing unit tests and one XCTest suite (`ScreenshotTests`). They run automatically in GitHub CI on every push and pull request.

## Test Structure

Tests live in `HealthExporterTests/` (sibling to the main `HealthExporter/` source folder):

| File | What it tests |
|------|--------------|
| `A1CCSVBytePinningTests.swift` | Byte-identical A1C CSV rows: `%` and `mmol/mol` units, comma/quote CSV escaping, two-decimal precision, ascending sort |
| `CSVFileTests.swift` | `CSVFile` content and UTF-8 byte count, the `.commaSeparatedText` transfer representation, `makeFile` bytes and cancellation, the builder's cancellation checks |
| `CSVGeneratorTests.swift` | CSV generation for weight, steps, glucose, lab results, and vitals; unit conversion; registry-driven precision; output formatting |
| `DateRangeOptionTests.swift` | `DateRangeOption` enum cases, raw values, `displayName` |
| `DayRangeSummaryFormatterTests.swift` | Date range summary text formatting |
| `ExportErrorTests.swift` | All `ExportError.errorDescription` branches with/without underlying errors |
| `ExportLogicTests.swift` | Export enablement (including labs and vitals), date range calculation, record limits, data availability, filename generation, `resolveLabMetrics` panel/favorite union and dedup |
| `ExportSizeTests.swift` | Exact row and byte counts in the alert text, confirmation thresholds, `makeFile` size against the generated CSV |
| `FHIRLabResultParserTests.swift` | FHIR JSON parsing — LOINC matching, missing fields, invalid data |
| `GlucoseSampleTests.swift` | `GlucoseSampleMgDl` init — values ≥20 accepted, values <20 rejected |
| `HealthKitQueryHelpersTests.swift` | Authorization type sets (with/without labs and vitals), day-aligned date ranges, `filterLabResultsByDateRange`, simulator-only test data helpers |
| `HealthMetricConfigTests.swift` | `HealthMetrics` static properties and `LOINCCode` constants |
| `LabSelectionTests.swift` | Panel and single-lab selection rules, including the #115 sequence (a panel on then off keeps a lab selected on its own) |
| `LabMetricRegistryTests.swift` | `LabPanel` cases, `LabMetric.id == loincCode`, registry uniqueness, lookup by LOINC, panel grouping |
| `LabResultSampleTests.swift` | `LabResultSample` memberwise init, default empty source, FHIR init with known/unknown LOINC, missing observation handling |
| `SettingsEnumTests.swift` | Raw values, displayName, dateFormat, isUTC for all settings enums |
| `SettingsManagerTests.swift` | The real `SettingsManager` on a per-test `UserDefaults` suite: defaults, a suite written by v2.5.0 loads unchanged, changes are written with the same keys and formats, invalid raw value fallbacks, legacy `exportA1C` → favorites migration |
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

To run the same steps as CI, on a throwaway simulator:
```bash
ci/run_ios_tests.sh /tmp/TestResults.xcresult
```

## GitHub Actions CI

The workflow is defined in `.github/workflows/ios-tests.yml` and triggers on:
- Pushes to `main`
- Pull requests targeting `main`, from branches in this repository only

The job runs on the self-hosted Mac runner, selected by the labels `[self-hosted, macOS, ARM64]` (currently `MacMiniM6_01`). That runner also holds the signing keychain for TestFlight builds, so pull requests from forks do not run on it. A new push to the same ref cancels the run in progress.

The job calls [`ci/run_ios_tests.sh`](../ci/run_ios_tests.sh). The script:
1. Prints the selected Xcode and its version.
2. Restarts `CoreSimulatorService`, so an Xcode upgrade does not leave a stale daemon.
3. Creates a throwaway simulator from the newest `iPhone N Pro` device type and the newest iOS runtime, and deletes it on exit.
4. Runs `xcodebuild test -only-testing:HealthExporterTests` with `CODE_SIGNING_ALLOWED=NO`.

The result bundle is uploaded as the `test-results` artifact, also when the tests fail. The TestFlight workflow runs the same script before it archives.

### Xcode version

The runner admin installs and selects Xcode on the runner. The workflow does not run `xcode-select` or `setup-xcode`: a newer Xcode without its iOS simulator runtime breaks the tests. The project requires **Xcode 26** or later (for the iOS 26.0 deployment target).

### Secrets

The test job needs no secrets. `CODE_SIGNING_ALLOWED=NO` means no Apple Developer account is involved.

### Logs

The runner does not have `xcpretty`, so the job logs raw `xcodebuild` output. Open the `test-results` artifact in Xcode for a structured view.

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
- **`HealthKitManager` fetch methods** are tightly coupled to `HKHealthStore` and callback-based queries. The pure query construction logic is tested via `HealthKitQueryHelpers`; actual data fetching requires a device with HealthKit data.
