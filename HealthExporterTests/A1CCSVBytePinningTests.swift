import Foundation
@testable import HealthExporter
import Testing

/// Locks the exact byte format of A1C CSV rows so the lab-pipeline refactor
/// cannot accidentally change output. Uses `.iso8601` date format because it
/// is forced to UTC by `CSVGenerator.makeDateFormatter`, giving a deterministic
/// expected string independent of the test host's locale or timezone.
struct A1CCSVBytePinningTests {
    private var fixedDate: Date {
        ISO8601DateFormatter().date(from: "2024-06-15T10:30:00Z")!
    }

    private func a1cSample(date: Date, value: Double, unit: String, source: String) -> LabResultSample {
        LabResultSample(
            metricName: "Hemoglobin A1C",
            loincCode: LOINCCode.hemoglobinA1C,
            effectiveDateTime: date,
            value: value,
            unit: unit,
            source: source
        )
    }

    private func generateCSV(for samples: [LabResultSample]) -> String {
        CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: samples,
            weightUnit: .kilograms,
            dateFormat: .iso8601,
            sortOrder: .ascending
        )
    }

    // MARK: - Exact byte format

    @Test func a1cRow_exactByteFormat_percentUnit() {
        let sample = a1cSample(date: fixedDate, value: 7.2, unit: "%", source: "TestClinic")
        let expected = CSVGenerator.csvPreamble + """
        2024-06-15T10:30:00Z,Hemoglobin A1C,4548-4,7.20,%,TestClinic,

        """
        #expect(generateCSV(for: [sample]) == expected)
    }

    @Test func a1cRow_exactByteFormat_mmolPerMolUnit() {
        let sample = a1cSample(date: fixedDate, value: 55.0, unit: "mmol/mol", source: "LabCorp")
        let expected = CSVGenerator.csvPreamble + """
        2024-06-15T10:30:00Z,Hemoglobin A1C,4548-4,55.00,mmol/mol,LabCorp,

        """
        #expect(generateCSV(for: [sample]) == expected)
    }

    @Test func a1cRow_exactByteFormat_sourceWithCommaIsCSVEscaped() {
        let sample = a1cSample(date: fixedDate, value: 6.1, unit: "%", source: "Foo, Inc.")
        let expected = CSVGenerator.csvPreamble + """
        2024-06-15T10:30:00Z,Hemoglobin A1C,4548-4,6.10,%,"Foo, Inc.",

        """
        #expect(generateCSV(for: [sample]) == expected)
    }

    @Test func a1cRow_exactByteFormat_sourceWithQuoteIsCSVEscaped() {
        let sample = a1cSample(date: fixedDate, value: 6.1, unit: "%", source: "Mom's Lab")
        let expected = CSVGenerator.csvPreamble + """
        2024-06-15T10:30:00Z,Hemoglobin A1C,4548-4,6.10,%,Mom's Lab,

        """
        #expect(generateCSV(for: [sample]) == expected)
    }

    @Test func a1cRow_exactByteFormat_valuePrecisionIsTwoDecimals() {
        let sample = a1cSample(date: fixedDate, value: 5.0, unit: "%", source: "TestClinic")
        // 5.0 must render as "5.00" — two decimals, zero-padded
        #expect(generateCSV(for: [sample]).contains(",5.00,"))
    }

    // MARK: - Ascending sort order (default)

    @Test func a1cRow_ascendingSort_oldestFirst() throws {
        let older = try #require(ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z"))
        let newer = try #require(ISO8601DateFormatter().date(from: "2024-12-31T23:59:59Z"))
        let samples = [
            a1cSample(date: newer, value: 7.5, unit: "%", source: "C"),
            a1cSample(date: older, value: 6.5, unit: "%", source: "C"),
        ]
        let expected = CSVGenerator.csvPreamble + """
        2024-01-01T00:00:00Z,Hemoglobin A1C,4548-4,6.50,%,C,
        2024-12-31T23:59:59Z,Hemoglobin A1C,4548-4,7.50,%,C,

        """
        #expect(generateCSV(for: samples) == expected)
    }
}
