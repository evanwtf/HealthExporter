# HealthExporterCSV

A privacy-focused iOS app that exports Apple HealthKit data to CSV files. All data processing happens entirely on-device — no health data is ever sent to external servers.

## Features

- **Privacy-first design**: All processing on-device, no analytics, no tracking, no accounts
- **Multiple health metrics**: Export Weight, Steps, Blood Glucose (mg/dL), selected clinical lab panels, and selected vitals
- **Flexible date ranges**: Last X days, last X records, custom date range, or all data
- **Unit preferences**: Configure weight units (kg/lbs), temperature (°C/°F), and distance/speed (metric/imperial); defaults to US units (Fahrenheit, lbs, imperial)
- **Selectable date format**: Choose from 5 date formats including ISO8601 (UTC), `yyyy-MM-dd HH:mm:ss`, `MM/dd/yyyy HH:mm:ss`, and more
- **Sort order**: Export rows in ascending (oldest first) or descending (newest first) order
- **CSV export**: Save directly to Files app via `.fileExporter()`
- **Splash screen** with navigation to data selection and settings
- **Settings persistence**: Unit preferences are automatically saved
- **Clinical records support**: Lab-result export requires Clinical Health Records capability and permission
- **Memory-optimized**: Health data is cleared from memory immediately after export

## Screenshots

<table>
  <tr>
    <td align="center">
      <strong>Splash Screen</strong><br>
      <img src="assets/splash_screen.PNG" alt="Splash Screen" style="border: 1px solid black; width: 300px;">
    </td>
    <td align="center">
      <strong>Metric Selector</strong><br>
      <img src="assets/metric_selector.PNG" alt="Metric Selector" style="border: 1px solid black; width: 300px;">
    </td>
    <td align="center">
      <strong>Settings</strong><br>
      <img src="assets/settings.PNG" alt="Settings" style="border: 1px solid black; width: 300px;">
    </td>
  </tr>
</table>

## Setup

1. Open `HealthExporter.xcodeproj` in Xcode
2. Ensure HealthKit is enabled in Signing & Capabilities
3. If using lab-result export, enable **Clinical Health Records** capability (see [lab result docs](docs/a1c/) for details)
4. Build and run on a physical device (HealthKit has limited simulator support)

## Usage

1. Launch the app (splash screen displays briefly)
2. (Optional) Tap the gear icon to configure unit preferences or view the privacy policy
3. Tap "Next" to go to the data selection screen
4. Select metrics to export (Weight, Steps, Blood Glucose, lab sections, or vitals)
5. Choose a date range option (last X days, last X records, date range, or all data)
6. Tap "Save..." to save to Files

## CSV Output Format

The exported CSV includes the following columns:

| Column | Description |
|--------|-------------|
| **Date** | Timestamp in user-selected format (see below) |
| **Metric** | Type of measurement (Weight, Steps, Blood Glucose, lab result, or vital sign) |
| **Value** | Numeric value with metric-specific precision |
| **Unit** | Unit of measurement (kg, lbs, steps, mg/dL, %, etc.) |
| **Source** | The app or device that recorded the data (e.g., Withings, Apple Watch) |

### Date Format Options

| Format | Example |
|--------|---------|
| `yyyy-MM-dd HH:mm:ss` (default) | 2026-01-09 10:30:00 |
| ISO8601 (UTC) | 2026-01-09T10:30:00Z |
| `yyyy/MM/dd HH:mm:ss` | 2026/01/09 10:30:00 |
| `MM/dd/yyyy HH:mm:ss` | 01/09/2026 10:30:00 |
| `dd MMM yyyy HH:mm:ss` | 09 Jan 2026 10:30:00 |

Example:
```
### HealthExporterCSV: data exported as-is from Apple Health.
### No warranty of accuracy, completeness, or fitness for any purpose.
### Not a medical record. Verify with your healthcare provider before any clinical use.
Date,Metric,LOINC,Value,Unit,Source
2026-01-09 10:30:00,Weight,,185.50,lbs,Withings
2026-01-09 11:00:00,Steps,,5432,steps,Apple Watch
2026-01-09 14:30:00,Blood Glucose,,145,mg/dL,MyFitnessPal
2026-01-15 14:30:00,Hemoglobin A1C,4548-4,7.50,%,Apple Health
2026-01-15 14:31:00,Total Cholesterol,2093-3,184,mg/dL,Apple Health
2026-01-15 14:32:00,Blood Pressure Systolic,,120,mmHg,Apple Health
2026-01-15 14:32:00,Blood Pressure Diastolic,,80,mmHg,Apple Health
2026-01-15 14:33:00,Oxygen Saturation,,98.5,%,Apple Health
```

Each export starts with three `### `-prefixed disclaimer lines so common CSV parsers can be configured to skip them as comments. The `LOINC` column carries the LOINC code for clinical-record lab results and is left empty for HealthKit-native metrics (weight, steps, glucose, vitals).

Data can be sorted ascending (oldest first) or descending (newest first) within each metric type. Filename format: `HealthExporter_YYYY-MM-DD_HHMMSS.csv`.

## Requirements

- iOS 26+
- Physical iOS device (for full HealthKit functionality)
- HealthKit access permission
- Clinical Health Records capability and user permission (for lab-result export)

## Testing

Unit tests run automatically in GitHub Actions CI on every push and PR. See [docs/TESTING.md](docs/TESTING.md) for the full testing guide.

| Test file | Coverage |
|-----------|----------|
| `CSVGeneratorTests.swift` | CSV generation for all metrics, unit conversion, formatting |
| `DateRangeOptionTests.swift` | Date range enum cases and display names |
| `HealthMetricConfigTests.swift` | Metric availability, LOINC codes |
| `GlucoseSampleTests.swift` | Blood glucose filtering (values >= 20 accepted, < 20 rejected) |

### Lab Testing Status

Hemoglobin A1C export has been **verified working end-to-end** on a physical device with Clinical Health Records enabled. Additional lab panels use the same registry-driven clinical-records pipeline and are covered by unit tests; validate new lab records on a physical device before release. Vitals use HealthKit quantity samples and should also be verified on device before release. See [docs/a1c/](docs/a1c/) for lab implementation details.

## Releases

Three GitHub Actions workflows handle the release pipeline:

| Workflow | Trigger | Runner | What it does |
|----------|---------|--------|--------------|
| `.github/workflows/bump-build-number.yml` | PR merge to `main` | `ubuntu-latest` | Increments `CURRENT_PROJECT_VERSION` and the `MARKETING_VERSION` patch component, commits the bump, and pushes a `vX.Y.Z` tag |
| `.github/workflows/publish-release.yml` | `v*` tag push | `ubuntu-latest` | Creates the GitHub release with auto-generated notes |
| `.github/workflows/release-testflight.yml` | Manual dispatch + daily 13:00 UTC schedule | `[self-hosted, macOS, ARM64]` (`MacMiniM4_01`) | Tests, archives, exports a signed IPA via [`ci/ExportOptions.plist`](ci/ExportOptions.plist), and uploads it to internal TestFlight |

Manual TestFlight upload for the current `main`:

```sh
gh workflow run release-testflight.yml --repo evanwtf/HealthExporter
```

Upload a specific tag or commit:

```sh
gh workflow run release-testflight.yml --repo evanwtf/HealthExporter -f ref=vX.Y.Z
```

The TestFlight workflow requires the `MACOS_KEYCHAIN_PASSWORD`, `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID`, and `ASC_API_KEY_P8` secrets, plus a `HealthExporter App Store` provisioning profile installed on the runner with HealthKit and Clinical Health Records capabilities. See [docs/macos-runner-recovery.md](docs/macos-runner-recovery.md) when signing or runner state drifts.

## Project Structure

```
HealthExporter/
├── HealthExporter/
│   ├── HealthExporter.xcodeproj/
│   ├── HealthExporter.entitlements
│   ├── Info.plist
│   └── HealthExporter/
│       ├── HealthExporterApp.swift      # App entry point, NavigationStack
│       ├── LaunchView.swift             # Splash screen with spinner + settings access
│       ├── DataSelectionView.swift      # Metric selection & export UI
│       ├── SettingsView.swift           # Unit/format preferences & test data
│       ├── PrivacyPolicyView.swift      # Privacy policy & disclaimer
│       ├── HealthKitManager.swift       # HealthKit auth & data fetching
      │       ├── HealthMetricConfig.swift     # Base metric registry
      │       ├── LabMetricRegistry.swift      # Clinical lab panel registry
      │       ├── VitalMetricRegistry.swift    # HealthKit vital metric registry
│       ├── HealthSampleTypes.swift      # Glucose, LOINC constants, FHIR parsing
│       ├── CSVGenerator.swift           # CSV generation & unit conversion
│       ├── CSVDocument.swift            # FileDocument for saving
│       ├── SettingsManager.swift        # UserDefaults persistence
│       ├── DateRangeOption.swift        # Date range selection enum
│       ├── ExportError.swift            # Localized error types
│       └── Assets.xcassets/
├── HealthExporterTests/
│   ├── CSVGeneratorTests.swift
│   ├── DateRangeOptionTests.swift
│   ├── HealthMetricConfigTests.swift
│   └── GlucoseSampleTests.swift
├── docs/
│   ├── TESTING.md
│   ├── app-store-review.md
│   ├── privacy-policy.md
│   ├── index.md
│   └── a1c/
│       ├── QUICK_REFERENCE.md
│       └── IMPLEMENTATION_GUIDE.md
├── .github/workflows/         # ios-tests, bump-build-number, publish-release, release-testflight
├── ci/ExportOptions.plist
└── README.md
```

## Privacy Policy

*Last updated: May 2026*

### Overview

HealthExporterCSV is designed with your privacy as a core principle. All data processing happens entirely on your device. No health data is ever sent to external servers, collected by the developer, or shared with third parties.

### Data We Access

HealthExporterCSV requests read-only access to the following Apple HealthKit data types, only when you explicitly grant permission:

- Weight
- Step Count
- Blood Glucose
- Selected clinical lab results, such as Hemoglobin A1C, lipid panel, CBC, CMP / BMP, thyroid, and other tracked labs
- Selected vitals, such as blood pressure, resting heart rate, heart rate variability, oxygen saturation, respiratory rate, and body temperature

You control exactly which data types to share through the Apple Health permissions dialog.

### How Your Data Is Used

Your health data is used solely to generate CSV export files on your device. Specifically:

- Data is read from HealthKit only when you initiate an export
- The CSV file is generated in memory and presented through the system file picker
- Health data is cleared from app memory immediately after export
- No health data is stored persistently by the app

### Data Storage

The only data HealthExporterCSV stores persistently is your preferences (unit selections, date format, sort order, and metric toggle states) in the app's local UserDefaults. No health data, personal identifiers, or usage analytics are stored.

### No Data Collection or Transmission

HealthExporterCSV does not:

- Collect or transmit any data to external servers
- Include analytics, crash reporting, or tracking SDKs
- Require or support user accounts
- Use advertising or marketing frameworks
- Share data with any third parties

### Your Control

You can revoke HealthExporterCSV's access to HealthKit data at any time through **Settings > Health > Data Access & Devices** on your iPhone. Revoking access does not affect any CSV files you have previously exported.

### Changes to This Policy

If this privacy policy is updated, the revised version will be included in an app update. The "Last updated" date at the top will reflect the most recent revision.

## Disclaimer

### No Warranty

HealthExporterCSV is provided "as is" without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement.

### Not Medical Advice

HealthExporterCSV is a data export utility. It does not provide medical advice, diagnosis, or treatment recommendations. The exported data is a reflection of what is stored in Apple HealthKit and should not be used as a substitute for professional medical judgment. Always consult a qualified healthcare provider with questions about your health.

### Limitation of Liability

In no event shall the developer be liable for any claim, damages, or other liability arising from the use or inability to use this app, including but not limited to data loss, inaccurate exports, or any decisions made based on exported data.

### Data Accuracy

HealthExporterCSV exports data as recorded in Apple HealthKit. The developer makes no guarantees about the accuracy, completeness, or reliability of the underlying health data or the exported CSV files.

# Test of beef
Can you believe this?
