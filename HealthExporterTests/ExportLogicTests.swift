import Foundation
import Testing
import HealthKit
@testable import HealthExporter

struct ExportLogicTests {

    private let now = Date()
    private let calendar = Calendar(identifier: .gregorian)

    // MARK: - isExportEnabled

    @Test func exportDisabled_noMetricsSelected() {
        #expect(!ExportLogic.isExportEnabled(
            exportWeight: false, exportSteps: false, exportGlucose: false, hasSelectedLabs: false,
            dateRangeOption: .lastXDays, startDate: now, endDate: now
        ))
    }

    @Test func exportEnabled_weightOnly_lastXDays() {
        #expect(ExportLogic.isExportEnabled(
            exportWeight: true, exportSteps: false, exportGlucose: false, hasSelectedLabs: false,
            dateRangeOption: .lastXDays, startDate: now, endDate: now
        ))
    }

    @Test func exportEnabled_stepsOnly_lastXRecords() {
        #expect(ExportLogic.isExportEnabled(
            exportWeight: false, exportSteps: true, exportGlucose: false, hasSelectedLabs: false,
            dateRangeOption: .lastXRecords, startDate: now, endDate: now
        ))
    }

    @Test func exportEnabled_glucoseOnly_allRecords() {
        #expect(ExportLogic.isExportEnabled(
            exportWeight: false, exportSteps: false, exportGlucose: true, hasSelectedLabs: false,
            dateRangeOption: .allRecords, startDate: now, endDate: now
        ))
    }

    @Test func exportEnabled_vitalsOnly_lastXDays() {
        #expect(ExportLogic.isExportEnabled(
            exportWeight: false, exportSteps: false, exportGlucose: false, hasSelectedLabs: false, hasSelectedVitals: true,
            dateRangeOption: .lastXDays, startDate: now, endDate: now
        ))
    }

    @Test func exportEnabled_a1cOnly_specificDateRange_validRange() {
        let start = calendar.date(byAdding: .day, value: -7, to: now)!
        #expect(ExportLogic.isExportEnabled(
            exportWeight: false, exportSteps: false, exportGlucose: false, hasSelectedLabs: true,
            dateRangeOption: .specificDateRange, startDate: start, endDate: now
        ))
    }

    @Test func exportDisabled_specificDateRange_invalidRange() {
        let start = calendar.date(byAdding: .day, value: 7, to: now)!
        #expect(!ExportLogic.isExportEnabled(
            exportWeight: true, exportSteps: true, exportGlucose: true, hasSelectedLabs: true,
            dateRangeOption: .specificDateRange, startDate: start, endDate: now
        ))
    }

    @Test func exportEnabled_specificDateRange_sameDay() {
        #expect(ExportLogic.isExportEnabled(
            exportWeight: true, exportSteps: false, exportGlucose: false, hasSelectedLabs: false,
            dateRangeOption: .specificDateRange, startDate: now, endDate: now
        ))
    }

    @Test func exportEnabled_allMetricsSelected() {
        #expect(ExportLogic.isExportEnabled(
            exportWeight: true, exportSteps: true, exportGlucose: true, hasSelectedLabs: true,
            dateRangeOption: .lastXDays, startDate: now, endDate: now
        ))
    }

    /// The Range dates stay in state when another option is picked. An end
    /// before the start must not disable the other options (#120).
    @Test(arguments: [DateRangeOption.lastXDays, .lastXRecords, .allRecords])
    func exportEnabled_invalidRangeDates_ignoredByOtherOptions(_ option: DateRangeOption) {
        let start = calendar.date(byAdding: .day, value: 7, to: now)!
        #expect(ExportLogic.isExportEnabled(
            exportWeight: true, exportSteps: false, exportGlucose: false, hasSelectedLabs: false,
            dateRangeOption: option, startDate: start, endDate: now
        ))
    }

    /// The view derives `hasSelectedLabs` from the panels and the single labs.
    /// A panel alone, or one lab alone, must enable export (#120).
    @Test func exportEnabled_labsFromAPanelOrASingleLab() {
        let panelOnly = ExportLogic.resolveLabMetrics(selectedPanels: [.thyroid], favoriteCodes: [])
        let singleLab = ExportLogic.resolveLabMetrics(selectedPanels: [], favoriteCodes: [LOINCCode.hemoglobinA1C])
        let none = ExportLogic.resolveLabMetrics(selectedPanels: [], favoriteCodes: [])

        for (labs, expected) in [(panelOnly, true), (singleLab, true), (none, false)] {
            #expect(ExportLogic.isExportEnabled(
                exportWeight: false, exportSteps: false, exportGlucose: false, hasSelectedLabs: !labs.isEmpty,
                dateRangeOption: .lastXDays, startDate: now, endDate: now
            ) == expected)
        }
    }

    // MARK: - dateRange

    @Test func dateRange_lastXDays_returns7DayRange() {
        let result = ExportLogic.dateRange(
            for: .lastXDays, lastXDays: 7,
            specificStart: now, specificEnd: now,
            now: now, calendar: calendar
        )
        #expect(result != nil)
        let expected = calendar.date(byAdding: .day, value: -6, to: now)!
        #expect(abs(result!.startDate.timeIntervalSinceReferenceDate - expected.timeIntervalSinceReferenceDate) <= 1)
        #expect(abs(result!.endDate.timeIntervalSinceReferenceDate - now.timeIntervalSinceReferenceDate) <= 1)
    }

    @Test func dateRange_lastXDays_returns30DayRange() {
        let result = ExportLogic.dateRange(
            for: .lastXDays, lastXDays: 30,
            specificStart: now, specificEnd: now,
            now: now, calendar: calendar
        )
        #expect(result != nil)
        let expected = calendar.date(byAdding: .day, value: -29, to: now)!
        #expect(abs(result!.startDate.timeIntervalSinceReferenceDate - expected.timeIntervalSinceReferenceDate) <= 1)
    }

    @Test func firstFetchError_returnsWeightErrorFirst() {
        let underlying = NSError(domain: "HKErrorDomain", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Weight failed"
        ])

        let error = ExportLogic.firstFetchError(
            weightError: underlying,
            stepsError: nil,
            glucoseError: nil,
            labError: nil
        )

        #expect(error?.localizedDescription == "Failed to fetch Weight data: Weight failed")
    }

    @Test func firstFetchError_prefersEarlierSelectedMetric() {
        let stepsError = NSError(domain: "HKErrorDomain", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Steps failed"
        ])
        let labError = NSError(domain: "HKErrorDomain", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "A1C failed"
        ])

        let error = ExportLogic.firstFetchError(
            weightError: nil,
            stepsError: stepsError,
            glucoseError: nil,
            labError: labError
        )

        #expect(error?.localizedDescription == "Failed to fetch Steps data: Steps failed")
    }

    @Test func firstFetchError_labErrorUsesLabResultsLabel() {
        let labError = NSError(domain: "HKErrorDomain", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "lab failed"
        ])

        let error = ExportLogic.firstFetchError(
            weightError: nil,
            stepsError: nil,
            glucoseError: nil,
            labError: labError
        )

        #expect(error?.localizedDescription == "Failed to fetch Lab Results data: lab failed")
    }

    @Test func firstFetchError_vitalErrorUsesVitalsLabel() {
        let vitalError = NSError(domain: "HKErrorDomain", code: 5, userInfo: [
            NSLocalizedDescriptionKey: "vitals failed"
        ])

        let error = ExportLogic.firstFetchError(
            weightError: nil,
            stepsError: nil,
            glucoseError: nil,
            labError: nil,
            vitalError: vitalError
        )

        #expect(error?.localizedDescription == "Failed to fetch Vitals data: vitals failed")
    }

    @Test func dateRange_lastXRecords_returnsNil() {
        let result = ExportLogic.dateRange(
            for: .lastXRecords, lastXDays: 7,
            specificStart: now, specificEnd: now,
            now: now, calendar: calendar
        )
        #expect(result == nil)
    }

    @Test func dateRange_allRecords_returnsNil() {
        let result = ExportLogic.dateRange(
            for: .allRecords, lastXDays: 7,
            specificStart: now, specificEnd: now,
            now: now, calendar: calendar
        )
        #expect(result == nil)
    }

    @Test func dateRange_specificDateRange_returnsProvidedDates() {
        let start = calendar.date(byAdding: .day, value: -14, to: now)!
        let end = calendar.date(byAdding: .day, value: -1, to: now)!
        let result = ExportLogic.dateRange(
            for: .specificDateRange, lastXDays: 7,
            specificStart: start, specificEnd: end,
            now: now, calendar: calendar
        )
        #expect(result != nil)
        #expect(result!.startDate == start)
        #expect(result!.endDate == end)
    }

    // MARK: - recordLimit

    @Test func recordLimit_lastXDays_isNoLimit() {
        #expect(ExportLogic.recordLimit(for: .lastXDays, lastXRecords: 100) == HKObjectQueryNoLimit)
    }

    @Test func recordLimit_allRecords_isNoLimit() {
        #expect(ExportLogic.recordLimit(for: .allRecords, lastXRecords: 100) == HKObjectQueryNoLimit)
    }

    @Test func recordLimit_specificDateRange_isNoLimit() {
        #expect(ExportLogic.recordLimit(for: .specificDateRange, lastXRecords: 100) == HKObjectQueryNoLimit)
    }

    @Test func recordLimit_lastXRecords_returnsValue() {
        #expect(ExportLogic.recordLimit(for: .lastXRecords, lastXRecords: 250) == 250)
    }

    @Test func recordLimit_lastXRecords_returnsExactValue() {
        #expect(ExportLogic.recordLimit(for: .lastXRecords, lastXRecords: 1) == 1)
        #expect(ExportLogic.recordLimit(for: .lastXRecords, lastXRecords: 10000) == 10000)
    }

    // MARK: - resolveLabMetrics

    private static let lipid1 = LabMetric(name: "Total Cholesterol", loincCode: "2093-3", group: .lipid, valuePrecision: 0)
    private static let lipid2 = LabMetric(name: "HDL Cholesterol",   loincCode: "2085-9", group: .lipid, valuePrecision: 0)
    private static let other1 = LabMetric(name: "Hemoglobin A1C",    loincCode: "4548-4", group: .other, valuePrecision: 2)
    private static let stubRegistry: [LabMetric] = [lipid1, lipid2, other1]

    @Test func resolveLabMetrics_noPanelsNoFavorites_returnsEmpty() {
        let result = ExportLogic.resolveLabMetrics(
            selectedPanels: [],
            favoriteCodes: [],
            registry: Self.stubRegistry
        )
        #expect(result.isEmpty)
    }

    @Test func resolveLabMetrics_panelOnly_returnsAllMetricsInPanel() {
        let result = ExportLogic.resolveLabMetrics(
            selectedPanels: [.lipid],
            favoriteCodes: [],
            registry: Self.stubRegistry
        )
        #expect(Set(result.map(\.loincCode)) == ["2093-3", "2085-9"])
    }

    @Test func resolveLabMetrics_favoritesOnly_returnsFavorites() {
        let result = ExportLogic.resolveLabMetrics(
            selectedPanels: [],
            favoriteCodes: ["4548-4"],
            registry: Self.stubRegistry
        )
        #expect(result.map(\.loincCode) == ["4548-4"])
    }

    @Test func resolveLabMetrics_panelAndFavorite_deduplicates() {
        // Lipid panel already contains 2093-3; adding it as a favorite must not double up.
        let result = ExportLogic.resolveLabMetrics(
            selectedPanels: [.lipid],
            favoriteCodes: ["2093-3"],
            registry: Self.stubRegistry
        )
        #expect(result.count == 2)
        #expect(Set(result.map(\.loincCode)) == ["2093-3", "2085-9"])
    }

    @Test func resolveLabMetrics_favoriteFromAnotherPanel_isStillIncluded() {
        let result = ExportLogic.resolveLabMetrics(
            selectedPanels: [.lipid],
            favoriteCodes: ["4548-4"],
            registry: Self.stubRegistry
        )
        #expect(Set(result.map(\.loincCode)) == ["2093-3", "2085-9", "4548-4"])
    }

    @Test func resolveLabMetrics_unknownFavoriteCode_isIgnored() {
        let result = ExportLogic.resolveLabMetrics(
            selectedPanels: [],
            favoriteCodes: ["9999-9"],
            registry: Self.stubRegistry
        )
        #expect(result.isEmpty)
    }

    // MARK: - hasAnyData

    @Test func hasAnyData_allNil_returnsFalse() {
        #expect(!ExportLogic.hasAnyData(
            weightSamples: nil, stepsSamples: nil,
            glucoseSamples: nil, labResults: nil
        ))
    }

    @Test func hasAnyData_allEmpty_returnsFalse() {
        #expect(!ExportLogic.hasAnyData(
            weightSamples: [], stepsSamples: [],
            glucoseSamples: [], labResults: []
        ))
    }

    @Test func hasAnyData_withLabResults_returnsTrue() {
        let sample = LabResultSample(
            metricName: "Hemoglobin A1C",
            loincCode: LOINCCode.hemoglobinA1C,
            effectiveDateTime: now,
            value: 7.0,
            unit: "%"
        )
        #expect(ExportLogic.hasAnyData(
            weightSamples: nil, stepsSamples: nil,
            glucoseSamples: nil, labResults: [sample]
        ))
    }

    @Test func hasAnyData_withWeightSamples_returnsTrue() {
        let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let sample = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .pound(), doubleValue: 180),
            start: now, end: now
        )
        #expect(ExportLogic.hasAnyData(
            weightSamples: [sample], stepsSamples: nil,
            glucoseSamples: nil, labResults: nil
        ))
    }

    @Test func hasAnyData_withVitalSamples_returnsTrue() {
        let oxygenType = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!
        let sample = HKQuantitySample(
            type: oxygenType,
            quantity: HKQuantity(unit: .percent(), doubleValue: 0.98),
            start: now,
            end: now
        )

        #expect(ExportLogic.hasAnyData(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: nil,
            vitalSamples: [.oxygenSaturation: [sample]]
        ))
    }

    @Test func hasAnyData_mixedNilAndEmpty_returnsFalse() {
        #expect(!ExportLogic.hasAnyData(
            weightSamples: nil, stepsSamples: [],
            glucoseSamples: nil, labResults: []
        ))
    }

    // MARK: - exportFilename

    @Test func exportFilename_matchesExpectedFormat() {
        let filename = ExportLogic.exportFilename(for: now)
        #expect(filename.hasPrefix("HealthExporter_"))
        #expect(filename.hasSuffix(".csv"))
    }

    @Test func exportFilename_containsDate() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: now)

        let filename = ExportLogic.exportFilename(for: now)
        #expect(filename.contains(dateStr))
    }

    @Test func exportFilename_deterministicForSameDate() {
        let fixedDate = ISO8601DateFormatter().date(from: "2024-06-15T14:30:45Z")!
        let filename = ExportLogic.exportFilename(for: fixedDate)
        // The exact filename depends on the local timezone, but the format should be consistent
        #expect(filename.hasPrefix("HealthExporter_2024-06-15_"))
        #expect(filename.hasSuffix(".csv"))
    }

    @Test func exportFilename_exactOutputInUTC() {
        let fixedDate = ISO8601DateFormatter().date(from: "2024-06-15T14:30:45Z")!
        let filename = ExportLogic.exportFilename(for: fixedDate, timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(filename == "HealthExporter_2024-06-15_143045.csv")
    }

    @Test func filenameFormatter_usesGregorianPOSIX() {
        let formatter = ExportLogic.makeFilenameFormatter(timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(formatter.calendar.identifier == .gregorian)
        #expect(formatter.locale.identifier == "en_US_POSIX")
    }
}
