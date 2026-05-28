# App Store Review Notes — HealthExporter

**Date:** 2026-03-18
**Bundle ID:** `com.evanhoffman.HealthExporter`
**Platform:** iOS 26+, iPhone
**Version:** 2.4.6

This note tracks the current App Store review posture for the `2.4.6` submission and the cleanup items worth resolving before the next upload.

## Confirmed

- Production HealthKit access is read-only: `requestAuthorization(toShare: Set(), read: ...)`.
- Clinical Health Records are only requested when selected lab-result export requires them.
- Simulator-only test data generation is gated behind `#if targetEnvironment(simulator)`.
- The current build settings include the required HealthKit and Clinical Health Records usage strings.
- The full unit test suite passes locally on the simulator.

## Cleanup Still Worth Doing

- Export errors should distinguish HealthKit query failures from a genuinely empty result set.
- `Last X Days` should be clarified or corrected so the date window matches the label.
- Lab-result date filtering should be pushed down into the query path instead of filtering after fetch.
- The testing guide should use a collision-resistant simulator destination.

## Notes

- `NSHealthUpdateUsageDescription` is still present because the simulator-only write path still references `healthStore.save(...)`.
- The app icon asset catalog now includes the declared dark and tinted variants, using the same 1024x1024 source image.
- The app remains privacy-first: no health data is persisted beyond the export flow, and no analytics or account system is present.
