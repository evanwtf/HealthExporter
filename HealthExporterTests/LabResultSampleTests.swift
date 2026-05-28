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

    func testInit_fromFHIRData_a1cObservation_populatesSampleWithRegistryName() throws {
        let fhirJSON: [String: Any] = [
            "resourceType": "Observation",
            "code": [
                "coding": [
                    [
                        "system": "http://loinc.org",
                        "code": LOINCCode.hemoglobinA1C,
                        "display": "Hemoglobin A1c"
                    ]
                ]
            ],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": [
                "value": 7.2,
                "unit": "%"
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: fhirJSON)

        let sample = LabResultSample(
            fromFHIRData: data,
            loincCode: LOINCCode.hemoglobinA1C,
            source: "TestClinic"
        )

        let unwrapped = try XCTUnwrap(sample)
        XCTAssertEqual(unwrapped.metricName, "Hemoglobin A1C")
        XCTAssertEqual(unwrapped.loincCode, LOINCCode.hemoglobinA1C)
        XCTAssertEqual(unwrapped.value, 7.2, accuracy: 0.001)
        XCTAssertEqual(unwrapped.unit, "%")
        XCTAssertEqual(unwrapped.source, "TestClinic")
    }

    func testInit_fromFHIRData_unknownLoincInRegistry_returnsNil() {
        // Even if the FHIR data parses, we can't render the row without a
        // registry entry to supply the metric name. Bail out.
        let fhirJSON: [String: Any] = [
            "code": [
                "coding": [
                    ["system": "http://loinc.org", "code": "9999-9"]
                ]
            ],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": ["value": 1.0, "unit": "x"]
        ]
        let data = try! JSONSerialization.data(withJSONObject: fhirJSON)
        XCTAssertNil(LabResultSample(fromFHIRData: data, loincCode: "9999-9", source: ""))
    }

    func testInit_fromFHIRData_missingObservation_returnsNil() {
        let data = "not json".data(using: .utf8)!
        XCTAssertNil(LabResultSample(fromFHIRData: data, loincCode: LOINCCode.hemoglobinA1C, source: ""))
    }
}
