import XCTest
import HealthKit
@testable import HealthExporter

final class CSVGeneratorTests: XCTestCase {

    private let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    private let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!
    private let mgDlUnit = HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))

    /// A fixed reference date (2024-01-15 09:30:00 UTC) for deterministic test output.
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

    // MARK: - Weight CSV

    func testGenerateWeightCSV_emptyInput_returnsHeaderOnly() {
        let csv = CSVGenerator.generateWeightCSV(from: [], unit: .kilograms)
        XCTAssertEqual(csv, "Date,Metric,Value,Unit,Source\n")
    }

    func testGenerateWeightCSV_hasCorrectHeader() {
        let csv = CSVGenerator.generateWeightCSV(from: [], unit: .kilograms)
        XCTAssertTrue(csv.hasPrefix("Date,Metric,Value,Unit,Source"))
    }

    func testGenerateWeightCSV_kilograms_formatsCorrectly() {
        let sample = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 75.0),
            start: referenceDate,
            end: referenceDate
        )
        let csv = CSVGenerator.generateWeightCSV(from: [sample], unit: .kilograms)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains(",Weight,"))
        XCTAssertTrue(lines[1].contains(",75.00,"))
        XCTAssertTrue(lines[1].contains(",kg,"))
    }

    func testGenerateWeightCSV_pounds_convertsFromKg() {
        let weightKg = 75.0
        let sample = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weightKg),
            start: referenceDate,
            end: referenceDate
        )
        let csv = CSVGenerator.generateWeightCSV(from: [sample], unit: .pounds)
        XCTAssertTrue(csv.contains(",lbs"))
        let expectedLbs = weightKg * 2.2046226218
        XCTAssertTrue(csv.contains(String(format: "%.2f", expectedLbs)))
    }

    func testGenerateWeightCSV_100kg_toPoundsRoundTrip() {
        let sample = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 100.0),
            start: referenceDate,
            end: referenceDate
        )
        let csv = CSVGenerator.generateWeightCSV(from: [sample], unit: .pounds)
        // 100 kg * 2.2046226218 = 220.46226218 → "220.46"
        XCTAssertTrue(csv.contains("220.46"))
        XCTAssertTrue(csv.contains(",lbs"))
    }

    func testGenerateWeightCSV_multipleEntries_correctLineCount() {
        let samples = (0..<5).map { i -> HKQuantitySample in
            let date = Calendar.current.date(byAdding: .day, value: -i, to: referenceDate)!
            return HKQuantitySample(
                type: weightType,
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: Double(70 + i)),
                start: date,
                end: date
            )
        }
        let csv = CSVGenerator.generateWeightCSV(from: samples, unit: .kilograms)
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 6) // 1 header + 5 data rows
    }

    func testGenerateWeightCSV_iso8601Format_usesUTC() {
        let sample = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 70.0),
            start: referenceDate,
            end: referenceDate
        )
        let csv = CSVGenerator.generateWeightCSV(from: [sample], unit: .kilograms, dateFormat: .iso8601)
        XCTAssertTrue(csv.contains("T"), "ISO8601 field should contain 'T' separator")
        XCTAssertTrue(csv.contains("Z"), "ISO8601 field should end with 'Z' for UTC")
    }

    // MARK: - Steps CSV

    func testGenerateStepsCSV_emptyInput_returnsHeaderOnly() {
        let csv = CSVGenerator.generateStepsCSV(from: [])
        XCTAssertEqual(csv, "Date,Metric,Value,Unit,Source\n")
    }

    func testGenerateStepsCSV_formatsCorrectly() {
        let sample = HKQuantitySample(
            type: stepsType,
            quantity: HKQuantity(unit: .count(), doubleValue: 8500),
            start: referenceDate,
            end: referenceDate
        )
        let csv = CSVGenerator.generateStepsCSV(from: [sample])
        XCTAssertTrue(csv.contains(",Steps,"))
        XCTAssertTrue(csv.contains(",8500,"))
        XCTAssertTrue(csv.contains(",steps,"))
    }

    func testGenerateStepsCSV_stepsFormattedAsInteger() {
        let sample = HKQuantitySample(
            type: stepsType,
            quantity: HKQuantity(unit: .count(), doubleValue: 12345.7),
            start: referenceDate,
            end: referenceDate
        )
        let csv = CSVGenerator.generateStepsCSV(from: [sample])
        XCTAssertTrue(csv.contains(",12345,"), "Steps should be truncated to integer")
        XCTAssertFalse(csv.contains("12345.7"), "Steps should not include decimal point")
    }

    // MARK: - Combined CSV

    func testGenerateCombinedCSV_allNil_returnsHeaderOnly() {
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: nil,
            weightUnit: .kilograms
        )
        XCTAssertEqual(csv, "Date,Metric,Value,Unit,Source\n")
    }

    func testGenerateCombinedCSV_allEmpty_returnsHeaderOnly() {
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: [],
            stepsSamples: [],
            glucoseSamples: [],
            labResults: [],
            weightUnit: .kilograms
        )
        XCTAssertEqual(csv, "Date,Metric,Value,Unit,Source\n")
    }

    func testGenerateCombinedCSV_weightOnly_containsWeightRow() {
        let sample = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 80.0),
            start: referenceDate,
            end: referenceDate
        )
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: [sample],
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: nil,
            weightUnit: .kilograms
        )
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains(",Weight,"))
    }

    func testGenerateCombinedCSV_stepsOnly_containsStepsRow() {
        let sample = HKQuantitySample(
            type: stepsType,
            quantity: HKQuantity(unit: .count(), doubleValue: 5000),
            start: referenceDate,
            end: referenceDate
        )
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: [sample],
            glucoseSamples: nil,
            labResults: nil,
            weightUnit: .kilograms
        )
        XCTAssertTrue(csv.contains(",Steps,"))
    }

    func testGenerateCombinedCSV_glucoseOnly_containsGlucoseRow() {
        let hkSample = HKQuantitySample(
            type: glucoseType,
            quantity: HKQuantity(unit: mgDlUnit, doubleValue: 120.0),
            start: referenceDate,
            end: referenceDate
        )
        guard let glucoseSample = GlucoseSampleMgDl(from: hkSample) else {
            XCTFail("GlucoseSampleMgDl should be created for value 120")
            return
        }
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: [glucoseSample],
            labResults: nil,
            weightUnit: .kilograms
        )
        XCTAssertTrue(csv.contains(",Blood Glucose,"))
        XCTAssertTrue(csv.contains(",mg/dL"))
    }

    func testGenerateCombinedCSV_mixedData_allMetricsPresent() {
        let weightSample = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 75.0),
            start: referenceDate,
            end: referenceDate
        )
        let stepsSample = HKQuantitySample(
            type: stepsType,
            quantity: HKQuantity(unit: .count(), doubleValue: 8000),
            start: referenceDate,
            end: referenceDate
        )
        let hkGlucose = HKQuantitySample(
            type: glucoseType,
            quantity: HKQuantity(unit: mgDlUnit, doubleValue: 95.0),
            start: referenceDate,
            end: referenceDate
        )
        let glucoseSample = GlucoseSampleMgDl(from: hkGlucose)!

        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: [weightSample],
            stepsSamples: [stepsSample],
            glucoseSamples: [glucoseSample],
            labResults: nil,
            weightUnit: .kilograms
        )
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 4) // header + 3 data rows
        XCTAssertTrue(csv.contains(",Weight,"))
        XCTAssertTrue(csv.contains(",Steps,"))
        XCTAssertTrue(csv.contains(",Blood Glucose,"))
    }

    func testGenerateCombinedCSV_a1cData_containsA1CRow() {
        let a1c = LabResultSample(
            metricName: "Hemoglobin A1C",
            loincCode: LOINCCode.hemoglobinA1C,
            effectiveDateTime: referenceDate,
            value: 7.2,
            unit: "%"
        )
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: [a1c],
            weightUnit: .kilograms
        )
        XCTAssertTrue(csv.contains(",Hemoglobin A1C,"))
        XCTAssertTrue(csv.contains(",7.20,"))
        XCTAssertTrue(csv.contains(",%"))
    }

    func testGenerateCombinedCSV_weightPounds_usesLbsUnit() {
        let sample = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 90.0),
            start: referenceDate,
            end: referenceDate
        )
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: [sample],
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: nil,
            weightUnit: .pounds
        )
        XCTAssertTrue(csv.contains(",lbs"))
        XCTAssertFalse(csv.contains(",kg"))
    }

    func testGenerateCombinedCSV_endsWithNewline() {
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: nil,
            weightUnit: .kilograms
        )
        XCTAssertTrue(csv.hasSuffix("\n"), "CSV output should end with a newline")
    }

    func testGenerateCombinedCSV_glucoseFormattedAsRoundedInteger() {
        let hkSample = HKQuantitySample(
            type: glucoseType,
            quantity: HKQuantity(unit: mgDlUnit, doubleValue: 145.6),
            start: referenceDate,
            end: referenceDate
        )
        let glucoseSample = GlucoseSampleMgDl(from: hkSample)!
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: [glucoseSample],
            labResults: nil,
            weightUnit: .kilograms
        )
        XCTAssertTrue(csv.contains(",146,"), "Glucose should be rounded to nearest integer")
    }

    // MARK: - Lab Result Rows (generic)

    func testLabResultRow_usesRegistryPrecision_forKnownLoinc() {
        // A1C is registered with precision 2, so 7.0 renders as "7.00"
        let sample = LabResultSample(
            metricName: "Hemoglobin A1C",
            loincCode: LOINCCode.hemoglobinA1C,
            effectiveDateTime: referenceDate,
            value: 7.0,
            unit: "%",
            source: "Lab"
        )
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: [sample],
            weightUnit: .kilograms
        )
        XCTAssertTrue(csv.contains(",7.00,%,"))
    }

    func testLabResultRow_unknownLoinc_defaultsToTwoDecimals() {
        // Registry has no entry for this code, so precision falls back to 2.
        let sample = LabResultSample(
            metricName: "Mystery Lab",
            loincCode: "0000-0",
            effectiveDateTime: referenceDate,
            value: 3.456,
            unit: "u",
            source: "Lab"
        )
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: [sample],
            weightUnit: .kilograms
        )
        XCTAssertTrue(csv.contains(",Mystery Lab,3.46,u,"))
    }

    func testLabResultRow_metricNameContainingCommaIsCSVEscaped() {
        let sample = LabResultSample(
            metricName: "Some, Metric",
            loincCode: "0000-0",
            effectiveDateTime: referenceDate,
            value: 1.0,
            unit: "u",
            source: "Lab"
        )
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: [sample],
            weightUnit: .kilograms
        )
        XCTAssertTrue(csv.contains(",\"Some, Metric\","))
    }

    // MARK: - Date Format Options

    func testGenerateCombinedCSV_iso8601Format_usesUTCTimestamps() {
        let sample = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 80.0),
            start: referenceDate,
            end: referenceDate
        )
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: [sample],
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: nil,
            weightUnit: .kilograms,
            dateFormat: .iso8601
        )
        XCTAssertTrue(csv.contains("2024-01-15T09:30:00Z"))
    }

    func testGenerateCombinedCSV_slashFormat_usesSlashes() {
        let sample = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 80.0),
            start: referenceDate,
            end: referenceDate
        )
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: [sample],
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: nil,
            weightUnit: .kilograms,
            dateFormat: .yyyySlashMMddHHmmss
        )
        XCTAssertTrue(csv.contains("/"))
    }

    func testGenerateCombinedCSV_singleDateColumn() {
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: nil,
            weightUnit: .kilograms
        )
        XCTAssertTrue(csv.hasPrefix("Date,Metric,"), "Should have single Date column, not Date,ISO8601")
        XCTAssertFalse(csv.contains("ISO8601"), "Should not have separate ISO8601 column")
    }

    // MARK: - Sort Order

    func testGenerateCombinedCSV_descendingOrder_newestFirst() {
        let olderDate = referenceDate
        let newerDate = Calendar.current.date(byAdding: .day, value: 1, to: referenceDate)!

        let sample1 = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 70.0),
            start: olderDate,
            end: olderDate
        )
        let sample2 = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 80.0),
            start: newerDate,
            end: newerDate
        )

        let csvAsc = CSVGenerator.generateCombinedCSV(
            weightSamples: [sample2, sample1],
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: nil,
            weightUnit: .kilograms,
            sortOrder: .ascending
        )
        let linesAsc = csvAsc.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertTrue(linesAsc[1].contains("70.00"), "Ascending: older (70kg) should come first")
        XCTAssertTrue(linesAsc[2].contains("80.00"), "Ascending: newer (80kg) should come second")

        let csvDesc = CSVGenerator.generateCombinedCSV(
            weightSamples: [sample1, sample2],
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: nil,
            weightUnit: .kilograms,
            sortOrder: .descending
        )
        let linesDesc = csvDesc.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertTrue(linesDesc[1].contains("80.00"), "Descending: newer (80kg) should come first")
        XCTAssertTrue(linesDesc[2].contains("70.00"), "Descending: older (70kg) should come second")
    }
}
