import Foundation
@testable import HealthExporter
import HealthKit
import Testing

struct ExportSizeTests {
    private let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    private let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!
    private let oxygenType = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!
    private let mgDlUnit = HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))

    private var referenceDate: Date {
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 15
        components.hour = 9
        components.minute = 30
        components.second = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test func summaryText_givesTheExactRowCountAndSize() {
        let size = ExportSize(rowCount: 19432, byteCount: 1_980_000)

        #expect(size.summaryText == "This will export 19,432 rows (\(size.formattedByteCount)).")
        #expect(!size.summaryText.contains("around"))
    }

    @Test func summaryText_singularRow() {
        let size = ExportSize(rowCount: 1, byteCount: 300)

        #expect(size.summaryText.hasPrefix("This will export 1 row ("))
    }

    @Test func formattedByteCount_usesFileStyle() {
        let size = ExportSize(rowCount: 10, byteCount: 1_500_000)

        #expect(size.formattedByteCount == ByteCountFormatter.string(fromByteCount: 1_500_000, countStyle: .file))
    }

    @Test func shouldShowConfirmation_falseWhenRowsAndBytesAreUnderThreshold() {
        let size = ExportSize(rowCount: 500, byteCount: 1_000_000)

        #expect(!size.shouldShowConfirmation)
    }

    @Test func shouldShowConfirmation_trueWhenRowCountExceedsThreshold() {
        let size = ExportSize(rowCount: 501, byteCount: 5000)

        #expect(size.shouldShowConfirmation)
    }

    @Test func shouldShowConfirmation_trueWhenByteCountExceedsThreshold() {
        let size = ExportSize(rowCount: 10, byteCount: 1_000_001)

        #expect(size.shouldShowConfirmation)
    }

    @Test func makeFile_sizeAndBytesMatchGeneratedCSV() async throws {
        let weightSample = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 80.0),
            start: referenceDate,
            end: referenceDate
        )
        let stepsSample = HKQuantitySample(
            type: stepsType,
            quantity: HKQuantity(unit: .count(), doubleValue: 9876),
            start: referenceDate.addingTimeInterval(60),
            end: referenceDate.addingTimeInterval(60)
        )
        let glucoseHkSample = HKQuantitySample(
            type: glucoseType,
            quantity: HKQuantity(unit: mgDlUnit, doubleValue: 124.0),
            start: referenceDate.addingTimeInterval(120),
            end: referenceDate.addingTimeInterval(120)
        )
        let glucoseSample = try #require(GlucoseSampleMgDl(from: glucoseHkSample))
        let labSample = LabResultSample(
            metricName: "Hemoglobin A1C",
            loincCode: LOINCCode.hemoglobinA1C,
            effectiveDateTime: referenceDate.addingTimeInterval(180),
            value: 7.2,
            unit: "%",
            source: "Clinical Labs"
        )
        let oxygenSample = HKQuantitySample(
            type: oxygenType,
            quantity: HKQuantity(unit: .percent(), doubleValue: 0.98),
            start: referenceDate.addingTimeInterval(240),
            end: referenceDate.addingTimeInterval(240)
        )

        let fetched = ExportFetchResult(
            weightSamples: [weightSample],
            stepsSamples: [stepsSample],
            glucoseSamples: [glucoseSample],
            labResults: [labSample],
            vitalSamples: [.oxygenSaturation: [oxygenSample]]
        )
        let file = try await CSVGenerator.makeFile(
            from: fetched,
            weightUnit: .pounds,
            temperatureUnit: .fahrenheit,
            dateFormat: .yyyyMMddHHmmss,
            sortOrder: .ascending
        )
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: [weightSample],
            stepsSamples: [stepsSample],
            glucoseSamples: [glucoseSample],
            labResults: [labSample],
            vitalSamples: [.oxygenSaturation: [oxygenSample]],
            weightUnit: .pounds,
            dateFormat: .yyyyMMddHHmmss
        )

        #expect(file.content == csv)
        #expect(file.rowCount == 5)
        #expect(file.byteCount == csv.utf8.count)
        #expect(file.size == ExportSize(rowCount: 5, byteCount: csv.utf8.count))
    }
}
