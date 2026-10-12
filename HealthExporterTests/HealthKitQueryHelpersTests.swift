import Foundation
@testable import HealthExporter
import HealthKit
import Testing

struct HealthKitQueryHelpersTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping - a stored property initializer cannot throw, and the IANA name is fixed
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: "America/New_York")
        return try #require(calendar.date(from: components))
    }

    // MARK: - readTypes

    @Test func readTypes_withoutLabs_containsBaseTypes() throws {
        let types = HealthKitQueryHelpers.readTypes(
            includeWeight: true, includeSteps: true, includeGlucose: true, includeLabs: false
        )

        let weightType = try #require(HKQuantityType.quantityType(forIdentifier: .bodyMass))
        let stepsType = try #require(HKQuantityType.quantityType(forIdentifier: .stepCount))
        let glucoseType = try #require(HKQuantityType.quantityType(forIdentifier: .bloodGlucose))

        #expect(types.contains(weightType))
        #expect(types.contains(stepsType))
        #expect(types.contains(glucoseType))
        #expect(types.count == 3)
    }

    @Test func readTypes_withLabs_containsClinicalType() throws {
        let types = HealthKitQueryHelpers.readTypes(
            includeWeight: true, includeSteps: true, includeGlucose: true, includeLabs: true
        )

        let weightType = try #require(HKQuantityType.quantityType(forIdentifier: .bodyMass))
        let stepsType = try #require(HKQuantityType.quantityType(forIdentifier: .stepCount))
        let glucoseType = try #require(HKQuantityType.quantityType(forIdentifier: .bloodGlucose))

        #expect(types.contains(weightType))
        #expect(types.contains(stepsType))
        #expect(types.contains(glucoseType))

        if let clinicalType = HKObjectType.clinicalType(forIdentifier: .labResultRecord) {
            #expect(types.contains(clinicalType))
            #expect(types.count == 4)
        } else {
            // On platforms where clinical types aren't available
            #expect(types.count == 3)
        }
    }

    @Test func readTypes_withoutLabs_doesNotContainClinical() {
        let types = HealthKitQueryHelpers.readTypes(
            includeWeight: true, includeSteps: true, includeGlucose: true, includeLabs: false
        )
        if let clinicalType = HKObjectType.clinicalType(forIdentifier: .labResultRecord) {
            #expect(!types.contains(clinicalType))
        }
    }

    @Test func readTypes_withVitals_containsSelectedVitalQuantityTypes() throws {
        let types = HealthKitQueryHelpers.readTypes(
            includeWeight: true,
            includeSteps: true,
            includeGlucose: true,
            includeLabs: false,
            vitalMetrics: [.bloodPressure, .oxygenSaturation]
        )

        let systolic = try #require(HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic))
        let diastolic = try #require(HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic))
        let oxygen = try #require(HKQuantityType.quantityType(forIdentifier: .oxygenSaturation))

        #expect(types.contains(systolic))
        #expect(types.contains(diastolic))
        #expect(types.contains(oxygen))
        #expect(types.count == 6)
    }

    @Test func readTypes_vitalsOnly_omitsWeightStepsAndGlucose() {
        let types = HealthKitQueryHelpers.readTypes(
            includeWeight: false,
            includeSteps: false,
            includeGlucose: false,
            includeLabs: false,
            vitalMetrics: [.bloodPressure]
        )

        #expect(types == [
            HKQuantityType(.bloodPressureSystolic),
            HKQuantityType(.bloodPressureDiastolic),
        ])
    }

    @Test func readTypes_labsOnly_containsOnlyClinicalType() {
        let types = HealthKitQueryHelpers.readTypes(
            includeWeight: false, includeSteps: false, includeGlucose: false, includeLabs: true
        )

        if let clinicalType = HKObjectType.clinicalType(forIdentifier: .labResultRecord) {
            #expect(types == [clinicalType])
        } else {
            #expect(types.isEmpty)
        }
    }

    // MARK: - dayAlignedRange

    @Test func dayAlignedRange_alignsToStartOfDay() throws {
        let start = try date(2024, 6, 15, 14, 30) // 2:30 PM
        let end = try date(2024, 6, 20, 9, 15) // 9:15 AM

        let result = HealthKitQueryHelpers.dayAlignedRange(from: (start, end), calendar: calendar)

        #expect(result != nil)
        let startComponents = try calendar.dateComponents([.hour, .minute, .second], from: #require(result?.start))
        #expect(startComponents.hour == 0)
        #expect(startComponents.minute == 0)
        #expect(startComponents.second == 0)
    }

    @Test func dayAlignedRange_endIsNextDayMidnight() throws {
        let start = try date(2024, 6, 15)
        let end = try date(2024, 6, 20)

        let result = HealthKitQueryHelpers.dayAlignedRange(from: (start, end), calendar: calendar)

        #expect(result != nil)
        // End should be start of June 21
        let endComponents = try calendar.dateComponents([.year, .month, .day, .hour, .minute], from: #require(result?.end))
        #expect(endComponents.year == 2024)
        #expect(endComponents.month == 6)
        #expect(endComponents.day == 21)
        #expect(endComponents.hour == 0)
        #expect(endComponents.minute == 0)
    }

    @Test func dayAlignedRange_sameDay_coversFullDay() throws {
        let day = try date(2024, 6, 15, 14, 30)

        let result = HealthKitQueryHelpers.dayAlignedRange(from: (day, day), calendar: calendar)

        #expect(result != nil)
        let startDay = try calendar.component(.day, from: #require(result?.start))
        let endDay = try calendar.component(.day, from: #require(result?.end))
        #expect(startDay == 15)
        #expect(endDay == 16) // Next day midnight
    }

    @Test func dayAlignedRange_preservesStartDate() throws {
        let start = try date(2024, 1, 1, 23, 59)
        let end = try date(2024, 1, 31, 0, 1)

        let result = HealthKitQueryHelpers.dayAlignedRange(from: (start, end), calendar: calendar)

        #expect(result != nil)
        let startComponents = try calendar.dateComponents([.year, .month, .day], from: #require(result?.start))
        #expect(startComponents.year == 2024)
        #expect(startComponents.month == 1)
        #expect(startComponents.day == 1)
    }

    @Test func predicateForDateRange_returnsPredicate() throws {
        let start = try date(2024, 6, 15)
        let end = try date(2024, 6, 20)

        let predicate = HealthKitQueryHelpers.predicateForDateRange((start, end), calendar: calendar)

        #expect(predicate != nil)
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

    @Test func filterLabResults_insideRange_included() throws {
        let sample = try labSample(date(2024, 6, 17, 10, 0), value: 7.2)
        let range = try (startDate: date(2024, 6, 15), endDate: date(2024, 6, 20))

        let filtered = HealthKitQueryHelpers.filterLabResultsByDateRange([sample], dateRange: range, calendar: calendar)
        #expect(filtered.count == 1)
    }

    @Test func filterLabResults_beforeRange_excluded() throws {
        let sample = try labSample(date(2024, 6, 14, 10, 0), value: 7.2)
        let range = try (startDate: date(2024, 6, 15), endDate: date(2024, 6, 20))

        let filtered = HealthKitQueryHelpers.filterLabResultsByDateRange([sample], dateRange: range, calendar: calendar)
        #expect(filtered.isEmpty)
    }

    @Test func filterLabResults_afterRange_excluded() throws {
        let sample = try labSample(date(2024, 6, 21, 10, 0), value: 7.2)
        let range = try (startDate: date(2024, 6, 15), endDate: date(2024, 6, 20))

        let filtered = HealthKitQueryHelpers.filterLabResultsByDateRange([sample], dateRange: range, calendar: calendar)
        #expect(filtered.isEmpty)
    }

    @Test func filterLabResults_onStartDay_included() throws {
        let sample = try labSample(date(2024, 6, 15, 0, 0), value: 6.5)
        let range = try (startDate: date(2024, 6, 15), endDate: date(2024, 6, 20))

        let filtered = HealthKitQueryHelpers.filterLabResultsByDateRange([sample], dateRange: range, calendar: calendar)
        #expect(filtered.count == 1)
    }

    @Test func filterLabResults_onEndDay_included() throws {
        let sample = try labSample(date(2024, 6, 20, 23, 59), value: 6.5)
        let range = try (startDate: date(2024, 6, 15), endDate: date(2024, 6, 20))

        let filtered = HealthKitQueryHelpers.filterLabResultsByDateRange([sample], dateRange: range, calendar: calendar)
        #expect(filtered.count == 1)
    }

    @Test func filterLabResults_multipleSamples_filtersCorrectly() throws {
        let samples = try [
            labSample(date(2024, 6, 14), value: 7.0), // before
            labSample(date(2024, 6, 15), value: 7.1), // start day
            labSample(date(2024, 6, 18), value: 7.2), // middle
            labSample(date(2024, 6, 20), value: 7.3), // end day
            labSample(date(2024, 6, 21), value: 7.4), // after
        ]
        let range = try (startDate: date(2024, 6, 15), endDate: date(2024, 6, 20))

        let filtered = HealthKitQueryHelpers.filterLabResultsByDateRange(samples, dateRange: range, calendar: calendar)
        #expect(filtered.count == 3)
        #expect(abs(filtered[0].value - 7.1) <= 0.01)
        #expect(abs(filtered[1].value - 7.2) <= 0.01)
        #expect(abs(filtered[2].value - 7.3) <= 0.01)
    }

    @Test func filterLabResults_emptySamples_returnsEmpty() throws {
        let range = try (startDate: date(2024, 6, 15), endDate: date(2024, 6, 20))
        let filtered = HealthKitQueryHelpers.filterLabResultsByDateRange([], dateRange: range, calendar: calendar)
        #expect(filtered.isEmpty)
    }

    @Test func filterLabResults_sameDay_includesFullDay() throws {
        let samples = try [
            labSample(date(2024, 6, 15, 0, 0), value: 6.5),
            labSample(date(2024, 6, 15, 12, 0), value: 6.6),
            labSample(date(2024, 6, 15, 23, 59), value: 6.7),
        ]
        let range = try (startDate: date(2024, 6, 15), endDate: date(2024, 6, 15))

        let filtered = HealthKitQueryHelpers.filterLabResultsByDateRange(samples, dateRange: range, calendar: calendar)
        #expect(filtered.count == 3)
    }

    // MARK: - generateWeightTestSamples

    @Test func generateWeightTestSamples_createsSixtyDailyWeightRecords() throws {
        var gmtCalendar = Calendar(identifier: .gregorian)
        gmtCalendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 20
        components.hour = 12
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)
        let referenceDate = try #require(gmtCalendar.date(from: components))

        let samples = HealthKitQueryHelpers.generateWeightTestSamples(
            days: 60,
            referenceDate: referenceDate,
            calendar: gmtCalendar
        ) { index in
            80.0 + Double(index)
        }

        #expect(samples.count == 60)

        let firstDate = try #require(gmtCalendar.date(byAdding: .day, value: -59, to: referenceDate))
        #expect(samples.first?.startDate == firstDate)
        #expect(samples.last?.startDate == referenceDate)

        for (index, sample) in samples.enumerated() {
            let expectedDate = try #require(gmtCalendar.date(byAdding: .day, value: index - 59, to: referenceDate))
            #expect(sample.startDate == expectedDate)
            #expect(abs(sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo)) - (80.0 + Double(index))) <= 0.0001)
        }
    }

    @Test func simulatorTestDataShareTypes_containsWeightType() throws {
        let shareTypes = HealthKitQueryHelpers.simulatorTestDataShareTypes()
        let weightType = try #require(HKQuantityType.quantityType(forIdentifier: .bodyMass))

        #expect(shareTypes.count == 1)
        #expect(shareTypes.contains(weightType))
    }

    @Test func simulatorTestDataFailureMessage_includesUnderlyingError() {
        let underlying = NSError(domain: "HealthKit", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Permission denied",
        ])

        let message = HealthKitQueryHelpers.simulatorTestDataFailureMessage(underlying)

        #expect(message == "Failed to generate weight data: Permission denied")
    }

    @Test func simulatorTestDataFailureMessage_withoutUnderlyingError() {
        let message = HealthKitQueryHelpers.simulatorTestDataFailureMessage(nil)

        #expect(message == "Failed to generate weight data.")
    }

    // MARK: - limitLabResultsPerMetric

    private func lab(_ code: String, _ name: String, day: Int) throws -> LabResultSample {
        try LabResultSample(metricName: name, loincCode: code, effectiveDateTime: date(2024, 6, day), value: Double(day), unit: "u")
    }

    @Test func limitPerMetric_keepsNewestPerMetric() throws {
        let samples = try [
            lab(LOINCCode.hemoglobinA1C, "Hemoglobin A1C", day: 1),
            lab(LOINCCode.hemoglobinA1C, "Hemoglobin A1C", day: 3),
            lab(LOINCCode.hemoglobinA1C, "Hemoglobin A1C", day: 2),
            lab(LOINCCode.totalCholesterol, "Total Cholesterol", day: 1),
            lab(LOINCCode.totalCholesterol, "Total Cholesterol", day: 5),
            lab(LOINCCode.totalCholesterol, "Total Cholesterol", day: 4),
        ]
        let limited = HealthKitQueryHelpers.limitLabResultsPerMetric(samples, limit: 2)
        #expect(limited.count == 4)
        #expect(Set(limited.filter { $0.loincCode == LOINCCode.hemoglobinA1C }.map(\.value)) == [2, 3])
        #expect(Set(limited.filter { $0.loincCode == LOINCCode.totalCholesterol }.map(\.value)) == [4, 5])
    }

    @Test func limitPerMetric_oneMetricDoesNotStarveAnother() throws {
        var samples = try (1 ... 20).map { try lab(LOINCCode.hemoglobinA1C, "Hemoglobin A1C", day: $0) }
        try samples.append(lab(LOINCCode.triglycerides, "Triglycerides", day: 1))
        let limited = HealthKitQueryHelpers.limitLabResultsPerMetric(samples, limit: 5)
        #expect((limited.filter { $0.loincCode == LOINCCode.hemoglobinA1C }.count) == 5)
        #expect((limited.filter { $0.loincCode == LOINCCode.triglycerides }.count) == 1)
    }

    @Test func limitPerMetric_alternateCodesCountAsSameMetric() throws {
        let samples = try [
            lab(LOINCCode.ldlCholesterolDirect, "LDL Cholesterol", day: 1),
            lab("13457-7", "LDL Cholesterol", day: 2),
            lab("18262-6", "LDL Cholesterol", day: 3),
        ]
        let limited = HealthKitQueryHelpers.limitLabResultsPerMetric(samples, limit: 2)
        #expect(limited.map(\.loincCode) == ["13457-7", "18262-6"])
    }

    @Test func limitPerMetric_noLimitReturnsAll() throws {
        let samples = try (1 ... 5).map { try lab(LOINCCode.hemoglobinA1C, "Hemoglobin A1C", day: $0) }
        #expect(HealthKitQueryHelpers.limitLabResultsPerMetric(samples, limit: HKObjectQueryNoLimit).count == 5)
    }
}
