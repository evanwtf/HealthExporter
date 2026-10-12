# HealthExporterCSV

A privacy-focused iOS app that exports Apple HealthKit data to CSV files. All data processing happens entirely on-device — no health data is ever sent to external servers.

## Features

- **Privacy-first design**: All processing on-device, no analytics, no tracking, no accounts
- **Multiple health metrics**: Export Weight, Steps, Blood Glucose (mg/dL), selected clinical lab panels, and selected vitals
- **Flexible date ranges**: Last X days, last X records, custom date range, or all data
- **Unit preferences**: Configure weight units (kg/lbs) and temperature (°C/°F); defaults to US units (Fahrenheit, lbs)
- **Selectable date format**: Choose from 5 date formats including ISO8601 (UTC), `yyyy-MM-dd HH:mm:ss`, `MM/dd/yyyy HH:mm:ss`, and more
- **Sort order**: Export rows in ascending (oldest first) or descending (newest first) order
- **CSV export**: Save directly to Files app via `.fileExporter()`
- **Welcome screen** with navigation to data selection and settings
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
| **LOINC** | LOINC code found in the lab record (e.g., `4548-4`); empty for weight, steps, glucose, and vitals |
| **Value** | Numeric value with metric-specific precision |
| **Unit** | Unit of measurement (kg, lbs, steps, mg/dL, %, etc.) |
| **Source** | The app or device that recorded the data (e.g., Withings, Apple Watch) |
| **Meal Time** | Blood glucose only: `Before Meal`, `After Meal`, or empty when the reading has no meal time. Empty for all other metrics |

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
### No warranty of accuracy or completeness or fitness for any purpose.
### Not a medical record. Verify with your healthcare provider before any clinical use.
Date,Metric,LOINC,Value,Unit,Source,Meal Time
2026-01-09 10:30:00,Weight,,185.50,lbs,Withings,
2026-01-09 11:00:00,Steps,,5432,steps,Apple Watch,
2026-01-09 07:15:00,Blood Glucose,,98,mg/dL,MyFitnessPal,Before Meal
2026-01-09 14:30:00,Blood Glucose,,145,mg/dL,MyFitnessPal,After Meal
2026-01-15 14:30:00,Hemoglobin A1C,4548-4,7.50,%,Apple Health,
2026-01-15 14:31:00,Total Cholesterol,2093-3,184,mg/dL,Apple Health,
2026-01-15 14:32:00,Blood Pressure Systolic,,120,mmHg,Apple Health,
2026-01-15 14:32:00,Blood Pressure Diastolic,,80,mmHg,Apple Health,
2026-01-15 14:33:00,Oxygen Saturation,,98.5,%,Apple Health,
```

Each export starts with three `### `-prefixed disclaimer lines so common CSV parsers can be configured to skip them as comments. The `LOINC` column carries the LOINC code for clinical-record lab results and is left empty for HealthKit-native metrics (weight, steps, glucose, vitals). The `Meal Time` column comes from the meal-time tag on a blood glucose reading; every other row leaves it empty, so each row has seven fields.

Data can be sorted ascending (oldest first) or descending (newest first) within each metric type. Filename format: `HealthExporter_YYYY-MM-DD_HHMMSS.csv`.

## Requirements

- iOS 26+
- Physical iOS device (for full HealthKit functionality)
- HealthKit access permission
- Clinical Health Records capability and user permission (for lab-result export)

## Testing

Unit tests run in GitHub Actions on every push to `main` and every pull request from a branch in this repo. The `iOS Tests` workflow (`.github/workflows/ios-tests.yml`) runs on the self-hosted Mac runner (`[self-hosted, macOS, ARM64]`, `MacMiniM6_01`) through [`ci/run_ios_tests.sh`](ci/run_ios_tests.sh). Pull requests from forks do not run on the self-hosted runner. See [docs/TESTING.md](docs/TESTING.md) for the full testing guide.

| Test file | Coverage |
|-----------|----------|
| `CSVGeneratorTests.swift` | CSV generation for all metrics, unit conversion, formatting |
| `DateRangeOptionTests.swift` | Date range enum cases and display names |
| `HealthMetricConfigTests.swift` | Metric availability, LOINC codes |
| `GlucoseSampleTests.swift` | Blood glucose filtering (values >= 20 accepted, < 20 rejected) |

### Lab Testing Status

Hemoglobin A1C export has been **verified working end-to-end** on a physical device with Clinical Health Records enabled. Additional lab panels use the same registry-driven clinical-records pipeline and are covered by unit tests; validate new lab records on a physical device before release. Vitals use HealthKit quantity samples and should also be verified on device before release. See [docs/a1c/](docs/a1c/) for lab implementation details.

## Releases

Every pull request merged to `main` cuts a new version and uploads it to TestFlight. Nothing runs from a laptop. The chain:

1. A merge to `main` starts `bump-build-number.yml` on the Linux runner. It bumps the build number and the patch version, commits the bump, pushes a `vX.Y.Z` tag, creates the GitHub release, and dispatches `release-testflight.yml` on the tag.
2. `release-testflight.yml` runs on the Mac runner. It tests, archives, exports a signed IPA and uploads it to internal TestFlight.

| Workflow | Trigger | Runner | What it does |
|----------|---------|--------|--------------|
| `.github/workflows/bump-build-number.yml` | PR merge to `main` | `[self-hosted, Linux, X64]` | Increments `CURRENT_PROJECT_VERSION` and the `MARKETING_VERSION` patch component, commits the bump, pushes a `vX.Y.Z` tag, creates the GitHub release with generated notes, and dispatches the TestFlight upload on the tag |
| `.github/workflows/release-testflight.yml` | Dispatch from the bump workflow, or by hand | `[self-hosted, macOS, ARM64]` (`MacMiniM6_01`) | Tests, archives, exports a signed IPA via [`ci/ExportOptions.plist`](ci/ExportOptions.plist), and uploads it to internal TestFlight |
| `.github/workflows/publish-release.yml` | `v*` tag pushed by hand | `[self-hosted, Linux, X64]` | Fallback: creates the GitHub release for a tag that did not come from the bump workflow |

A tag that the bump workflow pushes with `GITHUB_TOKEN` does not trigger other workflows. That is why the bump workflow creates the release and dispatches TestFlight itself.

Rebuild and upload a specific tag by hand. App Store Connect rejects a build number that it already has, so this only helps when the earlier upload failed:

```sh
gh workflow run release-testflight.yml --repo evanwtf/HealthExporter --ref vX.Y.Z
```

Dry run: test, archive and export a signed IPA, but do not upload it:

```sh
gh workflow run release-testflight.yml --repo evanwtf/HealthExporter -f upload=false
```

The TestFlight workflow needs these secrets. Its "Check required secrets" step fails the job early if one is missing.

- Repository secrets `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID` and `ASC_API_KEY_P8`: an App Store Connect API key with the App Manager role. One team key serves all the team's apps.
- Organization secret `MACOS_KEYCHAIN_PASSWORD`: the password for the runner's login keychain. Its selected repositories must include `HealthExporter`.

The archive signs automatically for development. The export signs manually ([`ci/ExportOptions.plist`](ci/ExportOptions.plist)) with the runner's local `Apple Distribution` identity for team `94S5PZTVPY` and the `HealthExporter App Store` profile. The workflow downloads that profile by name through the API key on every run ([`ci/install_profile.swift`](ci/install_profile.swift), read-only). An Admin creates or renews the profile once a year in the Apple Developer portal; nothing is installed on the runner by hand. See [docs/macos-runner-recovery.md](docs/macos-runner-recovery.md) when signing or runner state drifts.

## Project Structure

```
HealthExporter/
├── HealthExporter/
│   ├── HealthExporter.xcodeproj/
│   ├── HealthExporter.entitlements
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
│       ├── CSVFile.swift                # Transferable CSV for the Files picker
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
├── ci/
│   ├── ExportOptions.plist        # Export options (manual signing)
│   ├── install_profile.swift      # Downloads the App Store profile by name
│   └── run_ios_tests.sh           # Simulator unit tests, used by CI
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
