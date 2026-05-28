import XCTest
@testable import HealthExporter

final class LabMetricRegistryTests: XCTestCase {

    // MARK: - LabPanel

    func testLabPanel_hasFiveCases() {
        XCTAssertEqual(LabPanel.allCases.count, 5)
    }

    func testLabPanel_containsExpectedGroups() {
        let cases = Set(LabPanel.allCases)
        XCTAssertEqual(cases, [.lipid, .cbc, .cmp, .thyroid, .other])
    }

    // MARK: - LabMetric

    func testLabMetric_idEqualsLoincCode() {
        let metric = LabMetric(
            name: "Hemoglobin A1C",
            loincCode: "4548-4",
            group: .other,
            valuePrecision: 2
        )
        XCTAssertEqual(metric.id, metric.loincCode)
        XCTAssertEqual(metric.id, "4548-4")
    }

    // MARK: - LabMetricRegistry

    func testRegistry_containsHemoglobinA1C() {
        let a1c = LabMetricRegistry.all.first { $0.loincCode == LOINCCode.hemoglobinA1C }
        XCTAssertNotNil(a1c)
        XCTAssertEqual(a1c?.name, "Hemoglobin A1C")
        XCTAssertEqual(a1c?.group, .other)
        XCTAssertEqual(a1c?.valuePrecision, 2)
    }

    func testRegistry_loincCodesAreUnique() {
        let codes = LabMetricRegistry.all.map(\.loincCode)
        XCTAssertEqual(Set(codes).count, codes.count, "Duplicate LOINC codes in registry: \(codes)")
    }

    func testRegistry_lookupByLoincCode_returnsMatchingMetric() {
        let metric = LabMetricRegistry.metric(forLoincCode: LOINCCode.hemoglobinA1C)
        XCTAssertNotNil(metric)
        XCTAssertEqual(metric?.loincCode, LOINCCode.hemoglobinA1C)
    }

    func testRegistry_lookupByLoincCode_missingCode_returnsNil() {
        XCTAssertNil(LabMetricRegistry.metric(forLoincCode: "9999-9"))
    }

    func testRegistry_metricsForPanel_other_includesA1C() {
        let others = LabMetricRegistry.metrics(in: .other)
        XCTAssertTrue(others.contains { $0.loincCode == LOINCCode.hemoglobinA1C })
    }

    func testRegistry_metricsForPanel_lipid_includesExpectedMetrics() {
        let lipids = LabMetricRegistry.metrics(in: .lipid)
        let expectedCodes: Set<String> = [
            LOINCCode.totalCholesterol,
            LOINCCode.hdlCholesterol,
            LOINCCode.ldlCholesterolDirect,
            LOINCCode.triglycerides
        ]

        XCTAssertEqual(Set(lipids.map(\.loincCode)), expectedCodes)
        XCTAssertTrue(lipids.allSatisfy { $0.group == .lipid })
        XCTAssertTrue(lipids.allSatisfy { $0.valuePrecision == 0 })
    }

    func testRegistry_lipidMetricsHaveExpectedNames() {
        let metricsByCode = Dictionary(uniqueKeysWithValues: LabMetricRegistry.metrics(in: .lipid).map { ($0.loincCode, $0.name) })
        XCTAssertEqual(metricsByCode[LOINCCode.totalCholesterol], "Total Cholesterol")
        XCTAssertEqual(metricsByCode[LOINCCode.hdlCholesterol], "HDL Cholesterol")
        XCTAssertEqual(metricsByCode[LOINCCode.ldlCholesterolDirect], "LDL Cholesterol")
        XCTAssertEqual(metricsByCode[LOINCCode.triglycerides], "Triglycerides")
    }
}
