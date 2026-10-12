import Foundation
import Testing
import HealthKit
@testable import HealthExporter

struct ExportPreviewEstimateTests {

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

    @Test func roundedRowCount_underThousandRoundsToNearestHundred() {
        let estimate = ExportPreviewEstimate(rowCount: 720, estimatedByteCount: 7_240)

        #expect(estimate.roundedRowCount == 700)
        #expect(estimate.summaryText.contains("around 700 rows"))
    }

    @Test func roundedRowCount_overThousandRoundsToNearestThousand() {
        let estimate = ExportPreviewEstimate(rowCount: 19_432, estimatedByteCount: 1_980_000)

        #expect(estimate.roundedRowCount == 19_000)
        #expect(estimate.summaryText.contains("around 19,000 rows"))
    }

    @Test func shouldShowConfirmation_falseWhenRowsAndBytesAreUnderThreshold() {
        let estimate = ExportPreviewEstimate(rowCount: 500, estimatedByteCount: 1_000_000)

        #expect(!estimate.shouldShowConfirmation)
    }

    @Test func shouldShowConfirmation_trueWhenRowCountExceedsThreshold() {
        let estimate = ExportPreviewEstimate(rowCount: 501, estimatedByteCount: 5_000)

        #expect(estimate.shouldShowConfirmation)
    }

    @Test func shouldShowConfirmation_trueWhenByteCountExceedsThreshold() {
        let estimate = ExportPreviewEstimate(rowCount: 10, estimatedByteCount: 1_000_001)

        #expect(estimate.shouldShowConfirmation)
    }

    @Test func makePreviewEstimate_matchesGeneratedCSVByteCount() {
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
        let oxygenSample = HKQuantitySample(
            type: oxygenType,
            quantity: HKQuantity(unit: .percent(), doubleValue: 0.98),
            start: referenceDate.addingTimeInterval(240),
            end: referenceDate.addingTimeInterval(240)
        )

        let estimate = CSVGenerator.makePreviewEstimate(
            weightSamples: [weightSample],
            stepsSamples: [stepsSample],
            glucoseSamples: [glucoseSample],
            labResults: [labSample],
            vitalSamples: [.oxygenSaturation: [oxygenSample]],
            weightUnit: .pounds,
            dateFormat: .yyyyMMddHHmmss
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

        #expect(estimate.rowCount == 5)
        #expect(estimate.estimatedByteCount == csv.utf8.count)
    }
}
