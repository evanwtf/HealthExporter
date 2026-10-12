import Foundation
import Testing
@testable import HealthExporter

struct LabMetricRegistryTests {

    // MARK: - LabPanel

    @Test func labPanel_hasFiveCases() {
        #expect(LabPanel.allCases.count == 5)
    }

    @Test func labPanel_containsExpectedGroups() {
        let cases = Set(LabPanel.allCases)
        #expect(cases == [.lipid, .cbc, .cmp, .thyroid, .other])
    }

    @Test func labPanel_displayNamesMatchExportSections() {
        #expect(LabPanel.lipid.displayName == "Lipid panel")
        #expect(LabPanel.cbc.displayName == "CBC")
        #expect(LabPanel.cmp.displayName == "CMP / BMP")
        #expect(LabPanel.thyroid.displayName == "Thyroid")
        #expect(LabPanel.other.displayName == "Other")
    }

    // MARK: - LabMetric

    @Test func labMetric_idEqualsLoincCode() {
        let metric = LabMetric(
            name: "Hemoglobin A1C",
            loincCode: "4548-4",
            group: .other,
            valuePrecision: 2
        )
        #expect(metric.id == metric.loincCode)
        #expect(metric.id == "4548-4")
    }

    // MARK: - LabMetricRegistry

    @Test func registry_containsHemoglobinA1C() {
        let a1c = LabMetricRegistry.all.first { $0.loincCode == LOINCCode.hemoglobinA1C }
        #expect(a1c != nil)
        #expect(a1c?.name == "Hemoglobin A1C")
        #expect(a1c?.group == .other)
        #expect(a1c?.valuePrecision == 2)
    }

    @Test func registry_loincCodesAreUnique() {
        let codes = LabMetricRegistry.all.map(\.loincCode)
        #expect(Set(codes).count == codes.count, "Duplicate LOINC codes in registry: \(codes)")
    }

    @Test func registry_lookupByLoincCode_returnsMatchingMetric() {
        let metric = LabMetricRegistry.metric(forLoincCode: LOINCCode.hemoglobinA1C)
        #expect(metric != nil)
        #expect(metric?.loincCode == LOINCCode.hemoglobinA1C)
    }

    @Test func registry_lookupByLoincCode_missingCode_returnsNil() {
        #expect(LabMetricRegistry.metric(forLoincCode: "9999-9") == nil)
    }

    @Test func registry_metricsForPanel_other_includesA1C() {
        let others = LabMetricRegistry.metrics(in: .other)
        #expect(others.contains { $0.loincCode == LOINCCode.hemoglobinA1C })
    }

    @Test func registry_metricsForPanel_lipid_includesExpectedMetrics() {
        let lipids = LabMetricRegistry.metrics(in: .lipid)
        let expectedCodes: Set<String> = [
            LOINCCode.totalCholesterol,
            LOINCCode.hdlCholesterol,
            LOINCCode.ldlCholesterolDirect,
            LOINCCode.triglycerides
        ]

        #expect(Set(lipids.map(\.loincCode)) == expectedCodes)
        #expect(lipids.allSatisfy { $0.group == .lipid })
        #expect(lipids.allSatisfy { $0.valuePrecision == 0 })
    }

    @Test func registry_lipidMetricsHaveExpectedNames() {
        let metricsByCode = Dictionary(uniqueKeysWithValues: LabMetricRegistry.metrics(in: .lipid).map { ($0.loincCode, $0.name) })
        #expect(metricsByCode[LOINCCode.totalCholesterol] == "Total Cholesterol")
        #expect(metricsByCode[LOINCCode.hdlCholesterol] == "HDL Cholesterol")
        #expect(metricsByCode[LOINCCode.ldlCholesterolDirect] == "LDL Cholesterol")
        #expect(metricsByCode[LOINCCode.triglycerides] == "Triglycerides")
    }

    @Test func registry_metricsForPanel_cbc_includesExpectedMetrics() {
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

        #expect(Set(cbc.map(\.loincCode)) == expectedCodes)
        #expect(cbc.allSatisfy { $0.group == .cbc })
    }

    @Test func registry_metricsForPanel_cmp_includesExpectedMetrics() {
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

        #expect(Set(cmp.map(\.loincCode)) == expectedCodes)
        #expect(cmp.allSatisfy { $0.group == .cmp })
    }

    @Test func registry_metricsForPanel_thyroid_includesExpectedMetrics() {
        let thyroid = LabMetricRegistry.metrics(in: .thyroid)
        let expectedCodes: Set<String> = [
            LOINCCode.thyroidStimulatingHormone,
            LOINCCode.freeT4,
            LOINCCode.freeT3
        ]

        #expect(Set(thyroid.map(\.loincCode)) == expectedCodes)
        #expect(thyroid.allSatisfy { $0.group == .thyroid })
    }

    @Test func registry_metricsForPanel_other_includesExpectedTrackedLabs() {
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

        #expect(Set(others.map(\.loincCode)) == expectedCodes)
        #expect(others.allSatisfy { $0.group == .other })
    }

    // MARK: - Alternate LOINC codes

    @Test func registry_allCodesIncludingAlternatesAreUnique() {
        let codes = LabMetricRegistry.all.flatMap(\.allLoincCodes)
        #expect(Set(codes).count == codes.count, "A LOINC code maps to two metrics: \(codes)")
    }

    @Test(arguments: [
        ("13457-7", LOINCCode.ldlCholesterolDirect),
        ("18262-6", LOINCCode.ldlCholesterolDirect),
        ("2345-7", LOINCCode.fastingGlucose),
        ("98979-8", LOINCCode.estimatedGlomerularFiltrationRate),
        ("62238-1", LOINCCode.estimatedGlomerularFiltrationRate),
        ("17856-6", LOINCCode.hemoglobinA1C)
    ])
    func registry_alternatesResolveToPrimaryMetric(alternate: String, primary: String) {
        #expect(LabMetricRegistry.metric(forLoincCode: alternate)?.loincCode == primary, "\(alternate)")
        #expect(LabMetricRegistry.metric(forLoincCode: alternate)?.id == primary, "\(alternate)")
    }

    @Test func registry_primaryIdentityUnchanged() {
        #expect(LabMetricRegistry.metric(forLoincCode: LOINCCode.ldlCholesterolDirect)?.id == "2089-1")
        #expect(LabMetricRegistry.metric(forLoincCode: LOINCCode.fastingGlucose)?.id == "1558-6")
        #expect(LabMetricRegistry.metric(forLoincCode: LOINCCode.estimatedGlomerularFiltrationRate)?.id == "33914-3")
        #expect(LabMetricRegistry.metric(forLoincCode: LOINCCode.hemoglobinA1C)?.id == "4548-4")
    }

    @Test func codeIndex_onlyCoversRequestedMetrics() {
        let index = LabMetricRegistry.codeIndex(for: LabMetricRegistry.metrics(in: .lipid))
        #expect(index["13457-7"]?.loincCode == LOINCCode.ldlCholesterolDirect)
        #expect(index[LOINCCode.hemoglobinA1C] == nil)
    }

    @Test func codeIndex_primaryCodeWinsOverAnotherMetricsAlternate() {
        let a = LabMetric(name: "A", loincCode: "1-1", group: .other, valuePrecision: 0, alternateLoincCodes: ["2-2"])
        let b = LabMetric(name: "B", loincCode: "2-2", group: .other, valuePrecision: 0)
        #expect(LabMetricRegistry.codeIndex(for: [a, b])["2-2"]?.name == "B")
    }
}
