import XCTest
import HealthKit
@testable import HealthExporter

final class ExportPreviewEstimateTests: XCTestCase {

    private let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    private let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!
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

    func testRoundedRowCount_underThousandRoundsToNearestHundred() {
        let estimate = ExportPreviewEstimate(rowCount: 720, estimatedByteCount: 7_240)

        XCTAssertEqual(estimate.roundedRowCount, 700)
        XCTAssertTrue(estimate.summaryText.contains("around 700 rows"))
    }

    func testRoundedRowCount_overThousandRoundsToNearestThousand() {
        let estimate = ExportPreviewEstimate(rowCount: 19_432, estimatedByteCount: 1_980_000)

        XCTAssertEqual(estimate.roundedRowCount, 19_000)
        XCTAssertTrue(estimate.summaryText.contains("around 19,000 rows"))
    }

    func testShouldShowConfirmation_falseWhenRowsAndBytesAreUnderThreshold() {
        let estimate = ExportPreviewEstimate(rowCount: 500, estimatedByteCount: 1_000_000)

        XCTAssertFalse(estimate.shouldShowConfirmation)
    }

    func testShouldShowConfirmation_trueWhenRowCountExceedsThreshold() {
        let estimate = ExportPreviewEstimate(rowCount: 501, estimatedByteCount: 5_000)

        XCTAssertTrue(estimate.shouldShowConfirmation)
    }

    func testShouldShowConfirmation_trueWhenByteCountExceedsThreshold() {
        let estimate = ExportPreviewEstimate(rowCount: 10, estimatedByteCount: 1_000_001)

        XCTAssertTrue(estimate.shouldShowConfirmation)
    }

    func testMakePreviewEstimate_matchesGeneratedCSVByteCount() {
        let weightSample = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 80.0),
            start: referenceDate,
            end: referenceDate
        )
        let stepsSample = HKQuantitySample(
            type: stepsType,
            quantity: HKQuantity(unit: .count(), doubleValue: 9_876),
            start: referenceDate.addingTimeInterval(60),
            end: referenceDate.addingTimeInterval(60)
        )
        let glucoseHkSample = HKQuantitySample(
            type: glucoseType,
            quantity: HKQuantity(unit: mgDlUnit, doubleValue: 124.0),
            start: referenceDate.addingTimeInterval(120),
            end: referenceDate.addingTimeInterval(120)
        )
        let glucoseSample = GlucoseSampleMgDl(from: glucoseHkSample)!
        let labSample = LabResultSample(
            metricName: "Hemoglobin A1C",
            loincCode: LOINCCode.hemoglobinA1C,
            effectiveDateTime: referenceDate.addingTimeInterval(180),
            value: 7.2,
            unit: "%",
            source: "Clinical Labs"
        )

        let estimate = CSVGenerator.makePreviewEstimate(
            weightSamples: [weightSample],
            stepsSamples: [stepsSample],
            glucoseSamples: [glucoseSample],
            labResults: [labSample],
            weightUnit: .pounds,
            dateFormat: .yyyyMMddHHmmss
        )
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: [weightSample],
            stepsSamples: [stepsSample],
            glucoseSamples: [glucoseSample],
            labResults: [labSample],
            weightUnit: .pounds,
            dateFormat: .yyyyMMddHHmmss
        )

        XCTAssertEqual(estimate.rowCount, 4)
        XCTAssertEqual(estimate.estimatedByteCount, csv.utf8.count)
    }
}
