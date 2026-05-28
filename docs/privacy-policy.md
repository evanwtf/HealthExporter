---
layout: page
title: Privacy Policy
permalink: /privacy-policy/
---

# Privacy Policy — HealthExporterCSV

**Last updated:** May 2026

## Overview

HealthExporterCSV is designed with your privacy as a core principle. All data processing happens entirely on your device. No health data is ever sent to external servers, collected by the developer, or shared with third parties.

## Data We Access

HealthExporterCSV requests read-only access to the following Apple HealthKit data types, only when you explicitly grant permission:

- Weight
- Step Count
- Blood Glucose
- Selected clinical lab results, such as Hemoglobin A1C, lipid panel, CBC, CMP / BMP, thyroid, and other tracked labs
- Selected vitals, such as blood pressure, resting heart rate, heart rate variability, oxygen saturation, respiratory rate, and body temperature

You control exactly which data types to share through the Apple Health permissions dialog.

## How Your Data Is Used

Your health data is used solely to generate CSV export files on your device. Specifically:

- Data is read from HealthKit only when you initiate an export.
- The CSV file is generated in memory and presented through the system file picker.
- Health data is cleared from app memory immediately after export.
- No health data is stored persistently by the app.

## Data Storage

The only data HealthExporterCSV stores persistently is your preferences (unit selections, date format, sort order, and metric toggle states) in the app's local UserDefaults. No health data, personal identifiers, or usage analytics are stored.

## No Data Collection or Transmission

HealthExporterCSV does not:

- Collect or transmit any data to external servers
- Include analytics, crash reporting, or tracking SDKs
- Require or support user accounts
- Use advertising or marketing frameworks
- Share data with any third parties

## Your Control

You can revoke HealthExporterCSV's access to HealthKit data at any time through **Settings > Health > Data Access & Devices** on your iPhone. Revoking access does not affect any CSV files you have previously exported.

## Changes to This Policy

If this privacy policy is updated, the revised version will be included in an app update. The "Last updated" date at the top will reflect the most recent revision.

---

# Disclaimer

## No Warranty

HealthExporterCSV is provided "as is" without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, and noninfringement.

## Not Medical Advice

HealthExporterCSV is a data export utility. It does not provide medical advice, diagnosis, or treatment recommendations. The exported data is a reflection of what is stored in Apple HealthKit and should not be used as a substitute for professional medical judgment. Always consult a qualified healthcare provider with questions about your health.

## Limitation of Liability

In no event shall the developer be liable for any claim, damages, or other liability arising from the use or inability to use this app, including but not limited to data loss, inaccurate exports, or any decisions made based on exported data.

## Data Accuracy

HealthExporterCSV exports data as recorded in Apple HealthKit. The developer makes no guarantees about the accuracy, completeness, or reliability of the underlying health data or the exported CSV files.

---

## Contact

For questions about this privacy policy, please open an issue at [github.com/evandhoffman/HealthExporter/issues](https://github.com/evandhoffman/HealthExporter/issues).
