import XCTest
@testable import HealthExporter

final class FHIRLabResultParserTests: XCTestCase {

    // MARK: - Helpers

    private func makeFHIRJSON(
        loincCode: String = "4548-4",
        system: String = "http://loinc.org",
        effectiveDateTime: String = "2024-06-15T10:30:00Z",
        value: Any = 7.2,
        unit: String = "%"
    ) -> Data {
        let json: [String: Any] = [
            "resourceType": "Observation",
            "code": [
                "coding": [
                    ["system": system, "code": loincCode, "display": "Hemoglobin A1c"]
                ]
            ],
            "effectiveDateTime": effectiveDateTime,
            "valueQuantity": [
                "value": value,
                "unit": unit
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func makeFHIRJSONWithout(_ keyToOmit: String) -> Data {
        var json: [String: Any] = [
            "resourceType": "Observation",
            "code": [
                "coding": [
                    ["system": "http://loinc.org", "code": "4548-4", "display": "Hemoglobin A1c"]
                ]
            ],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": [
                "value": 7.2,
                "unit": "%"
            ]
        ]
        json.removeValue(forKey: keyToOmit)
        return try! JSONSerialization.data(withJSONObject: json)
    }

    // MARK: - Matching LOINC code

    func testMatchingLOINCCode_returnsResult() {
        let data = makeFHIRJSON(loincCode: "4548-4")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.value, 7.2, accuracy: 0.001)
        XCTAssertEqual(result?.unit, "%")
    }

    func testMatchingLOINCCode_parsesDateCorrectly() {
        let data = makeFHIRJSON(effectiveDateTime: "2024-06-15T10:30:00Z")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")

        XCTAssertNotNil(result)
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: result!.effectiveDateTime)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 30)
    }

    // MARK: - Non-matching LOINC code

    func testNonMatchingLOINCCode_returnsNil() {
        let data = makeFHIRJSON(loincCode: "4548-4")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "2093-3")
        XCTAssertNil(result)
    }

    func testWrongSystem_returnsNil() {
        let data = makeFHIRJSON(system: "http://snomed.org")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        XCTAssertNil(result)
    }

    // MARK: - Invalid/missing JSON

    func testInvalidJSON_returnsNil() {
        let data = "not json".data(using: .utf8)!
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        XCTAssertNil(result)
    }

    func testEmptyData_returnsNil() {
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: Data(), loincCode: "4548-4")
        XCTAssertNil(result)
    }

    func testEmptyJSONObject_returnsNil() {
        let data = try! JSONSerialization.data(withJSONObject: [:] as [String: Any])
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        XCTAssertNil(result)
    }

    // MARK: - Missing required fields

    func testMissingCodeField_returnsNil() {
        let data = makeFHIRJSONWithout("code")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        XCTAssertNil(result)
    }

    func testMissingEffectiveDateTime_returnsNil() {
        let data = makeFHIRJSONWithout("effectiveDateTime")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        XCTAssertNil(result)
    }

    func testMissingValueQuantity_returnsNil() {
        let data = makeFHIRJSONWithout("valueQuantity")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        XCTAssertNil(result)
    }

    // MARK: - Invalid field values

    func testInvalidDateTimeFormat_returnsNil() {
        let data = makeFHIRJSON(effectiveDateTime: "June 15, 2024")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        XCTAssertNil(result)
    }

    func testMissingValueInValueQuantity_returnsNil() {
        let json: [String: Any] = [
            "resourceType": "Observation",
            "code": ["coding": [["system": "http://loinc.org", "code": "4548-4"]]],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": ["unit": "%"]  // missing "value"
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        XCTAssertNil(result)
    }

    func testMissingUnitInValueQuantity_fallsBackToEmptyUnit() {
        let json: [String: Any] = [
            "resourceType": "Observation",
            "code": ["coding": [["system": "http://loinc.org", "code": "4548-4"]]],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": ["value": 7.2]  // missing "unit" and "code"
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        XCTAssertEqual(result?.unit, "")
        XCTAssertEqual(result?.value ?? 0, 7.2, accuracy: 0.001)
    }

    // MARK: - Empty coding array

    func testEmptyCodingArray_returnsNil() {
        let json: [String: Any] = [
            "resourceType": "Observation",
            "code": ["coding": []],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": ["value": 7.2, "unit": "%"]
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        XCTAssertNil(result)
    }

    // MARK: - Multiple codings (one matching)

    func testMultipleCodings_oneMatchingLOINC_returnsResult() {
        let json: [String: Any] = [
            "resourceType": "Observation",
            "code": [
                "coding": [
                    ["system": "http://snomed.org", "code": "12345"],
                    ["system": "http://loinc.org", "code": "4548-4", "display": "Hemoglobin A1c"]
                ]
            ],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": ["value": 6.8, "unit": "%"]
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")

        XCTAssertNotNil(result)
        XCTAssertEqual(result!.value, 6.8, accuracy: 0.001)
    }

    // MARK: - Unit fallback

    func testMissingUnit_fallsBackToUCUMCode() {
        let json: [String: Any] = [
            "code": ["coding": [["system": "http://loinc.org", "code": "4548-4"]]],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": ["value": 7.2, "system": "http://unitsofmeasure.org", "code": "%"]
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")?.unit, "%")
    }

    // MARK: - Comparator

    private func observation(valueQuantity: [String: Any]) -> FHIRObservation? {
        let json: [String: Any] = [
            "code": ["coding": [["system": "http://loinc.org", "code": "33914-3"]]],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": valueQuantity
        ]
        return FHIRLabResultParser.parseObservation(fromFHIRData: try! JSONSerialization.data(withJSONObject: json))
    }

    func testComparator_eachAllowedValueIsKept() {
        for comparator in ["<", "<=", ">", ">="] {
            let result = observation(valueQuantity: ["value": 60, "unit": "mL/min", "comparator": comparator])
            XCTAssertEqual(result?.comparator, comparator)
        }
    }

    func testComparator_absentIsNil() {
        XCTAssertNil(observation(valueQuantity: ["value": 60, "unit": "mL/min"])?.comparator)
    }

    func testComparator_unknownValueIsNil() {
        XCTAssertNil(observation(valueQuantity: ["value": 60, "unit": "mL/min", "comparator": "ad"])?.comparator)
    }

    // MARK: - Codes

    func testParseObservation_returnsLOINCCodesInRecordOrder() {
        let json: [String: Any] = [
            "code": ["coding": [
                ["system": "http://loinc.org", "code": "13457-7"],
                ["system": "http://snomed.org", "code": "12345"],
                ["system": "http://loinc.org", "code": "2089-1"]
            ]],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": ["value": 100, "unit": "mg/dL"]
        ]
        let result = FHIRLabResultParser.parseObservation(fromFHIRData: try! JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(result?.loincCodes, ["13457-7", "2089-1"])
    }

    // MARK: - FHIR date forms

    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    func testParseDate_fullDateTimeWithoutFraction() {
        XCTAssertEqual(FHIRLabResultParser.parseDate("2024-06-15T10:30:00Z"), utc(2024, 6, 15, 10, 30))
    }

    func testParseDate_fullDateTimeWithOffset() {
        XCTAssertEqual(FHIRLabResultParser.parseDate("2024-06-15T10:30:00-04:00"), utc(2024, 6, 15, 14, 30))
    }

    func testParseDate_fractionalSeconds() {
        let date = FHIRLabResultParser.parseDate("2024-06-15T10:30:00.123Z")
        XCTAssertNotNil(date)
        XCTAssertEqual(date!.timeIntervalSince(utc(2024, 6, 15, 10, 30)), 0.123, accuracy: 0.001)
    }

    func testParseDate_fractionalSecondsWithOffset() {
        let date = FHIRLabResultParser.parseDate("2024-06-15T10:30:00.5+02:00")
        XCTAssertNotNil(date)
        XCTAssertEqual(date!.timeIntervalSince(utc(2024, 6, 15, 8, 30)), 0.5, accuracy: 0.001)
    }

    func testParseDate_dateOnly_isStartOfDayUTC() {
        XCTAssertEqual(FHIRLabResultParser.parseDate("2024-06-15"), utc(2024, 6, 15))
    }

    func testParseDate_yearMonth_isFirstOfMonthUTC() {
        XCTAssertEqual(FHIRLabResultParser.parseDate("2024-06"), utc(2024, 6, 1))
    }

    func testParseDate_yearOnly_isJanuaryFirstUTC() {
        XCTAssertEqual(FHIRLabResultParser.parseDate("2024"), utc(2024, 1, 1))
    }

    func testParseDate_garbage_isNil() {
        for value in ["", "June 15, 2024", "2024-13", "2024-02-30", "24-06-15", "2024-6-15", "2024-06-15T10:30", "abcd", "2024-06-15Z"] {
            XCTAssertNil(FHIRLabResultParser.parseDate(value), value)
        }
    }

    /// `parseDate` used two `ISO8601DateFormatter`s before it moved to
    /// `Date.ISO8601FormatStyle`. Pin the date-time results to the old ones.
    func testParseDate_dateTimeMatchesISO8601DateFormatter() {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let inputs = [
            "2024-06-15T10:30:00Z",
            "2024-06-15T10:30:00-04:00",
            "2024-06-15T10:30:00+14:00",
            "2024-06-15T10:30:00.123Z",
            "2024-06-15T10:30:00.5+02:00",
            "2024-06-15T10:30:00.123456Z",
            "2024-06-15T10:30:00.Z",
            "2024-06-15T10:30:00",
            "2024-06-15T10:30Z",
            "2024-06-15T10:30",
            "2024-06-15T10:30:00+0200",
            "2024-06-15T10:30:00+02",
            "2024-06-15T10:30:00z",
            "2024-06-15T25:00:00Z",
            "2024-02-30T10:00:00Z",
            "20240615T103000Z",
            "2024-06-15T",
            "T10:30:00Z",
        ]
        for input in inputs {
            let expected = fractional.date(from: input) ?? plain.date(from: input)
            let actual = FHIRLabResultParser.parseDate(input)
            XCTAssertEqual(actual == nil, expected == nil, "\(input): expected \(String(describing: expected)), got \(String(describing: actual))")
            if let expected, let actual {
                XCTAssertEqual(actual.timeIntervalSinceReferenceDate, expected.timeIntervalSinceReferenceDate, accuracy: 0.001, input)
            }
        }
    }

    // MARK: - Effective date fallbacks

    private func observationData(dateFields: [String: Any]) -> Data {
        var json: [String: Any] = [
            "code": ["coding": [["system": "http://loinc.org", "code": "4548-4"]]],
            "valueQuantity": ["value": 7.2, "unit": "%"]
        ]
        json.merge(dateFields) { _, new in new }
        return try! JSONSerialization.data(withJSONObject: json)
    }

    func testEffectiveInstant_usedWhenDateTimeAbsent() {
        let data = observationData(dateFields: ["effectiveInstant": "2024-06-15T10:30:00.250Z"])
        let result = FHIRLabResultParser.parseObservation(fromFHIRData: data)
        XCTAssertEqual(result!.effectiveDateTime.timeIntervalSince(utc(2024, 6, 15, 10, 30)), 0.25, accuracy: 0.001)
    }

    func testEffectivePeriodStart_usedWhenDateTimeAndInstantAbsent() {
        let data = observationData(dateFields: ["effectivePeriod": ["start": "2024-06-15", "end": "2024-06-16"]])
        XCTAssertEqual(FHIRLabResultParser.parseObservation(fromFHIRData: data)?.effectiveDateTime, utc(2024, 6, 15))
    }

    func testEffectiveDateTime_winsOverFallbacks() {
        let data = observationData(dateFields: [
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "effectiveInstant": "2023-01-01T00:00:00Z",
            "effectivePeriod": ["start": "2022-01-01"]
        ])
        XCTAssertEqual(FHIRLabResultParser.parseObservation(fromFHIRData: data)?.effectiveDateTime, utc(2024, 6, 15, 10, 30))
    }
}
