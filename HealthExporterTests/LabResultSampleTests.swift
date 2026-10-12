import Foundation
import Testing
@testable import HealthExporter

struct LabResultSampleTests {

    private var referenceDate: Date {
        ISO8601DateFormatter().date(from: "2024-06-15T10:30:00Z")!
    }

    // MARK: - Memberwise initializer

    @Test func memberwiseInit_preservesAllValues() {
        let sample = LabResultSample(
            metricName: "Hemoglobin A1C",
            loincCode: "4548-4",
            effectiveDateTime: referenceDate,
            value: 7.5,
            unit: "%",
            source: "MyClinic"
        )
        #expect(sample.metricName == "Hemoglobin A1C")
        #expect(sample.loincCode == "4548-4")
        #expect(sample.effectiveDateTime == referenceDate)
        #expect(abs(sample.value - 7.5) <= 0.001)
        #expect(sample.unit == "%")
        #expect(sample.source == "MyClinic")
    }

    @Test func memberwiseInit_defaultSource_isEmpty() {
        let sample = LabResultSample(
            metricName: "Hemoglobin A1C",
            loincCode: "4548-4",
            effectiveDateTime: referenceDate,
            value: 6.1,
            unit: "%"
        )
        #expect(sample.source == "")
    }

    // MARK: - FHIR data initializer

    private func fhirData(codes: [String], value: Any = 7.2, unit: String = "%", comparator: String? = nil) -> Data {
        var quantity: [String: Any] = ["value": value, "unit": unit]
        quantity["comparator"] = comparator
        let json: [String: Any] = [
            "resourceType": "Observation",
            "code": ["coding": codes.map { ["system": "http://loinc.org", "code": $0] }],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": quantity
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test func init_fromFHIRData_a1cObservation_populatesSampleWithRegistryName() throws {
        let sample = LabResultSample(fromFHIRData: fhirData(codes: [LOINCCode.hemoglobinA1C]), source: "TestClinic")

        let unwrapped = try #require(sample)
        #expect(unwrapped.metricName == "Hemoglobin A1C")
        #expect(unwrapped.loincCode == LOINCCode.hemoglobinA1C)
        #expect(abs(unwrapped.value - 7.2) <= 0.001)
        #expect(unwrapped.unit == "%")
        #expect(unwrapped.source == "TestClinic")
        #expect(unwrapped.comparator == nil)
    }

    @Test func init_fromFHIRData_unknownLoincInRegistry_returnsNil() {
        #expect(LabResultSample(fromFHIRData: fhirData(codes: ["9999-9"]), source: "") == nil)
    }

    @Test func init_fromFHIRData_missingObservation_returnsNil() {
        let data = "not json".data(using: .utf8)!
        #expect(LabResultSample(fromFHIRData: data, source: "") == nil)
    }

    @Test func init_fromFHIRData_alternateCode_mapsToMetricAndKeepsFoundCode() throws {
        let sample = try #require(LabResultSample(fromFHIRData: fhirData(codes: ["13457-7"], value: 101, unit: "mg/dL"), source: "Lab"))
        #expect(sample.metricName == "LDL Cholesterol")
        #expect(sample.loincCode == "13457-7")
    }

    @Test func init_fromFHIRData_codeNotRequested_returnsNil() {
        let lipidsOnly = LabMetricRegistry.codeIndex(for: LabMetricRegistry.metrics(in: .lipid))
        #expect(LabResultSample(fromFHIRData: fhirData(codes: [LOINCCode.hemoglobinA1C]), source: "", codeIndex: lipidsOnly) == nil)
    }

    @Test func init_fromFHIRData_recordMatchingTwoMetrics_yieldsOneSampleForFirstCoding() throws {
        let data = fhirData(codes: [LOINCCode.hdlCholesterol, LOINCCode.ldlCholesterolDirect], value: 50, unit: "mg/dL")
        let sample = try #require(LabResultSample(fromFHIRData: data, source: ""))
        #expect(sample.metricName == "HDL Cholesterol")
        #expect(sample.loincCode == LOINCCode.hdlCholesterol)
    }

    @Test func init_fromFHIRData_skipsUnrequestedCodingAndUsesNextMatch() throws {
        let data = fhirData(codes: ["9999-9", "17856-6"], value: 6.1)
        let sample = try #require(LabResultSample(fromFHIRData: data, source: ""))
        #expect(sample.metricName == "Hemoglobin A1C")
        #expect(sample.loincCode == "17856-6")
    }

    @Test func init_fromFHIRData_carriesComparator() throws {
        let data = fhirData(codes: [LOINCCode.estimatedGlomerularFiltrationRate], value: 60, unit: "mL/min/1.73m2", comparator: ">")
        let sample = try #require(LabResultSample(fromFHIRData: data, source: ""))
        #expect(sample.comparator == ">")
    }
}
