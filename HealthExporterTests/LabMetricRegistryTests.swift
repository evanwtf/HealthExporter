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

    func testRegistry_metricsForPanel_lipid_isInitiallyEmpty() {
        // Lipid/CBC/CMP/Thyroid panels are scaffolded for future labs but seeded
        // empty in this refactor — only A1C exists today.
        XCTAssertTrue(LabMetricRegistry.metrics(in: .lipid).isEmpty)
    }
}
