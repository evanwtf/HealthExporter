import Foundation
import HealthKit

/// Pure logic extracted from DataSelectionView for testability.
enum ExportLogic {

    /// Whether the export button should be enabled.
    static func isExportEnabled(
        exportWeight: Bool,
        exportSteps: Bool,
        exportGlucose: Bool,
        hasSelectedLabs: Bool,
        dateRangeOption: DateRangeOption,
        startDate: Date,
        endDate: Date
    ) -> Bool {
        let hasSelectedMetric = exportWeight || exportSteps || exportGlucose || hasSelectedLabs
        guard hasSelectedMetric else { return false }

        switch dateRangeOption {
        case .lastXDays, .lastXRecords, .allRecords:
            return true
        case .specificDateRange:
            return startDate <= endDate
        }
    }

    /// Resolves the concrete LabMetric instances to fetch given the user's
    /// selected panels and curated favorite LOINC codes. Favorites and panel
    /// memberships are unioned, then deduplicated by LOINC code.
    static func resolveLabMetrics(
        selectedPanels: Set<LabPanel>,
        favoriteCodes: Set<String>,
        registry: [LabMetric] = LabMetricRegistry.all
    ) -> [LabMetric] {
        let panelCodes = registry
            .filter { selectedPanels.contains($0.group) }
            .map(\.loincCode)
        let allCodes = Set(panelCodes).union(favoriteCodes)
        return registry.filter { allCodes.contains($0.loincCode) }
    }

    /// Computes the date range for a given option, or nil when not applicable.
    static func dateRange(
        for option: DateRangeOption,
        lastXDays: Int,
        specificStart: Date,
        specificEnd: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (startDate: Date, endDate: Date)? {
        switch option {
        case .lastXDays:
            let offset = max(lastXDays - 1, 0)
            if let start = calendar.date(byAdding: .day, value: -offset, to: now) {
                return (start, now)
            }
            return nil
        case .lastXRecords:
            return nil
        case .specificDateRange:
            return (specificStart, specificEnd)
        case .allRecords:
            return nil
        }
    }

    /// Returns the first fetch error in display order for the selected metrics.
    static func firstFetchError(
        weightError: Error?,
        stepsError: Error?,
        glucoseError: Error?,
        labError: Error?
    ) -> ExportError? {
        if let weightError {
            return .healthKitQueryFailed(metric: HealthMetrics.weight.name, underlying: weightError)
        }
        if let stepsError {
            return .healthKitQueryFailed(metric: HealthMetrics.steps.name, underlying: stepsError)
        }
        if let glucoseError {
            return .healthKitQueryFailed(metric: HealthMetrics.glucose.name, underlying: glucoseError)
        }
        if let labError {
            return .healthKitQueryFailed(metric: "Lab Results", underlying: labError)
        }
        return nil
    }

    /// Computes the record limit for a given option.
    static func recordLimit(for option: DateRangeOption, lastXRecords: Int) -> Int {
        switch option {
        case .lastXDays, .allRecords, .specificDateRange:
            return HKObjectQueryNoLimit
        case .lastXRecords:
            return lastXRecords
        }
    }

    /// Whether any fetched data exists across all sample arrays.
    static func hasAnyData(
        weightSamples: [HKQuantitySample]?,
        stepsSamples: [HKQuantitySample]?,
        glucoseSamples: [GlucoseSampleMgDl]?,
        labResults: [LabResultSample]?
    ) -> Bool {
        (weightSamples?.isEmpty == false) ||
        (stepsSamples?.isEmpty == false) ||
        (glucoseSamples?.isEmpty == false) ||
        (labResults?.isEmpty == false)
    }

    /// Generates the export filename for a given date.
    static func exportFilename(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return "HealthExporter_\(formatter.string(from: date)).csv"
    }
}
