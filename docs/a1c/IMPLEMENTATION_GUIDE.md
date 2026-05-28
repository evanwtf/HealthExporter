# Lab Results Export Implementation Guide

## Overview

Lab result export — including Hemoglobin A1C and lipid panel labs — is part of the current HealthExporter release. Users can opt into exporting Clinical Health Records lab results and the app will include matching records in the combined CSV output. The lab pipeline is registry-driven: adding a new lab requires only appending a `LabMetric` to `LabMetricRegistry.all`.

> Testing status: A1C export has been verified working end-to-end on a physical device with Clinical Health Records enabled. Byte-identical CSV output is pinned by `A1CCSVBytePinningTests`.

## Current Architecture

### Registry

- `LabMetricRegistry.swift` defines the metric registry
- `LabPanel` groups metrics into logical panels (`lipid`, `cbc`, `cmp`, `thyroid`, `other`)
- `LabMetric` describes a single lab observation: `name`, `loincCode` (also `id`), `group`, and `valuePrecision`
- `LabMetricRegistry.all` is the single source of truth; current entries include Hemoglobin A1C plus Total Cholesterol, HDL Cholesterol, LDL Cholesterol, and Triglycerides
- Helpers: `LabMetricRegistry.metric(forLoincCode:)` and `LabMetricRegistry.metrics(in:)`

### Data Model

- `HealthSampleTypes.swift` defines `LabResultSample`, the generic lab result row
- `LabResultSample` carries `metricName`, `loincCode`, `effectiveDateTime`, `value`, `unit`, and `source`
- Initializers parse FHIR JSON (`init?(fromFHIRData:loincCode:source:)`) or an `HKClinicalRecord` (`init?(from:loincCode:)`)
- LOINC `4548-4` identifies Hemoglobin A1C; lipid LOINC constants (`2093-3`, `2085-9`, `2089-1`, `2571-8`) live alongside it in `LOINCCode`

### HealthKit Authorization

- `HealthKitManager.requestAuthorization(includeLabs:completion:)` adds the clinical-records read type when any lab metric is selected
- Production authorization is read-only; `toShare` is an empty set
- The app targets iOS 26+, while the clinical-records code path is guarded with `#available(iOS 15.0, *)`

### Fetch Path

- `HealthKitManager.fetchLabResults(metrics:dateRange:limit:completion:)` runs a single `HKSampleQuery` against `HKClinicalType.labResultRecord`
- For each returned record, the fetch tries every requested LOINC code; all matches become `LabResultSample` rows
- Date filtering happens after parsing via `HealthKitQueryHelpers.filterLabResultsByDateRange`

### UI and Settings

- `SettingsManager` persists `selectedLabPanels: Set<LabPanel>` and `favoriteLabCodes: Set<String>` in `UserDefaults`
- A one-time legacy migration seeds `favoriteLabCodes = ["4548-4"]` for upgrade installs that had `exportA1C == true`; the legacy boolean is no longer read after migration
- `DataSelectionView` shows a "Lab Favorites" section (per-metric toggles bound to `favoriteLabCodes`) and a "Lab Panels" section (one toggle per `LabPanel` that has at least one registered metric)
- `ExportLogic.resolveLabMetrics(selectedPanels:favoriteCodes:registry:)` produces the deduplicated fetch list
- `SettingsView` exposes simulator-only test data generation, but the write path is not part of the production export flow

### CSV Output

- `CSVGenerator.appendLabResultRows(to:samples:dateFormat:sortOrder:)` appends rows to the combined export
- The metric label comes from `LabMetric.name` (e.g. `Hemoglobin A1C` or `Total Cholesterol`)
- Per-metric precision comes from `LabMetric.valuePrecision`; A1C renders to 2 decimal places and lipid panel labs render as integers

## Required Configuration

The app uses generated Info.plist values from `HealthExporter.xcodeproj/project.pbxproj`. Keep these build settings present:

- `INFOPLIST_KEY_NSHealthClinicalHealthRecordsShareUsageDescription`
- `INFOPLIST_KEY_NSHealthShareUsageDescription`
- `INFOPLIST_KEY_NSHealthUpdateUsageDescription`

The Clinical Health Records usage string should clearly explain why the app needs lab-result access.

## Device Verification

- Clinical Records are not available in the simulator
- Validate lab-result export on a physical iOS device
- Make sure the device has clinical records synced in Apple Health

## Data Flow

1. User toggles favorites or panels in `DataSelectionView`
2. `ExportLogic.resolveLabMetrics` produces the deduplicated list of `LabMetric`s
3. The app requests HealthKit read access; clinical records are included when the list is non-empty
4. `HealthKitManager.fetchLabResults` runs a single clinical-records query
5. Matching FHIR payloads are parsed into `LabResultSample` values
6. `CSVGenerator.appendLabResultRows` appends rows into the combined CSV
7. The system file picker handles the save/export step

## Adding a New Lab

1. Add a LOINC constant in `LOINCCode` if it is not already there
2. Append a `LabMetric` to `LabMetricRegistry.all` with the right `group` and `valuePrecision`
3. The favorites/panel toggles, fetch path, and CSV output light up automatically — no other code changes needed
4. Add a pinning test if byte-identical CSV output matters for the new metric

## Notes

- Lab export is opt-in; no labs are selected by default
- Existing weight, steps, and glucose export behavior is unchanged
- The simulator-only write path remains behind `#if targetEnvironment(simulator)`
