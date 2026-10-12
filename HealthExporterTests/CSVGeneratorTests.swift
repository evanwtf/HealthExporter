import XCTest
import HealthKit
@testable import HealthExporter

final class CSVGeneratorTests: XCTestCase {

    private let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    private let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private let glucoseType = HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!
    private let systolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic)!
    private let diastolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic)!
    private let oxygenType = HKQuantityType.quantityType(forIdentifier: .oxygenSaturation)!
    private let bodyTemperatureType = HKQuantityType.quantityType(forIdentifier: .bodyTemperature)!
    private let mgDlUnit = HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))

    /// Returns just the data rows of a CSV (disclaimer and column header lines stripped).
    /// Tests previously indexed by `lines[1]` assumed only a single header line preceded
    /// the data; now there are also three `### ` disclaimer lines.
    private func dataRows(in csv: String) -> [String] {
        csv.components(separatedBy: "\n").filter { line in
            !line.isEmpty && !line.hasPrefix("###") && !line.hasPrefix("Date,")
        }
    }

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
        XCTAssertEqual(csv, CSVGenerator.csvPreamble)
    }

    func testGenerateWeightCSV_hasCorrectHeader() {
        let csv = CSVGenerator.generateWeightCSV(from: [], unit: .kilograms)
        XCTAssertEqual(CSVGenerator.csvHeader, "Date,Metric,LOINC,Value,Unit,Source,Meal Time")
        XCTAssertEqual(csv.components(separatedBy: "\n")[3], CSVGenerator.csvHeader)
    }

    func testGenerateWeightCSV_emitsDisclaimerBeforeHeader() {
        let csv = CSVGenerator.generateWeightCSV(from: [], unit: .kilograms)
        XCTAssertTrue(csv.hasPrefix("### "), "CSV should begin with a `### ` disclaimer line")
        XCTAssertTrue(csv.contains("Not a medical record"), "Disclaimer should mention the file is not a medical record")
    }

    func testGenerateWeightCSV_kilograms_formatsCorrectly() {
        let sample = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 75.0),
            start: referenceDate,
            end: referenceDate
        )
        let csv = CSVGenerator.generateWeightCSV(from: [sample], unit: .kilograms)
        let rows = dataRows(in: csv)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].contains(",Weight,"))
        XCTAssertTrue(rows[0].contains(",75.00,"))
        XCTAssertTrue(rows[0].contains(",kg,"))
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
        XCTAssertEqual(dataRows(in: csv).count, 5)
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
        XCTAssertEqual(csv, CSVGenerator.csvPreamble)
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
        XCTAssertTrue(csv.contains(",12346,"), "Steps should be rounded to the nearest integer")
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
        XCTAssertEqual(csv, CSVGenerator.csvPreamble)
    }

    func testGenerateCombinedCSV_allEmpty_returnsHeaderOnly() {
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: [],
            stepsSamples: [],
            glucoseSamples: [],
            labResults: [],
            weightUnit: .kilograms
        )
        XCTAssertEqual(csv, CSVGenerator.csvPreamble)
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
        let rows = dataRows(in: csv)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].contains(",Weight,"))
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
        XCTAssertEqual(dataRows(in: csv).count, 3)
        XCTAssertTrue(csv.contains(",Weight,"))
        XCTAssertTrue(csv.contains(",Steps,"))
        XCTAssertTrue(csv.contains(",Blood Glucose,"))
    }

    func testGenerateCombinedCSV_bloodPressure_containsPairedRows() {
        let systolic = HKQuantitySample(
            type: systolicType,
            quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: 120),
            start: referenceDate,
            end: referenceDate
        )
        let diastolic = HKQuantitySample(
            type: diastolicType,
            quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: 80),
            start: referenceDate,
            end: referenceDate
        )

        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: nil,
            vitalSamples: [
                .bloodPressureSystolic: [systolic],
                .bloodPressureDiastolic: [diastolic]
            ],
            weightUnit: .kilograms
        )

        XCTAssertEqual(dataRows(in: csv).count, 2)
        XCTAssertTrue(csv.contains(",Blood Pressure Systolic,,120,mmHg,"))
        XCTAssertTrue(csv.contains(",Blood Pressure Diastolic,,80,mmHg,"))
    }

    func testGenerateCombinedCSV_oxygenSaturation_formatsPercent() {
        let sample = HKQuantitySample(
            type: oxygenType,
            quantity: HKQuantity(unit: .percent(), doubleValue: 0.985),
            start: referenceDate,
            end: referenceDate
        )

        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: nil,
            vitalSamples: [.oxygenSaturation: [sample]],
            weightUnit: .kilograms
        )

        XCTAssertTrue(csv.contains(",Oxygen Saturation,,98.5,%,"))
    }

    func testGenerateCombinedCSV_bodyTemperature_usesSelectedUnit() {
        let sample = HKQuantitySample(
            type: bodyTemperatureType,
            quantity: HKQuantity(unit: .degreeCelsius(), doubleValue: 37),
            start: referenceDate,
            end: referenceDate
        )

        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: nil,
            vitalSamples: [.bodyTemperature: [sample]],
            weightUnit: .kilograms,
            temperatureUnit: .fahrenheit
        )

        XCTAssertTrue(csv.contains(",Body Temperature,,98.6,°F,"))
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

    func testLabResultRow_usesZeroPrecision_forLipidMetrics() {
        let sample = LabResultSample(
            metricName: "Total Cholesterol",
            loincCode: LOINCCode.totalCholesterol,
            effectiveDateTime: referenceDate,
            value: 201.6,
            unit: "mg/dL",
            source: "Lab"
        )
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: [sample],
            weightUnit: .kilograms
        )
        XCTAssertTrue(csv.contains(",Total Cholesterol,2093-3,202,mg/dL,"))
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
        XCTAssertTrue(csv.contains(",Mystery Lab,0000-0,3.46,u,"))
    }

    // MARK: - LOINC column

    func testLOINCColumn_emptyForWeightSteps() {
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
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: [weightSample],
            stepsSamples: [stepsSample],
            glucoseSamples: nil,
            labResults: nil,
            weightUnit: .kilograms
        )
        XCTAssertTrue(csv.contains(",Weight,,75.00,kg,"), "Weight row should have empty LOINC column")
        XCTAssertTrue(csv.contains(",Steps,,8000,steps,"), "Steps row should have empty LOINC column")
    }

    func testLOINCColumn_emptyForVitalRows() {
        let sample = HKQuantitySample(
            type: oxygenType,
            quantity: HKQuantity(unit: .percent(), doubleValue: 0.97),
            start: referenceDate,
            end: referenceDate
        )
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: nil,
            vitalSamples: [.oxygenSaturation: [sample]],
            weightUnit: .kilograms
        )
        XCTAssertTrue(csv.contains(",Oxygen Saturation,,97.0,%,"), "Vital row should have empty LOINC column")
    }

    func testLOINCColumn_populatedForLabRows() {
        let sample = LabResultSample(
            metricName: "Hemoglobin A1C",
            loincCode: LOINCCode.hemoglobinA1C,
            effectiveDateTime: referenceDate,
            value: 5.6,
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
        XCTAssertTrue(csv.contains(",Hemoglobin A1C,4548-4,5.60,%,"), "Lab row should include LOINC code from sample")
    }

    // MARK: - CSV escaping (labs)

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
        XCTAssertEqual(CSVGenerator.csvHeader, "Date,Metric,LOINC,Value,Unit,Source,Meal Time", "Should have single Date column, not Date,ISO8601")
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
        let rowsAsc = dataRows(in: csvAsc)
        XCTAssertTrue(rowsAsc[0].contains("70.00"), "Ascending: older (70kg) should come first")
        XCTAssertTrue(rowsAsc[1].contains("80.00"), "Ascending: newer (80kg) should come second")

        let csvDesc = CSVGenerator.generateCombinedCSV(
            weightSamples: [sample1, sample2],
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: nil,
            weightUnit: .kilograms,
            sortOrder: .descending
        )
        let rowsDesc = dataRows(in: csvDesc)
        XCTAssertTrue(rowsDesc[0].contains("80.00"), "Descending: newer (80kg) should come first")
        XCTAssertTrue(rowsDesc[1].contains("70.00"), "Descending: older (70kg) should come second")
    }

    func testGenerateStepsCSV_roundsHalfUp() {
        let sample = HKQuantitySample(
            type: stepsType,
            quantity: HKQuantity(unit: .count(), doubleValue: 12.5),
            start: referenceDate,
            end: referenceDate
        )
        let csv = CSVGenerator.generateStepsCSV(from: [sample])
        XCTAssertTrue(csv.contains(",Steps,,13,steps,"))
    }

    // MARK: - Date formatter locale and calendar

    func testMakeDateFormatter_usesGregorianPOSIXForEveryOption() {
        for option in DateFormatOption.allCases {
            let formatter = CSVGenerator.makeDateFormatter(for: option)
            XCTAssertEqual(formatter.calendar.identifier, .gregorian, "\(option)")
            XCTAssertEqual(formatter.locale.identifier, "en_US_POSIX", "\(option)")
        }
    }

    func testMakeDateFormatter_knownDateOutput() {
        let formatter = CSVGenerator.makeDateFormatter(for: .yyyyMMddHHmmss)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        XCTAssertEqual(formatter.string(from: referenceDate), "2024-01-15 09:30:00")
    }

    // MARK: - csvEscape

    func testCSVEscape_plainFieldUnchanged() {
        XCTAssertEqual(CSVGenerator.csvEscape("Quest Diagnostics"), "Quest Diagnostics")
    }

    func testCSVEscape_commaAndQuote() {
        XCTAssertEqual(CSVGenerator.csvEscape("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVGenerator.csvEscape("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func testCSVEscape_newlineAndCarriageReturnAreQuoted() {
        XCTAssertEqual(CSVGenerator.csvEscape("line1\nline2"), "\"line1\nline2\"")
        XCTAssertEqual(CSVGenerator.csvEscape("line1\rline2"), "\"line1\rline2\"")
        XCTAssertEqual(CSVGenerator.csvEscape("line1\r\nline2"), "\"line1\r\nline2\"")
    }

    func testLabResultRow_escapesUnitAndLOINC() {
        let sample = LabResultSample(
            metricName: "Mystery Lab",
            loincCode: "0000,0",
            effectiveDateTime: referenceDate,
            value: 1.0,
            unit: "x,y",
            source: "Lab\nTwo"
        )
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: [sample],
            weightUnit: .kilograms
        )
        XCTAssertTrue(csv.contains(",Mystery Lab,\"0000,0\",1.00,\"x,y\",\"Lab\nTwo\""))
    }

    // MARK: - Comparator and alternate codes

    private func labCSV(_ sample: LabResultSample) -> String {
        CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: [sample],
            weightUnit: .kilograms,
            dateFormat: .iso8601
        )
    }

    func testLabResultRow_comparatorPrefixesValue() {
        let egfr = LabResultSample(
            metricName: "eGFR",
            loincCode: "98979-8",
            effectiveDateTime: referenceDate,
            value: 60,
            unit: "mL/min/{1.73_m2}",
            source: "Lab",
            comparator: ">"
        )
        XCTAssertEqual(labCSV(egfr), CSVGenerator.csvPreamble + "2024-01-15T09:30:00Z,eGFR,98979-8,>60,mL/min/{1.73_m2},Lab,\n")

        let crp = LabResultSample(
            metricName: "hs-CRP",
            loincCode: LOINCCode.highSensitivityCRP,
            effectiveDateTime: referenceDate,
            value: 0.3,
            unit: "mg/L",
            source: "Lab",
            comparator: "<"
        )
        XCTAssertTrue(labCSV(crp).contains(",hs-CRP,30522-7,<0.30,mg/L,Lab,\n"))
    }

    func testLabResultRow_alternateCodeUsesMetricPrecision() {
        let ldl = LabResultSample(
            metricName: "LDL Cholesterol",
            loincCode: "13457-7",
            effectiveDateTime: referenceDate,
            value: 101.4,
            unit: "mg/dL",
            source: "Lab"
        )
        XCTAssertTrue(labCSV(ldl).contains(",LDL Cholesterol,13457-7,101,mg/dL,Lab,\n"))
    }

    // MARK: - Meal Time column

    func testGlucoseRows_exactByteFormat_withMealTime() {
        let iso = ISO8601DateFormatter()
        let samples = [
            GlucoseSampleMgDl(startDate: iso.date(from: "2024-06-15T07:00:00Z")!, value: 98, source: "Meter", mealTime: .preprandial),
            GlucoseSampleMgDl(startDate: iso.date(from: "2024-06-15T09:00:00Z")!, value: 142.4, source: "Meter", mealTime: .postprandial),
            GlucoseSampleMgDl(startDate: iso.date(from: "2024-06-15T13:00:00Z")!, value: 110, source: "Meter", mealTime: nil),
        ]
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: samples,
            labResults: nil,
            weightUnit: .kilograms,
            dateFormat: .iso8601
        )
        let expected = CSVGenerator.csvPreamble + """
        2024-06-15T07:00:00Z,Blood Glucose,,98,mg/dL,Meter,Before Meal
        2024-06-15T09:00:00Z,Blood Glucose,,142,mg/dL,Meter,After Meal
        2024-06-15T13:00:00Z,Blood Glucose,,110,mg/dL,Meter,

        """
        XCTAssertEqual(csv, expected)
    }

    func testNonGlucoseRows_endWithEmptyMealTimeField() {
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
        let oxygenSample = HKQuantitySample(
            type: oxygenType,
            quantity: HKQuantity(unit: .percent(), doubleValue: 0.97),
            start: referenceDate,
            end: referenceDate
        )
        let lab = LabResultSample(
            metricName: "Hemoglobin A1C",
            loincCode: LOINCCode.hemoglobinA1C,
            effectiveDateTime: referenceDate,
            value: 5.6,
            unit: "%",
            source: "Lab"
        )
        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: [weightSample],
            stepsSamples: [stepsSample],
            glucoseSamples: nil,
            labResults: [lab],
            vitalSamples: [.oxygenSaturation: [oxygenSample]],
            weightUnit: .kilograms
        )
        let rows = csv.dropFirst(CSVGenerator.csvPreamble.count).split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(rows.count, 4)
        for row in rows {
            XCTAssertTrue(row.hasSuffix(","), "Row should end with an empty Meal Time field: \(row)")
            XCTAssertEqual(row.filter { $0 == "," }.count, 6, "Row should have seven fields: \(row)")
        }
        XCTAssertTrue(csv.hasSuffix(",\n"))
    }

    // MARK: - Production entry point releases inputs

    func testGenerateCombinedCSV_inout_releasesConsumedArrays() {
        let weightSample = HKQuantitySample(
            type: weightType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 75.0),
            start: referenceDate,
            end: referenceDate
        )
        let oxygenSample = HKQuantitySample(
            type: oxygenType,
            quantity: HKQuantity(unit: .percent(), doubleValue: 0.97),
            start: referenceDate,
            end: referenceDate
        )
        var weight: [HKQuantitySample]? = [weightSample]
        var steps: [HKQuantitySample]? = []
        var glucose: [GlucoseSampleMgDl]? = nil
        var labs: [LabResultSample]? = []
        var vitals: [VitalMetricComponent: [HKQuantitySample]] = [.oxygenSaturation: [oxygenSample]]

        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: &weight,
            stepsSamples: &steps,
            glucoseSamples: &glucose,
            labResults: &labs,
            vitalSamples: &vitals,
            weightUnit: .kilograms
        )

        XCTAssertEqual(dataRows(in: csv).count, 2)
        XCTAssertNil(weight)
        XCTAssertNil(steps)
        XCTAssertNil(glucose)
        XCTAssertNil(labs)
        XCTAssertTrue(vitals.isEmpty)
    }
}

/// Test-only convenience over the production `inout` entry point, so tests can
/// pass literals. It forwards to the same function the export flow calls.
extension CSVGenerator {
    static func generateCombinedCSV(
        weightSamples: [HKQuantitySample]?,
        stepsSamples: [HKQuantitySample]?,
        glucoseSamples: [GlucoseSampleMgDl]?,
        labResults: [LabResultSample]?,
        vitalSamples: [VitalMetricComponent: [HKQuantitySample]]? = nil,
        weightUnit: WeightUnit,
        temperatureUnit: TemperatureUnit = .fahrenheit,
        dateFormat: DateFormatOption = .yyyyMMddHHmmss,
        sortOrder: HealthExporter.SortOrder = .ascending
    ) -> String {
        var weight = weightSamples
        var steps = stepsSamples
        var glucose = glucoseSamples
        var labs = labResults
        var vitals = vitalSamples ?? [:]
        return generateCombinedCSV(
            weightSamples: &weight,
            stepsSamples: &steps,
            glucoseSamples: &glucose,
            labResults: &labs,
            vitalSamples: &vitals,
            weightUnit: weightUnit,
            temperatureUnit: temperatureUnit,
            dateFormat: dateFormat,
            sortOrder: sortOrder
        )
    }
}
