# HealthExporter - Copilot Instructions

## Project Overview

HealthExporter is an iOS app built with SwiftUI that exports HealthKit data (Weight, Steps, Blood Glucose, Hemoglobin A1C) to CSV files. The app supports configurable date formats, sort order, unit preferences, and flexible date range filtering.

## Tech Stack

- **Language**: Swift 5
- **UI Framework**: SwiftUI
- **Platform**: iOS 26+ (build targets iOS 26 and above only)
- **Frameworks**: HealthKit, UniformTypeIdentifiers, Combine

## Project Structure

```
HealthExporter/
├── HealthExporter.xcodeproj/     # Xcode project file
├── HealthExporter/
│   └── HealthExporter/           # Main source folder
│       ├── HealthExporterApp.swift   # App entry point (@main)
│       ├── LaunchView.swift          # Splash screen with spinner + settings access
│       ├── DataSelectionView.swift   # Data selection, date range & export UI
│       ├── SettingsView.swift        # Settings: export format, units, test data
│       ├── SettingsManager.swift     # Settings persistence with UserDefaults
│       ├── HealthKitManager.swift    # HealthKit authorization & queries
│       ├── HealthMetricConfig.swift  # Central metric registry
│       ├── HealthSampleTypes.swift   # Glucose, A1C, FHIR parsing
│       ├── CSVGenerator.swift        # CSV generation with unit conversion, date format, sort order
│       ├── CSVDocument.swift         # FileDocument for SwiftUI fileExporter
│       ├── DateRangeOption.swift     # Date range selection enum
│       ├── ExportError.swift         # Localized error types
│       ├── PrivacyPolicyView.swift   # Privacy policy & disclaimer view
│       └── Assets.xcassets/          # App assets
├── HealthExporterTests/          # Unit tests
└── README.md
```

## Architecture

### Views
- **LaunchView**: Welcome/splash screen with "Next" button and gear icon for Settings
- **DataSelectionView**: Main screen with metric toggles (Weight, Steps, Blood Glucose, A1C), date pickers, and Save button
- **SettingsView**: Export format (date format, sort order) and unit preference configuration (Temperature, Weight, Distance/Speed)

### Managers
- **HealthKitManager**: Handles HealthKit authorization and data fetching with optional date range filtering
- **SettingsManager**: ObservableObject that persists unit preferences, date format, and sort order via UserDefaults
- **HealthMetricConfig**: Defines the supported export metrics

### Utilities
- **CSVGenerator**: Converts HKQuantitySample arrays to CSV strings with unit conversion
- **CSVDocument**: FileDocument implementation for SwiftUI's fileExporter

## Key Patterns

1. **Navigation**: Uses NavigationStack with NavigationLink for screen transitions (no deprecated APIs)
2. **File Export**: SwiftUI's `.fileExporter()` modifier for Save functionality
3. **HealthKit Queries**: Async completion handlers with DispatchGroup for parallel fetching
4. **Date Filtering**: Optional date range with inclusive start/end dates
5. **Settings Persistence**: UserDefaults with @Published properties for auto-save
6. **Unit Conversion**: Weight converted from kg to lbs based on user preference (1 kg = 2.2046226218 lbs)

## Required Capabilities

- **HealthKit**: Must be enabled in Signing & Capabilities
- **Clinical Health Records** (A1C): Enable capability for A1C export
- **Info.plist Keys** (set via Build Settings as INFOPLIST_KEY_*):
    - `NSHealthShareUsageDescription`
    - `NSHealthClinicalHealthRecordsShareUsageDescription` (required for A1C export)

## Supported Health Metrics

| Metric | HealthKit Identifier | Units |
|--------|---------------------|-------|
| Weight | `.bodyMass` | kg, lbs |
| Steps | `.stepCount` | count |
| Blood Glucose | `.bloodGlucose` | mg/dL |
| Hemoglobin A1C | `.labResultRecord` (Clinical) | % |

## CSV Output Format

Columns: `Date, Metric, LOINC, Value, Unit, Source, Meal Time`

Date format is user-selectable in Settings via `DateFormatOption`:
- `yyyy-MM-dd HH:mm:ss` (default, local time)
- ISO8601 (UTC)
- `yyyy/MM/dd HH:mm:ss`
- `MM/dd/yyyy HH:mm:ss`
- `dd MMM yyyy HH:mm:ss`

Sort order is configurable: ascending (oldest first, default) or descending (newest first).

Example:
```
Date,Metric,LOINC,Value,Unit,Source,Meal Time
2026-01-09 10:30:00,Weight,,185.50,lbs,Withings,
2026-01-09 11:00:00,Steps,,5432,steps,Apple Watch,
2026-01-09 14:30:00,Blood Glucose,,145,mg/dL,MyFitnessPal,After Meal
2026-01-15 14:30:00,Hemoglobin A1C,4548-4,7.50,%,Apple Health,
```

Filename format: `HealthExporter_YYYY-MM-DD_HHMMSS.csv`

## Development Notes

- HealthKit requires a physical iOS device for full testing (simulator has limited support)
- Export button is disabled when no metrics are selected or date range is invalid
- Weight values are formatted to 2 decimal places
- Default date range is past 30 days; date range is selectable via `DateRangeOption` enum (Last X Days, Last X Records, Specific Date Range, All Records)
- Settings auto-save on change (no save button needed)

### Testing Status

- Hemoglobin A1C export has been verified working end-to-end on a physical device with Clinical Health Records enabled.

### Metric Pattern

**CRITICAL**: When adding metrics:

1. Define the metric in `HealthMetricConfig.swift`
2. Add authorization and fetching support in `HealthKitManager`
3. Add a normal toggle in `DataSelectionView`
4. Persist the setting in `SettingsManager`
5. Update `hasSelectedMetric` and CSV generation
6. Add tests and documentation

## Memory Optimization Directive

**CRITICAL**: This app handles potentially large HealthKit datasets. Follow these memory management practices:

### Fetching Data
- **Never store raw HealthKit samples longer than necessary** - Release sample arrays as soon as CSV is generated
- Set fetched data to `nil` immediately after converting to CSV: `weightSamples = nil`
- Only keep in-memory what's actively being used

### CSV Generation
- **Use append methods**: Each metric type has a dedicated `appendXxxRows(to:samples:...)` method that sorts in-place and appends rows directly to a string buffer
- Avoid intermediate array allocations — write directly to the output string via `csv.append()`

### View State
- **Clear CSV content after export** - Empty `csvContent` property immediately after successful save
- Clean up large data structures in `.onDisappear` handlers
- Remove unused @State variables that hold data

### General Rules
- Don't keep gigantic structs or arrays in @State longer than needed
- Profile with Xcode's Memory Graph debugger if adding features
- Batch process if possible (stream to disk rather than accumulate in memory)
- For very large date ranges, consider pagination or chunked exports in the future

## Future Expansion

When adding new health data types:
1. Add the metric to `HealthMetricConfig.swift`
2. Add new quantity type identifiers in `HealthKitManager.requestAuthorization()` (only if available)
3. Create new fetch methods in `HealthKitManager` for each data type
4. Add corresponding toggle in `DataSelectionView` (see Development Notes)
5. Extend `CSVGenerator.generateCombinedCSV()` with the new data type
6. Add unit conversion logic if applicable
7. Update SettingsManager/SettingsView if new preferences are needed
8. **Ensure new data types follow memory optimization practices** - release samples after CSV generation

## Code Style

- SwiftUI declarative syntax
- Completion handler pattern for async HealthKit operations
- `@State` properties for view-local state management
- `@ObservedObject` for shared SettingsManager
- `@StateObject` at app root for SettingsManager lifecycle
- Compact DatePicker style for space efficiency
- DispatchGroup for coordinating parallel async operations

## Documentation

Keep all project documentation in the `docs/` folder, organized by feature/topic:
- Create subdirectories for related documentation (e.g., `docs/a1c/`, `docs/export/`)
- Use descriptive filenames (e.g., `IMPLEMENTATION_GUIDE.md`, `QUICK_REFERENCE.md`)
- Reference docs when implementing features to understand context and decisions
- Update docs when adding new features or changing implementation details
