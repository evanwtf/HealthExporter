import XCTest
import HealthKit
@testable import HealthExporter

final class ExportLogicTests: XCTestCase {

    private let now = Date()
    private let calendar = Calendar(identifier: .gregorian)

    // MARK: - isExportEnabled

    func testExportDisabled_noMetricsSelected() {
        XCTAssertFalse(ExportLogic.isExportEnabled(
            exportWeight: false, exportSteps: false, exportGlucose: false, hasSelectedLabs: false,
            dateRangeOption: .lastXDays, startDate: now, endDate: now
        ))
    }

    func testExportEnabled_weightOnly_lastXDays() {
        XCTAssertTrue(ExportLogic.isExportEnabled(
            exportWeight: true, exportSteps: false, exportGlucose: false, hasSelectedLabs: false,
            dateRangeOption: .lastXDays, startDate: now, endDate: now
        ))
    }

    func testExportEnabled_stepsOnly_lastXRecords() {
        XCTAssertTrue(ExportLogic.isExportEnabled(
            exportWeight: false, exportSteps: true, exportGlucose: false, hasSelectedLabs: false,
            dateRangeOption: .lastXRecords, startDate: now, endDate: now
        ))
    }

    func testExportEnabled_glucoseOnly_allRecords() {
        XCTAssertTrue(ExportLogic.isExportEnabled(
            exportWeight: false, exportSteps: false, exportGlucose: true, hasSelectedLabs: false,
            dateRangeOption: .allRecords, startDate: now, endDate: now
        ))
    }

    func testExportEnabled_vitalsOnly_lastXDays() {
        XCTAssertTrue(ExportLogic.isExportEnabled(
            exportWeight: false, exportSteps: false, exportGlucose: false, hasSelectedLabs: false, hasSelectedVitals: true,
            dateRangeOption: .lastXDays, startDate: now, endDate: now
        ))
    }

    func testExportEnabled_a1cOnly_specificDateRange_validRange() {
        let start = calendar.date(byAdding: .day, value: -7, to: now)!
        XCTAssertTrue(ExportLogic.isExportEnabled(
            exportWeight: false, exportSteps: false, exportGlucose: false, hasSelectedLabs: true,
            dateRangeOption: .specificDateRange, startDate: start, endDate: now
        ))
    }

    func testExportDisabled_specificDateRange_invalidRange() {
        let start = calendar.date(byAdding: .day, value: 7, to: now)!
        XCTAssertFalse(ExportLogic.isExportEnabled(
            exportWeight: true, exportSteps: true, exportGlucose: true, hasSelectedLabs: true,
            dateRangeOption: .specificDateRange, startDate: start, endDate: now
        ))
    }

    func testExportEnabled_specificDateRange_sameDay() {
        XCTAssertTrue(ExportLogic.isExportEnabled(
            exportWeight: true, exportSteps: false, exportGlucose: false, hasSelectedLabs: false,
            dateRangeOption: .specificDateRange, startDate: now, endDate: now
        ))
    }

    func testExportEnabled_allMetricsSelected() {
        XCTAssertTrue(ExportLogic.isExportEnabled(
            exportWeight: true, exportSteps: true, exportGlucose: true, hasSelectedLabs: true,
            dateRangeOption: .lastXDays, startDate: now, endDate: now
        ))
    }

    // MARK: - dateRange

    func testDateRange_lastXDays_returns7DayRange() {
        let result = ExportLogic.dateRange(
            for: .lastXDays, lastXDays: 7,
            specificStart: now, specificEnd: now,
            now: now, calendar: calendar
        )
        XCTAssertNotNil(result)
        let expected = calendar.date(byAdding: .day, value: -6, to: now)!
        XCTAssertEqual(result!.startDate.timeIntervalSinceReferenceDate,
                       expected.timeIntervalSinceReferenceDate, accuracy: 1)
        XCTAssertEqual(result!.endDate.timeIntervalSinceReferenceDate,
                       now.timeIntervalSinceReferenceDate, accuracy: 1)
    }

    func testDateRange_lastXDays_returns30DayRange() {
        let result = ExportLogic.dateRange(
            for: .lastXDays, lastXDays: 30,
            specificStart: now, specificEnd: now,
            now: now, calendar: calendar
        )
        XCTAssertNotNil(result)
        let expected = calendar.date(byAdding: .day, value: -29, to: now)!
        XCTAssertEqual(result!.startDate.timeIntervalSinceReferenceDate,
                       expected.timeIntervalSinceReferenceDate, accuracy: 1)
    }

    func testFirstFetchError_returnsWeightErrorFirst() {
        let underlying = NSError(domain: "HKErrorDomain", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Weight failed"
        ])

        let error = ExportLogic.firstFetchError(
            weightError: underlying,
            stepsError: nil,
            glucoseError: nil,
            labError: nil
        )

        XCTAssertEqual(
            error?.localizedDescription,
            "Failed to fetch Weight data: Weight failed"
        )
    }

    func testFirstFetchError_prefersEarlierSelectedMetric() {
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

        XCTAssertEqual(
            error?.localizedDescription,
            "Failed to fetch Steps data: Steps failed"
        )
    }

    func testFirstFetchError_labErrorUsesLabResultsLabel() {
        let labError = NSError(domain: "HKErrorDomain", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "lab failed"
        ])

        let error = ExportLogic.firstFetchError(
            weightError: nil,
            stepsError: nil,
            glucoseError: nil,
            labError: labError
        )

        XCTAssertEqual(
            error?.localizedDescription,
            "Failed to fetch Lab Results data: lab failed"
        )
    }

    func testFirstFetchError_vitalErrorUsesVitalsLabel() {
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

        XCTAssertEqual(
            error?.localizedDescription,
            "Failed to fetch Vitals data: vitals failed"
        )
    }

    func testDateRange_lastXRecords_returnsNil() {
        let result = ExportLogic.dateRange(
            for: .lastXRecords, lastXDays: 7,
            specificStart: now, specificEnd: now,
            now: now, calendar: calendar
        )
        XCTAssertNil(result)
    }

    func testDateRange_allRecords_returnsNil() {
        let result = ExportLogic.dateRange(
            for: .allRecords, lastXDays: 7,
            specificStart: now, specificEnd: now,
            now: now, calendar: calendar
        )
        XCTAssertNil(result)
    }

    func testDateRange_specificDateRange_returnsProvidedDates() {
        let start = calendar.date(byAdding: .day, value: -14, to: now)!
        let end = calendar.date(byAdding: .day, value: -1, to: now)!
        let result = ExportLogic.dateRange(
            for: .specificDateRange, lastXDays: 7,
            specificStart: start, specificEnd: end,
            now: now, calendar: calendar
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.startDate, start)
        XCTAssertEqual(result!.endDate, end)
    }

    // MARK: - recordLimit

    func testRecordLimit_lastXDays_isNoLimit() {
        XCTAssertEqual(ExportLogic.recordLimit(for: .lastXDays, lastXRecords: 100), HKObjectQueryNoLimit)
    }

    func testRecordLimit_allRecords_isNoLimit() {
        XCTAssertEqual(ExportLogic.recordLimit(for: .allRecords, lastXRecords: 100), HKObjectQueryNoLimit)
    }

    func testRecordLimit_specificDateRange_isNoLimit() {
        XCTAssertEqual(ExportLogic.recordLimit(for: .specificDateRange, lastXRecords: 100), HKObjectQueryNoLimit)
    }

    func testRecordLimit_lastXRecords_returnsValue() {
        XCTAssertEqual(ExportLogic.recordLimit(for: .lastXRecords, lastXRecords: 250), 250)
    }

    func testRecordLimit_lastXRecords_returnsExactValue() {
        XCTAssertEqual(ExportLogic.recordLimit(for: .lastXRecords, lastXRecords: 1), 1)
        XCTAssertEqual(ExportLogic.recordLimit(for: .lastXRecords, lastXRecords: 10000), 10000)
    }

    // MARK: - resolveLabMetrics

    private static let lipid1 = LabMetric(name: "Total Cholesterol", loincCode: "2093-3", group: .lipid, valuePrecision: 0)
    private static let lipid2 = LabMetric(name: "HDL Cholesterol",   loincCode: "2085-9", group: .lipid, valuePrecision: 0)
    private static let other1 = LabMetric(name: "Hemoglobin A1C",    loincCode: "4548-4", group: .other, valuePrecision: 2)
    private static let stubRegistry: [LabMetric] = [lipid1, lipid2, other1]

    func testResolveLabMetrics_noPanelsNoFavorites_returnsEmpty() {
        let result = ExportLogic.resolveLabMetrics(
            selectedPanels: [],
            favoriteCodes: [],
            registry: Self.stubRegistry
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testResolveLabMetrics_panelOnly_returnsAllMetricsInPanel() {
        let result = ExportLogic.resolveLabMetrics(
            selectedPanels: [.lipid],
            favoriteCodes: [],
            registry: Self.stubRegistry
        )
        XCTAssertEqual(Set(result.map(\.loincCode)), ["2093-3", "2085-9"])
    }

    func testResolveLabMetrics_favoritesOnly_returnsFavorites() {
        let result = ExportLogic.resolveLabMetrics(
            selectedPanels: [],
            favoriteCodes: ["4548-4"],
            registry: Self.stubRegistry
        )
        XCTAssertEqual(result.map(\.loincCode), ["4548-4"])
    }

    func testResolveLabMetrics_panelAndFavorite_deduplicates() {
        // Lipid panel already contains 2093-3; adding it as a favorite must not double up.
        let result = ExportLogic.resolveLabMetrics(
            selectedPanels: [.lipid],
            favoriteCodes: ["2093-3"],
            registry: Self.stubRegistry
        )
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.loincCode)), ["2093-3", "2085-9"])
    }

    func testResolveLabMetrics_favoriteFromAnotherPanel_isStillIncluded() {
        let result = ExportLogic.resolveLabMetrics(
            selectedPanels: [.lipid],
            favoriteCodes: ["4548-4"],
            registry: Self.stubRegistry
        )
        XCTAssertEqual(Set(result.map(\.loincCode)), ["2093-3", "2085-9", "4548-4"])
    }

    func testResolveLabMetrics_unknownFavoriteCode_isIgnored() {
        let result = ExportLogic.resolveLabMetrics(
            selectedPanels: [],
            favoriteCodes: ["9999-9"],
            registry: Self.stubRegistry
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - hasAnyData

    func testHasAnyData_allNil_returnsFalse() {
        XCTAssertFalse(ExportLogic.hasAnyData(
            weightSamples: nil, stepsSamples: nil,
            glucoseSamples: nil, labResults: nil
        ))
    }

    func testHasAnyData_allEmpty_returnsFalse() {
        XCTAssertFalse(ExportLogic.hasAnyData(
            weightSamples: [], stepsSamples: [],
            glucoseSamples: [], labResults: []
        ))
    }

    func testHasAnyData_withLabResults_returnsTrue() {
        let sample = LabResultSample(
            metricName: "Hemoglobin A1C",
            loincCode: LOINCCode.hemoglobinA1C,
            effectiveDateTime: now,
            value: 7.0,
            unit: "%"
        )
        XCTAssertTrue(ExportLogic.hasAnyData(
            weightSamples: nil, stepsSamples: nil,
            glucoseSamples: nil, labResults: [sample]
        ))
    }

    func testHasAnyData_withWeightSamples_returnsTrue() {
        let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let sample = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .pound(), doubleValue: 180),
            start: now, end: now
        )
        XCTAssertTrue(ExportLogic.hasAnyData(
            weightSamples: [sample], stepsSamples: nil,
            glucoseSamples: nil, labResults: nil
        ))
    }

    func testHasAnyData_withVitalSamples_returnsTrue() {
        let oxygenType = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!
        let sample = HKQuantitySample(
            type: oxygenType,
            quantity: HKQuantity(unit: .percent(), doubleValue: 0.98),
            start: now,
            end: now
        )

        XCTAssertTrue(ExportLogic.hasAnyData(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: nil,
            vitalSamples: [.oxygenSaturation: [sample]]
        ))
    }

    func testHasAnyData_mixedNilAndEmpty_returnsFalse() {
        XCTAssertFalse(ExportLogic.hasAnyData(
            weightSamples: nil, stepsSamples: [],
            glucoseSamples: nil, labResults: []
        ))
    }

    // MARK: - exportFilename

    func testExportFilename_matchesExpectedFormat() {
        let filename = ExportLogic.exportFilename(for: now)
        XCTAssertTrue(filename.hasPrefix("HealthExporter_"))
        XCTAssertTrue(filename.hasSuffix(".csv"))
    }

    func testExportFilename_containsDate() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: now)

        let filename = ExportLogic.exportFilename(for: now)
        XCTAssertTrue(filename.contains(dateStr))
    }

    func testExportFilename_deterministicForSameDate() {
        let fixedDate = ISO8601DateFormatter().date(from: "2024-06-15T14:30:45Z")!
        let filename = ExportLogic.exportFilename(for: fixedDate)
        // The exact filename depends on the local timezone, but the format should be consistent
        XCTAssertTrue(filename.hasPrefix("HealthExporter_2024-06-15_"))
        XCTAssertTrue(filename.hasSuffix(".csv"))
    }
}
