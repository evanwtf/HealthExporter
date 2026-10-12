import CoreTransferable
import Foundation
import HealthKit
import Testing
import UniformTypeIdentifiers
@testable import HealthExporter

/// `CSVFile` replaced `CSVDocument` as the item the file picker writes (#111).
struct CSVFileTests {

    private let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    private let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!

    private func samples(_ type: HKQuantityType, unit: HKUnit, count: Int) -> [HKQuantitySample] {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { index in
            let date = start.addingTimeInterval(Double(index) * 60)
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: 70 + Double(index % 10)),
                start: date,
                end: date
            )
        }
    }

    // MARK: - Content and size

    @Test func init_storesContentAndRowCount() {
        let file = CSVFile(content: "Date,Metric\n2024-01-01,Weight\n", rowCount: 1)

        #expect(file.content == "Date,Metric\n2024-01-01,Weight\n")
        #expect(file.rowCount == 1)
    }

    @Test func byteCount_isTheUTF8Size() {
        let content = "Date,Metric,Value\n2024-01-01,Température,37°C — ok\n"
        let file = CSVFile(content: content, rowCount: 1)

        #expect(file.byteCount == content.utf8.count)
        #expect(file.byteCount > content.count, "Multi-byte characters count as their UTF-8 bytes")
        #expect(file.size == ExportSize(rowCount: 1, byteCount: content.utf8.count))
    }

    @Test func emptyContent_hasNoBytes() {
        let file = CSVFile(content: "", rowCount: 0)

        #expect(file.byteCount == 0)
        #expect(file.data.isEmpty)
    }

    // MARK: - Transfer representation

    @Test func exportedContentTypes_isCSV() {
        #expect(CSVFile.exportedContentTypes() == [.commaSeparatedText])
    }

    @Test func exported_isTheUTF8Content() async throws {
        let original = "Date,Metric,Value\n2024-01-01,Gewicht,80.5 — kg\n2024-01-02,Température,37°C\n"
        let file = CSVFile(content: original, rowCount: 2)

        let data = try await file.exported(as: .commaSeparatedText)

        #expect(data == Data(original.utf8))
        #expect(String(data: data, encoding: .utf8) == original)
    }

    // MARK: - makeFile

    @Test func makeFile_matchesGenerateCombinedCSVBytes() async throws {
        let weight = samples(weightType, unit: .gramUnit(with: .kilo), count: 30)
        let steps = samples(stepsType, unit: .count(), count: 20)
        let expected = CSVGenerator.generateCombinedCSV(
            weightSamples: weight,
            stepsSamples: steps,
            glucoseSamples: nil,
            labResults: nil,
            weightUnit: .kilograms,
            dateFormat: .iso8601,
            sortOrder: .descending
        )

        let file = try await CSVGenerator.makeFile(
            from: ExportFetchResult(weightSamples: weight, stepsSamples: steps),
            weightUnit: .kilograms,
            temperatureUnit: .fahrenheit,
            dateFormat: .iso8601,
            sortOrder: .descending
        )

        #expect(file.content == expected)
        #expect(file.rowCount == 50)
        #expect(file.byteCount == expected.utf8.count)
    }

    @Test func makeFile_cancelledTask_throwsCancellationError() async {
        let fetched = ExportFetchResult(weightSamples: samples(weightType, unit: .gramUnit(with: .kilo), count: 3))
        // The test runs on the main actor, so the task cannot start before cancel().
        let task = Task {
            try await CSVGenerator.makeFile(
                from: fetched,
                weightUnit: .kilograms,
                temperatureUnit: .fahrenheit,
                dateFormat: .yyyyMMddHHmmss,
                sortOrder: .ascending
            )
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    // MARK: - Cancellation checks in the builder

    private struct StopBuilding: Error {}

    /// The builder checks before each metric and every
    /// `rowsPerCancellationCheck` rows, so a large metric stops part way.
    @Test func builder_checksBetweenMetricsAndWithinALargeMetric() {
        let perCheck = CSVGenerator.rowsPerCancellationCheck
        var weight: [HKQuantitySample]? = samples(weightType, unit: .gramUnit(with: .kilo), count: perCheck * 2 + 1)
        var steps: [HKQuantitySample]? = samples(stepsType, unit: .count(), count: 1)
        var glucose: [GlucoseSampleMgDl]?
        var labs: [LabResultSample]?
        var vitals: [VitalMetricComponent: [HKQuantitySample]] = [:]
        var checks = 0

        let csv = CSVGenerator.generateCombinedCSV(
            weightSamples: &weight,
            stepsSamples: &steps,
            glucoseSamples: &glucose,
            labResults: &labs,
            vitalSamples: &vitals,
            weightUnit: .kilograms,
            checkCancellation: { checks += 1 }
        )

        // Weight: 1 before the metric, then at rows 4096 and 8192. Steps: 1.
        #expect(checks == 4)
        #expect(csv.components(separatedBy: "\n").filter { $0.contains(",Weight,") }.count == perCheck * 2 + 1)
    }

    @Test func builder_stopsWhenACheckThrows() {
        let perCheck = CSVGenerator.rowsPerCancellationCheck
        var weight: [HKQuantitySample]? = samples(weightType, unit: .gramUnit(with: .kilo), count: perCheck * 3)
        var steps: [HKQuantitySample]? = samples(stepsType, unit: .count(), count: 5)
        var glucose: [GlucoseSampleMgDl]?
        var labs: [LabResultSample]?
        var vitals: [VitalMetricComponent: [HKQuantitySample]] = [:]
        var checks = 0

        #expect(throws: StopBuilding.self) {
            _ = try CSVGenerator.generateCombinedCSV(
                weightSamples: &weight,
                stepsSamples: &steps,
                glucoseSamples: &glucose,
                labResults: &labs,
                vitalSamples: &vitals,
                weightUnit: .kilograms,
                checkCancellation: {
                    checks += 1
                    if checks == 2 { throw StopBuilding() }
                }
            )
        }
        #expect(checks == 2, "The build stops at the first check that throws")
        #expect(steps != nil, "Steps were never reached")
    }

    @Test func builder_checksDoNotChangeTheBytes() {
        let weight = samples(weightType, unit: .gramUnit(with: .kilo), count: CSVGenerator.rowsPerCancellationCheck + 10)
        var checkedWeight: [HKQuantitySample]? = weight
        var noSteps: [HKQuantitySample]?
        var noGlucose: [GlucoseSampleMgDl]?
        var noLabs: [LabResultSample]?
        var noVitals: [VitalMetricComponent: [HKQuantitySample]] = [:]

        let checked = CSVGenerator.generateCombinedCSV(
            weightSamples: &checkedWeight,
            stepsSamples: &noSteps,
            glucoseSamples: &noGlucose,
            labResults: &noLabs,
            vitalSamples: &noVitals,
            weightUnit: .pounds,
            checkCancellation: {}
        )
        let plain = CSVGenerator.generateCombinedCSV(
            weightSamples: weight,
            stepsSamples: nil,
            glucoseSamples: nil,
            labResults: nil,
            weightUnit: .pounds
        )

        #expect(checked == plain)
    }
}
