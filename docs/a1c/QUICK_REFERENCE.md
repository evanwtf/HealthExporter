# Lab Results Quick Reference

> Testing status: A1C export has been verified working end-to-end on a physical device with Clinical Health Records enabled. Byte-identical CSV output is pinned by `A1CCSVBytePinningTests`.

## What It Does

- Exports lab result values from Apple Health Clinical Records
- Each metric is identified by its LOINC code (`4548-4` for Hemoglobin A1C; additional supported panels include lipid, CBC, CMP / BMP, thyroid, and other tracked labs)
- Includes matching lab rows in the same CSV as weight, steps, and glucose

## Key Files

- `LabMetricRegistry.swift` for `LabPanel`, `LabMetric`, and `LabMetricRegistry.all`
- `HealthSampleTypes.swift` for `LabResultSample`, FHIR parsing, and `LOINCCode` constants
- `HealthKitManager.swift` for `requestAuthorization(includeLabs:vitalMetrics:completion:)` and `fetchLabResults(metrics:dateRange:limit:completion:)`
- `SettingsManager.swift` for `selectedLabPanels` and `favoriteLabCodes` (with one-time `exportA1C` migration)
- `ExportLogic.swift` for `resolveLabMetrics(selectedPanels:favoriteCodes:registry:)`
- `DataSelectionView.swift` for lab section toggles and the export flow
- `CSVGenerator.swift` for `appendLabResultRows(to:samples:dateFormat:sortOrder:)`

## Required Setup

Keep these generated Info.plist build settings in the Xcode project:

- `INFOPLIST_KEY_NSHealthClinicalHealthRecordsShareUsageDescription`
- `INFOPLIST_KEY_NSHealthShareUsageDescription`
- `INFOPLIST_KEY_NSHealthUpdateUsageDescription`

Also make sure the target has HealthKit and Clinical Health Records capabilities enabled.

## Runtime Notes

- The app currently targets iOS 26+
- The clinical-records code path is guarded with `#available(iOS 15.0, *)`
- Simulator support is limited; validate on a physical device
- The simulator-only test data generator is separate from the production export path

## Export Flow

1. User toggles lab sections or individual labs in the export screen
2. `ExportLogic.resolveLabMetrics` builds the deduplicated `[LabMetric]` fetch list
3. App requests HealthKit read access (clinical records included when labs are selected)
4. `fetchLabResults` runs a single clinical-records query and parses every matching LOINC into a `LabResultSample`
5. The combined CSV is generated in memory via `appendLabResultRows`
6. The file picker saves the export

## CSV Example

```csv
Date,Metric,Value,Unit,Source
2026-01-15 14:30:00,Hemoglobin A1C,7.50,%,Apple Health
2026-01-15 14:31:00,Total Cholesterol,184,mg/dL,Apple Health
```

## Adding a New Lab

1. Add a LOINC constant in `LOINCCode` if needed
2. Append a `LabMetric` to `LabMetricRegistry.all` (with `group` and `valuePrecision`)
3. UI, fetch, and CSV output all pick it up automatically

## Notes

- No labs are selected by default
- Per-metric value precision comes from `LabMetric.valuePrecision`
- Existing export metrics are unaffected
