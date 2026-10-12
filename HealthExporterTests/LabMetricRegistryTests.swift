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

    func testLabPanel_displayNamesMatchExportSections() {
        XCTAssertEqual(LabPanel.lipid.displayName, "Lipid panel")
        XCTAssertEqual(LabPanel.cbc.displayName, "CBC")
        XCTAssertEqual(LabPanel.cmp.displayName, "CMP / BMP")
        XCTAssertEqual(LabPanel.thyroid.displayName, "Thyroid")
        XCTAssertEqual(LabPanel.other.displayName, "Other")
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

    func testRegistry_metricsForPanel_cbc_includesExpectedMetrics() {
        let cbc = LabMetricRegistry.metrics(in: .cbc)
        let expectedCodes: Set<String> = [
            LOINCCode.whiteBloodCellCount,
            LOINCCode.redBloodCellCount,
            LOINCCode.hemoglobin,
            LOINCCode.hematocrit,
            LOINCCode.platelets,
            LOINCCode.meanCorpuscularVolume,
            LOINCCode.meanCorpuscularHemoglobin,
            LOINCCode.meanCorpuscularHemoglobinConcentration,
            LOINCCode.redCellDistributionWidth
        ]

        XCTAssertEqual(Set(cbc.map(\.loincCode)), expectedCodes)
        XCTAssertTrue(cbc.allSatisfy { $0.group == .cbc })
    }

    func testRegistry_metricsForPanel_cmp_includesExpectedMetrics() {
        let cmp = LabMetricRegistry.metrics(in: .cmp)
        let expectedCodes: Set<String> = [
            LOINCCode.fastingGlucose,
            LOINCCode.bloodUreaNitrogen,
            LOINCCode.creatinine,
            LOINCCode.estimatedGlomerularFiltrationRate,
            LOINCCode.sodium,
            LOINCCode.potassium,
            LOINCCode.chloride,
            LOINCCode.carbonDioxideBicarbonate,
            LOINCCode.calcium,
            LOINCCode.totalProtein,
            LOINCCode.albumin,
            LOINCCode.bilirubinTotal,
            LOINCCode.alanineAminotransferase,
            LOINCCode.aspartateAminotransferase,
            LOINCCode.alkalinePhosphatase
        ]

        XCTAssertEqual(Set(cmp.map(\.loincCode)), expectedCodes)
        XCTAssertTrue(cmp.allSatisfy { $0.group == .cmp })
    }

    func testRegistry_metricsForPanel_thyroid_includesExpectedMetrics() {
        let thyroid = LabMetricRegistry.metrics(in: .thyroid)
        let expectedCodes: Set<String> = [
            LOINCCode.thyroidStimulatingHormone,
            LOINCCode.freeT4,
            LOINCCode.freeT3
        ]

        XCTAssertEqual(Set(thyroid.map(\.loincCode)), expectedCodes)
        XCTAssertTrue(thyroid.allSatisfy { $0.group == .thyroid })
    }

    func testRegistry_metricsForPanel_other_includesExpectedTrackedLabs() {
        let others = LabMetricRegistry.metrics(in: .other)
        let expectedCodes: Set<String> = [
            LOINCCode.hemoglobinA1C,
            LOINCCode.vitaminD25Hydroxy,
            LOINCCode.vitaminB12,
            LOINCCode.ferritin,
            LOINCCode.iron,
            LOINCCode.totalIronBindingCapacity,
            LOINCCode.highSensitivityCRP
        ]

        XCTAssertEqual(Set(others.map(\.loincCode)), expectedCodes)
        XCTAssertTrue(others.allSatisfy { $0.group == .other })
    }

    // MARK: - Alternate LOINC codes

    func testRegistry_allCodesIncludingAlternatesAreUnique() {
        let codes = LabMetricRegistry.all.flatMap(\.allLoincCodes)
        XCTAssertEqual(Set(codes).count, codes.count, "A LOINC code maps to two metrics: \(codes)")
    }

    func testRegistry_alternatesResolveToPrimaryMetric() {
        let expected: [String: String] = [
            "13457-7": LOINCCode.ldlCholesterolDirect,
            "18262-6": LOINCCode.ldlCholesterolDirect,
            "2345-7": LOINCCode.fastingGlucose,
            "98979-8": LOINCCode.estimatedGlomerularFiltrationRate,
            "62238-1": LOINCCode.estimatedGlomerularFiltrationRate,
            "17856-6": LOINCCode.hemoglobinA1C
        ]
        for (alternate, primary) in expected {
            XCTAssertEqual(LabMetricRegistry.metric(forLoincCode: alternate)?.loincCode, primary, alternate)
            XCTAssertEqual(LabMetricRegistry.metric(forLoincCode: alternate)?.id, primary, alternate)
        }
    }

    func testRegistry_primaryIdentityUnchanged() {
        XCTAssertEqual(LabMetricRegistry.metric(forLoincCode: LOINCCode.ldlCholesterolDirect)?.id, "2089-1")
        XCTAssertEqual(LabMetricRegistry.metric(forLoincCode: LOINCCode.fastingGlucose)?.id, "1558-6")
        XCTAssertEqual(LabMetricRegistry.metric(forLoincCode: LOINCCode.estimatedGlomerularFiltrationRate)?.id, "33914-3")
        XCTAssertEqual(LabMetricRegistry.metric(forLoincCode: LOINCCode.hemoglobinA1C)?.id, "4548-4")
    }

    func testCodeIndex_onlyCoversRequestedMetrics() {
        let index = LabMetricRegistry.codeIndex(for: LabMetricRegistry.metrics(in: .lipid))
        XCTAssertEqual(index["13457-7"]?.loincCode, LOINCCode.ldlCholesterolDirect)
        XCTAssertNil(index[LOINCCode.hemoglobinA1C])
    }

    func testCodeIndex_primaryCodeWinsOverAnotherMetricsAlternate() {
        let a = LabMetric(name: "A", loincCode: "1-1", group: .other, valuePrecision: 0, alternateLoincCodes: ["2-2"])
        let b = LabMetric(name: "B", loincCode: "2-2", group: .other, valuePrecision: 0)
        XCTAssertEqual(LabMetricRegistry.codeIndex(for: [a, b])["2-2"]?.name, "B")
    }
}
