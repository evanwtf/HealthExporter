import XCTest
import HealthKit
@testable import HealthExporter

final class HealthKitQueryHelpersTests: XCTestCase {

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: "America/New_York")
        return calendar.date(from: components)!
    }

    // MARK: - readTypes

    func testReadTypes_withoutLabs_containsBaseTypes() {
        let types = HealthKitQueryHelpers.readTypes(
            includeWeight: true, includeSteps: true, includeGlucose: true, includeLabs: false
        )

        let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!

        XCTAssertTrue(types.contains(weightType))
        XCTAssertTrue(types.contains(stepsType))
        XCTAssertTrue(types.contains(glucoseType))
        XCTAssertEqual(types.count, 3)
    }

    func testReadTypes_withLabs_containsClinicalType() {
        let types = HealthKitQueryHelpers.readTypes(
            includeWeight: true, includeSteps: true, includeGlucose: true, includeLabs: true
        )

        let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!

        XCTAssertTrue(types.contains(weightType))
        XCTAssertTrue(types.contains(stepsType))
        XCTAssertTrue(types.contains(glucoseType))

        if let clinicalType = HKObjectType.clinicalType(forIdentifier: .labResultRecord) {
            XCTAssertTrue(types.contains(clinicalType))
            XCTAssertEqual(types.count, 4)
        } else {
            // On platforms where clinical types aren't available
            XCTAssertEqual(types.count, 3)
        }
    }

    func testReadTypes_withoutLabs_doesNotContainClinical() {
        let types = HealthKitQueryHelpers.readTypes(
            includeWeight: true, includeSteps: true, includeGlucose: true, includeLabs: false
        )
        if let clinicalType = HKObjectType.clinicalType(forIdentifier: .labResultRecord) {
            XCTAssertFalse(types.contains(clinicalType))
        }
    }

    func testReadTypes_withVitals_containsSelectedVitalQuantityTypes() {
        let types = HealthKitQueryHelpers.readTypes(
            includeWeight: true,
            includeSteps: true,
            includeGlucose: true,
            includeLabs: false,
            vitalMetrics: [.bloodPressure, .oxygenSaturation]
        )

        let systolic = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic)!
        let diastolic = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic)!
        let oxygen = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!

        XCTAssertTrue(types.contains(systolic))
        XCTAssertTrue(types.contains(diastolic))
        XCTAssertTrue(types.contains(oxygen))
        XCTAssertEqual(types.count, 6)
    }

    func testReadTypes_vitalsOnly_omitsWeightStepsAndGlucose() {
        let types = HealthKitQueryHelpers.readTypes(
            includeWeight: false,
            includeSteps: false,
            includeGlucose: false,
            includeLabs: false,
            vitalMetrics: [.bloodPressure]
        )

        XCTAssertEqual(types, [
            HKQuantityType(.bloodPressureSystolic),
            HKQuantityType(.bloodPressureDiastolic),
        ])
    }

    func testReadTypes_labsOnly_containsOnlyClinicalType() {
        let types = HealthKitQueryHelpers.readTypes(
            includeWeight: false, includeSteps: false, includeGlucose: false, includeLabs: true
        )

        if let clinicalType = HKObjectType.clinicalType(forIdentifier: .labResultRecord) {
            XCTAssertEqual(types, [clinicalType])
        } else {
            XCTAssertTrue(types.isEmpty)
        }
    }

    // MARK: - dayAlignedRange

    func testDayAlignedRange_alignsToStartOfDay() {
        let start = date(2024, 6, 15, 14, 30) // 2:30 PM
        let end = date(2024, 6, 20, 9, 15)   // 9:15 AM

        let result = HealthKitQueryHelpers.dayAlignedRange(from: (start, end), calendar: calendar)

        XCTAssertNotNil(result)
        let startComponents = calendar.dateComponents([.hour, .minute, .second], from: result!.start)
        XCTAssertEqual(startComponents.hour, 0)
        XCTAssertEqual(startComponents.minute, 0)
        XCTAssertEqual(startComponents.second, 0)
    }

    func testDayAlignedRange_endIsNextDayMidnight() {
        let start = date(2024, 6, 15)
        let end = date(2024, 6, 20)

        let result = HealthKitQueryHelpers.dayAlignedRange(from: (start, end), calendar: calendar)

        XCTAssertNotNil(result)
        // End should be start of June 21
        let endComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result!.end)
        XCTAssertEqual(endComponents.year, 2024)
        XCTAssertEqual(endComponents.month, 6)
        XCTAssertEqual(endComponents.day, 21)
        XCTAssertEqual(endComponents.hour, 0)
        XCTAssertEqual(endComponents.minute, 0)
    }

    func testDayAlignedRange_sameDay_coversFullDay() {
        let day = date(2024, 6, 15, 14, 30)

        let result = HealthKitQueryHelpers.dayAlignedRange(from: (day, day), calendar: calendar)

        XCTAssertNotNil(result)
        let startDay = calendar.component(.day, from: result!.start)
        let endDay = calendar.component(.day, from: result!.end)
        XCTAssertEqual(startDay, 15)
        XCTAssertEqual(endDay, 16) // Next day midnight
    }

    func testDayAlignedRange_preservesStartDate() {
        let start = date(2024, 1, 1, 23, 59)
        let end = date(2024, 1, 31, 0, 1)

        let result = HealthKitQueryHelpers.dayAlignedRange(from: (start, end), calendar: calendar)

        XCTAssertNotNil(result)
        let startComponents = calendar.dateComponents([.year, .month, .day], from: result!.start)
        XCTAssertEqual(startComponents.year, 2024)
        XCTAssertEqual(startComponents.month, 1)
        XCTAssertEqual(startComponents.day, 1)
    }

    func testPredicateForDateRange_returnsPredicate() {
        let start = date(2024, 6, 15)
        let end = date(2024, 6, 20)

        let predicate = HealthKitQueryHelpers.predicateForDateRange((start, end), calendar: calendar)

        XCTAssertNotNil(predicate)
    }

    // MARK: - filterLabResultsByDateRange

    private func labSample(_ date: Date, value: Double = 7.0) -> LabResultSample {
        LabResultSample(
            metricName: "Hemoglobin A1C",
            loincCode: LOINCCode.hemoglobinA1C,
            effectiveDateTime: date,
            value: value,
            unit: "%"
        )
    }

    func testFilterLabResults_insideRange_included() {
        let sample = labSample(date(2024, 6, 17, 10, 0), value: 7.2)
        let range = (startDate: date(2024, 6, 15), endDate: date(2024, 6, 20))

        let filtered = HealthKitQueryHelpers.filterLabResultsByDateRange([sample], dateRange: range, calendar: calendar)
        XCTAssertEqual(filtered.count, 1)
    }

    func testFilterLabResults_beforeRange_excluded() {
        let sample = labSample(date(2024, 6, 14, 10, 0), value: 7.2)
        let range = (startDate: date(2024, 6, 15), endDate: date(2024, 6, 20))

        let filtered = HealthKitQueryHelpers.filterLabResultsByDateRange([sample], dateRange: range, calendar: calendar)
        XCTAssertEqual(filtered.count, 0)
    }

    func testFilterLabResults_afterRange_excluded() {
        let sample = labSample(date(2024, 6, 21, 10, 0), value: 7.2)
        let range = (startDate: date(2024, 6, 15), endDate: date(2024, 6, 20))

        let filtered = HealthKitQueryHelpers.filterLabResultsByDateRange([sample], dateRange: range, calendar: calendar)
        XCTAssertEqual(filtered.count, 0)
    }

    func testFilterLabResults_onStartDay_included() {
        let sample = labSample(date(2024, 6, 15, 0, 0), value: 6.5)
        let range = (startDate: date(2024, 6, 15), endDate: date(2024, 6, 20))

        let filtered = HealthKitQueryHelpers.filterLabResultsByDateRange([sample], dateRange: range, calendar: calendar)
        XCTAssertEqual(filtered.count, 1)
    }

    func testFilterLabResults_onEndDay_included() {
        let sample = labSample(date(2024, 6, 20, 23, 59), value: 6.5)
        let range = (startDate: date(2024, 6, 15), endDate: date(2024, 6, 20))

        let filtered = HealthKitQueryHelpers.filterLabResultsByDateRange([sample], dateRange: range, calendar: calendar)
        XCTAssertEqual(filtered.count, 1)
    }

    func testFilterLabResults_multipleSamples_filtersCorrectly() {
        let samples = [
            labSample(date(2024, 6, 14), value: 7.0), // before
            labSample(date(2024, 6, 15), value: 7.1), // start day
            labSample(date(2024, 6, 18), value: 7.2), // middle
            labSample(date(2024, 6, 20), value: 7.3), // end day
            labSample(date(2024, 6, 21), value: 7.4), // after
        ]
        let range = (startDate: date(2024, 6, 15), endDate: date(2024, 6, 20))

        let filtered = HealthKitQueryHelpers.filterLabResultsByDateRange(samples, dateRange: range, calendar: calendar)
        XCTAssertEqual(filtered.count, 3)
        XCTAssertEqual(filtered[0].value, 7.1, accuracy: 0.01)
        XCTAssertEqual(filtered[1].value, 7.2, accuracy: 0.01)
        XCTAssertEqual(filtered[2].value, 7.3, accuracy: 0.01)
    }

    func testFilterLabResults_emptySamples_returnsEmpty() {
        let range = (startDate: date(2024, 6, 15), endDate: date(2024, 6, 20))
        let filtered = HealthKitQueryHelpers.filterLabResultsByDateRange([], dateRange: range, calendar: calendar)
        XCTAssertTrue(filtered.isEmpty)
    }

    func testFilterLabResults_sameDay_includesFullDay() {
        let samples = [
            labSample(date(2024, 6, 15, 0, 0), value: 6.5),
            labSample(date(2024, 6, 15, 12, 0), value: 6.6),
            labSample(date(2024, 6, 15, 23, 59), value: 6.7),
        ]
        let range = (startDate: date(2024, 6, 15), endDate: date(2024, 6, 15))

        let filtered = HealthKitQueryHelpers.filterLabResultsByDateRange(samples, dateRange: range, calendar: calendar)
        XCTAssertEqual(filtered.count, 3)
    }

    // MARK: - generateWeightTestSamples

    func testGenerateWeightTestSamples_createsSixtyDailyWeightRecords() {
        var gmtCalendar = Calendar(identifier: .gregorian)
        gmtCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 20
        components.hour = 12
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)
        let referenceDate = gmtCalendar.date(from: components)!

        let samples = HealthKitQueryHelpers.generateWeightTestSamples(
            days: 60,
            referenceDate: referenceDate,
            calendar: gmtCalendar
        ) { index in
            80.0 + Double(index)
        }

        XCTAssertEqual(samples.count, 60)

        let firstDate = gmtCalendar.date(byAdding: .day, value: -59, to: referenceDate)!
        XCTAssertEqual(samples.first?.startDate, firstDate)
        XCTAssertEqual(samples.last?.startDate, referenceDate)

        for (index, sample) in samples.enumerated() {
            let expectedDate = gmtCalendar.date(byAdding: .day, value: index - 59, to: referenceDate)!
            XCTAssertEqual(sample.startDate, expectedDate)
            XCTAssertEqual(sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo)), 80.0 + Double(index), accuracy: 0.0001)
        }
    }

    func testSimulatorTestDataShareTypes_containsWeightType() {
        let shareTypes = HealthKitQueryHelpers.simulatorTestDataShareTypes()
        let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!

        XCTAssertEqual(shareTypes.count, 1)
        XCTAssertTrue(shareTypes.contains(weightType))
    }

    func testSimulatorTestDataFailureMessage_includesUnderlyingError() {
        let underlying = NSError(domain: "HealthKit", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Permission denied"
        ])

        let message = HealthKitQueryHelpers.simulatorTestDataFailureMessage(underlying)

        XCTAssertEqual(message, "Failed to generate weight data: Permission denied")
    }

    func testSimulatorTestDataFailureMessage_withoutUnderlyingError() {
        let message = HealthKitQueryHelpers.simulatorTestDataFailureMessage(nil)

        XCTAssertEqual(message, "Failed to generate weight data.")
    }

    // MARK: - limitLabResultsPerMetric

    private func lab(_ code: String, _ name: String, day: Int) -> LabResultSample {
        LabResultSample(metricName: name, loincCode: code, effectiveDateTime: date(2024, 6, day), value: Double(day), unit: "u")
    }

    func testLimitPerMetric_keepsNewestPerMetric() {
        let samples = [
            lab(LOINCCode.hemoglobinA1C, "Hemoglobin A1C", day: 1),
            lab(LOINCCode.hemoglobinA1C, "Hemoglobin A1C", day: 3),
            lab(LOINCCode.hemoglobinA1C, "Hemoglobin A1C", day: 2),
            lab(LOINCCode.totalCholesterol, "Total Cholesterol", day: 1),
            lab(LOINCCode.totalCholesterol, "Total Cholesterol", day: 5),
            lab(LOINCCode.totalCholesterol, "Total Cholesterol", day: 4)
        ]
        let limited = HealthKitQueryHelpers.limitLabResultsPerMetric(samples, limit: 2)
        XCTAssertEqual(limited.count, 4)
        XCTAssertEqual(Set(limited.filter { $0.loincCode == LOINCCode.hemoglobinA1C }.map(\.value)), [2, 3])
        XCTAssertEqual(Set(limited.filter { $0.loincCode == LOINCCode.totalCholesterol }.map(\.value)), [4, 5])
    }

    func testLimitPerMetric_oneMetricDoesNotStarveAnother() {
        var samples = (1...20).map { lab(LOINCCode.hemoglobinA1C, "Hemoglobin A1C", day: $0) }
        samples.append(lab(LOINCCode.triglycerides, "Triglycerides", day: 1))
        let limited = HealthKitQueryHelpers.limitLabResultsPerMetric(samples, limit: 5)
        XCTAssertEqual(limited.filter { $0.loincCode == LOINCCode.hemoglobinA1C }.count, 5)
        XCTAssertEqual(limited.filter { $0.loincCode == LOINCCode.triglycerides }.count, 1)
    }

    func testLimitPerMetric_alternateCodesCountAsSameMetric() {
        let samples = [
            lab(LOINCCode.ldlCholesterolDirect, "LDL Cholesterol", day: 1),
            lab("13457-7", "LDL Cholesterol", day: 2),
            lab("18262-6", "LDL Cholesterol", day: 3)
        ]
        let limited = HealthKitQueryHelpers.limitLabResultsPerMetric(samples, limit: 2)
        XCTAssertEqual(limited.map(\.loincCode), ["13457-7", "18262-6"])
    }

    func testLimitPerMetric_noLimitReturnsAll() {
        let samples = (1...5).map { lab(LOINCCode.hemoglobinA1C, "Hemoglobin A1C", day: $0) }
        XCTAssertEqual(HealthKitQueryHelpers.limitLabResultsPerMetric(samples, limit: HKObjectQueryNoLimit).count, 5)
    }
}
