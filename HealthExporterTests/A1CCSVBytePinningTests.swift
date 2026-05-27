import XCTest
@testable import HealthExporter

/// Locks the exact byte format of A1C CSV rows so the lab-pipeline refactor
/// cannot accidentally change output. Uses `.iso8601` date format because it
/// is forced to UTC by `CSVGenerator.makeDateFormatter`, giving a deterministic
/// expected string independent of the test host's locale or timezone.
final class A1CCSVBytePinningTests: XCTestCase {

    private var fixedDate: Date {
        ISO8601DateFormatter().date(from: "2024-06-15T10:30:00Z")!
    }

    private func generateCSV(for samples: [A1CSample]) -> String {
        CSVGenerator.generateCombinedCSV(
            weightSamples: nil,
            stepsSamples: nil,
            glucoseSamples: nil,
            a1cSamples: samples,
            weightUnit: .kilograms,
            dateFormat: .iso8601,
            sortOrder: .ascending
        )
    }

    // MARK: - Exact byte format

    func testA1CRow_exactByteFormat_percentUnit() {
        let sample = A1CSample(
            effectiveDateTime: fixedDate,
            value: 7.2,
            unit: "%",
            source: "TestClinic"
        )
        let expected = """
        Date,Metric,Value,Unit,Source
        2024-06-15T10:30:00Z,Hemoglobin A1C,7.20,%,TestClinic

        """
        XCTAssertEqual(generateCSV(for: [sample]), expected)
    }

    func testA1CRow_exactByteFormat_mmolPerMolUnit() {
        let sample = A1CSample(
            effectiveDateTime: fixedDate,
            value: 55.0,
            unit: "mmol/mol",
            source: "LabCorp"
        )
        let expected = """
        Date,Metric,Value,Unit,Source
        2024-06-15T10:30:00Z,Hemoglobin A1C,55.00,mmol/mol,LabCorp

        """
        XCTAssertEqual(generateCSV(for: [sample]), expected)
    }

    func testA1CRow_exactByteFormat_sourceWithCommaIsCSVEscaped() {
        let sample = A1CSample(
            effectiveDateTime: fixedDate,
            value: 6.1,
            unit: "%",
            source: "Foo, Inc."
        )
        let expected = """
        Date,Metric,Value,Unit,Source
        2024-06-15T10:30:00Z,Hemoglobin A1C,6.10,%,"Foo, Inc."

        """
        XCTAssertEqual(generateCSV(for: [sample]), expected)
    }

    func testA1CRow_exactByteFormat_sourceWithQuoteIsCSVEscaped() {
        let sample = A1CSample(
            effectiveDateTime: fixedDate,
            value: 6.1,
            unit: "%",
            source: "Mom's Lab"
        )
        let expected = """
        Date,Metric,Value,Unit,Source
        2024-06-15T10:30:00Z,Hemoglobin A1C,6.10,%,Mom's Lab

        """
        XCTAssertEqual(generateCSV(for: [sample]), expected)
    }

    func testA1CRow_exactByteFormat_valuePrecisionIsTwoDecimals() {
        let sample = A1CSample(
            effectiveDateTime: fixedDate,
            value: 5.0,
            unit: "%",
            source: "TestClinic"
        )
        // 5.0 must render as "5.00" — two decimals, zero-padded
        XCTAssertTrue(generateCSV(for: [sample]).contains(",5.00,"))
    }

    // MARK: - Ascending sort order (default)

    func testA1CRow_ascendingSort_oldestFirst() {
        let older = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!
        let newer = ISO8601DateFormatter().date(from: "2024-12-31T23:59:59Z")!
        let samples = [
            A1CSample(effectiveDateTime: newer, value: 7.5, unit: "%", source: "C"),
            A1CSample(effectiveDateTime: older, value: 6.5, unit: "%", source: "C"),
        ]
        let expected = """
        Date,Metric,Value,Unit,Source
        2024-01-01T00:00:00Z,Hemoglobin A1C,6.50,%,C
        2024-12-31T23:59:59Z,Hemoglobin A1C,7.50,%,C

        """
        XCTAssertEqual(generateCSV(for: samples), expected)
    }
}
