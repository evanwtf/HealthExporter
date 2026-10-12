import XCTest
@testable import HealthExporter

final class LabResultSampleTests: XCTestCase {

    private var referenceDate: Date {
        ISO8601DateFormatter().date(from: "2024-06-15T10:30:00Z")!
    }

    // MARK: - Memberwise initializer

    func testMemberwiseInit_preservesAllValues() {
        let sample = LabResultSample(
            metricName: "Hemoglobin A1C",
            loincCode: "4548-4",
            effectiveDateTime: referenceDate,
            value: 7.5,
            unit: "%",
            source: "MyClinic"
        )
        XCTAssertEqual(sample.metricName, "Hemoglobin A1C")
        XCTAssertEqual(sample.loincCode, "4548-4")
        XCTAssertEqual(sample.effectiveDateTime, referenceDate)
        XCTAssertEqual(sample.value, 7.5, accuracy: 0.001)
        XCTAssertEqual(sample.unit, "%")
        XCTAssertEqual(sample.source, "MyClinic")
    }

    func testMemberwiseInit_defaultSource_isEmpty() {
        let sample = LabResultSample(
            metricName: "Hemoglobin A1C",
            loincCode: "4548-4",
            effectiveDateTime: referenceDate,
            value: 6.1,
            unit: "%"
        )
        XCTAssertEqual(sample.source, "")
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

    func testInit_fromFHIRData_a1cObservation_populatesSampleWithRegistryName() throws {
        let sample = LabResultSample(fromFHIRData: fhirData(codes: [LOINCCode.hemoglobinA1C]), source: "TestClinic")

        let unwrapped = try XCTUnwrap(sample)
        XCTAssertEqual(unwrapped.metricName, "Hemoglobin A1C")
        XCTAssertEqual(unwrapped.loincCode, LOINCCode.hemoglobinA1C)
        XCTAssertEqual(unwrapped.value, 7.2, accuracy: 0.001)
        XCTAssertEqual(unwrapped.unit, "%")
        XCTAssertEqual(unwrapped.source, "TestClinic")
        XCTAssertNil(unwrapped.comparator)
    }

    func testInit_fromFHIRData_unknownLoincInRegistry_returnsNil() {
        XCTAssertNil(LabResultSample(fromFHIRData: fhirData(codes: ["9999-9"]), source: ""))
    }

    func testInit_fromFHIRData_missingObservation_returnsNil() {
        let data = "not json".data(using: .utf8)!
        XCTAssertNil(LabResultSample(fromFHIRData: data, source: ""))
    }

    func testInit_fromFHIRData_alternateCode_mapsToMetricAndKeepsFoundCode() throws {
        let sample = try XCTUnwrap(LabResultSample(fromFHIRData: fhirData(codes: ["13457-7"], value: 101, unit: "mg/dL"), source: "Lab"))
        XCTAssertEqual(sample.metricName, "LDL Cholesterol")
        XCTAssertEqual(sample.loincCode, "13457-7")
    }

    func testInit_fromFHIRData_codeNotRequested_returnsNil() {
        let lipidsOnly = LabMetricRegistry.codeIndex(for: LabMetricRegistry.metrics(in: .lipid))
        XCTAssertNil(LabResultSample(fromFHIRData: fhirData(codes: [LOINCCode.hemoglobinA1C]), source: "", codeIndex: lipidsOnly))
    }

    func testInit_fromFHIRData_recordMatchingTwoMetrics_yieldsOneSampleForFirstCoding() throws {
        let data = fhirData(codes: [LOINCCode.hdlCholesterol, LOINCCode.ldlCholesterolDirect], value: 50, unit: "mg/dL")
        let sample = try XCTUnwrap(LabResultSample(fromFHIRData: data, source: ""))
        XCTAssertEqual(sample.metricName, "HDL Cholesterol")
        XCTAssertEqual(sample.loincCode, LOINCCode.hdlCholesterol)
    }

    func testInit_fromFHIRData_skipsUnrequestedCodingAndUsesNextMatch() throws {
        let data = fhirData(codes: ["9999-9", "17856-6"], value: 6.1)
        let sample = try XCTUnwrap(LabResultSample(fromFHIRData: data, source: ""))
        XCTAssertEqual(sample.metricName, "Hemoglobin A1C")
        XCTAssertEqual(sample.loincCode, "17856-6")
    }

    func testInit_fromFHIRData_carriesComparator() throws {
        let data = fhirData(codes: [LOINCCode.estimatedGlomerularFiltrationRate], value: 60, unit: "mL/min/1.73m2", comparator: ">")
        let sample = try XCTUnwrap(LabResultSample(fromFHIRData: data, source: ""))
        XCTAssertEqual(sample.comparator, ">")
    }
}
