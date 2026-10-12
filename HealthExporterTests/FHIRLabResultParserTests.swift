import Foundation
@testable import HealthExporter
import Testing

struct FHIRLabResultParserTests {
    // MARK: - Helpers

    private func makeFHIRJSON(
        loincCode: String = "4548-4",
        system: String = "http://loinc.org",
        effectiveDateTime: String = "2024-06-15T10:30:00Z",
        value: Any = 7.2,
        unit: String = "%"
    ) throws -> Data {
        let json: [String: Any] = [
            "resourceType": "Observation",
            "code": [
                "coding": [
                    ["system": system, "code": loincCode, "display": "Hemoglobin A1c"],
                ],
            ],
            "effectiveDateTime": effectiveDateTime,
            "valueQuantity": [
                "value": value,
                "unit": unit,
            ],
        ]
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func makeFHIRJSONWithout(_ keyToOmit: String) throws -> Data {
        var json: [String: Any] = [
            "resourceType": "Observation",
            "code": [
                "coding": [
                    ["system": "http://loinc.org", "code": "4548-4", "display": "Hemoglobin A1c"],
                ],
            ],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": [
                "value": 7.2,
                "unit": "%",
            ],
        ]
        json.removeValue(forKey: keyToOmit)
        return try JSONSerialization.data(withJSONObject: json)
    }

    // MARK: - Matching LOINC code

    @Test func matchingLOINCCode_returnsResult() throws {
        let data = try makeFHIRJSON(loincCode: "4548-4")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")

        #expect(result != nil)
        #expect(try abs(#require(result?.value) - 7.2) <= 0.001)
        #expect(result?.unit == "%")
    }

    @Test func matchingLOINCCode_parsesDateCorrectly() throws {
        let data = try makeFHIRJSON(effectiveDateTime: "2024-06-15T10:30:00Z")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")

        #expect(result != nil)
        let calendar = Calendar(identifier: .gregorian)
        let components = try calendar.dateComponents(in: #require(TimeZone(identifier: "UTC")), from: #require(result?.effectiveDateTime))
        #expect(components.year == 2024)
        #expect(components.month == 6)
        #expect(components.day == 15)
        #expect(components.hour == 10)
        #expect(components.minute == 30)
    }

    // MARK: - Non-matching LOINC code

    @Test func nonMatchingLOINCCode_returnsNil() throws {
        let data = try makeFHIRJSON(loincCode: "4548-4")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "2093-3")
        #expect(result == nil)
    }

    @Test func wrongSystem_returnsNil() throws {
        let data = try makeFHIRJSON(system: "http://snomed.org")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    // MARK: - Invalid/missing JSON

    @Test func invalidJSON_returnsNil() {
        let data = Data("not json".utf8)
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    @Test func emptyData_returnsNil() {
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: Data(), loincCode: "4548-4")
        #expect(result == nil)
    }

    @Test func emptyJSONObject_returnsNil() throws {
        let data = try JSONSerialization.data(withJSONObject: [:] as [String: Any])
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    // MARK: - Missing required fields

    @Test func missingCodeField_returnsNil() throws {
        let data = try makeFHIRJSONWithout("code")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    @Test func missingEffectiveDateTime_returnsNil() throws {
        let data = try makeFHIRJSONWithout("effectiveDateTime")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    @Test func missingValueQuantity_returnsNil() throws {
        let data = try makeFHIRJSONWithout("valueQuantity")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    // MARK: - Invalid field values

    @Test func invalidDateTimeFormat_returnsNil() throws {
        let data = try makeFHIRJSON(effectiveDateTime: "June 15, 2024")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    @Test func missingValueInValueQuantity_returnsNil() throws {
        let json: [String: Any] = [
            "resourceType": "Observation",
            "code": ["coding": [["system": "http://loinc.org", "code": "4548-4"]]],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": ["unit": "%"], // missing "value"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    @Test func missingUnitInValueQuantity_fallsBackToEmptyUnit() throws {
        let json: [String: Any] = [
            "resourceType": "Observation",
            "code": ["coding": [["system": "http://loinc.org", "code": "4548-4"]]],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": ["value": 7.2], // missing "unit" and "code"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result?.unit.isEmpty == true)
        #expect(abs((result?.value ?? 0) - 7.2) <= 0.001)
    }

    // MARK: - Empty coding array

    @Test func emptyCodingArray_returnsNil() throws {
        let json: [String: Any] = [
            "resourceType": "Observation",
            "code": ["coding": []],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": ["value": 7.2, "unit": "%"],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    // MARK: - Multiple codings (one matching)

    @Test func multipleCodings_oneMatchingLOINC_returnsResult() throws {
        let json: [String: Any] = [
            "resourceType": "Observation",
            "code": [
                "coding": [
                    ["system": "http://snomed.org", "code": "12345"],
                    ["system": "http://loinc.org", "code": "4548-4", "display": "Hemoglobin A1c"],
                ],
            ],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": ["value": 6.8, "unit": "%"],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")

        #expect(result != nil)
        #expect(try abs(#require(result?.value) - 6.8) <= 0.001)
    }

    // MARK: - Unit fallback

    @Test func missingUnit_fallsBackToUCUMCode() throws {
        let json: [String: Any] = [
            "code": ["coding": [["system": "http://loinc.org", "code": "4548-4"]]],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": ["value": 7.2, "system": "http://unitsofmeasure.org", "code": "%"],
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")?.unit == "%")
    }

    // MARK: - Comparator

    private func observation(valueQuantity: [String: Any]) throws -> FHIRObservation? {
        let json: [String: Any] = [
            "code": ["coding": [["system": "http://loinc.org", "code": "33914-3"]]],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": valueQuantity,
        ]
        return try FHIRLabResultParser.parseObservation(fromFHIRData: JSONSerialization.data(withJSONObject: json))
    }

    @Test(arguments: ["<", "<=", ">", ">="])
    func comparator_eachAllowedValueIsKept(comparator: String) throws {
        let result = try observation(valueQuantity: ["value": 60, "unit": "mL/min", "comparator": comparator])
        #expect(result?.comparator == comparator)
    }

    @Test func comparator_absentIsNil() throws {
        #expect(try observation(valueQuantity: ["value": 60, "unit": "mL/min"])?.comparator == nil)
    }

    @Test func comparator_unknownValueIsNil() throws {
        #expect(try observation(valueQuantity: ["value": 60, "unit": "mL/min", "comparator": "ad"])?.comparator == nil)
    }

    // MARK: - Codes

    @Test func parseObservation_returnsLOINCCodesInRecordOrder() throws {
        let json: [String: Any] = [
            "code": ["coding": [
                ["system": "http://loinc.org", "code": "13457-7"],
                ["system": "http://snomed.org", "code": "12345"],
                ["system": "http://loinc.org", "code": "2089-1"],
            ]],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": ["value": 100, "unit": "mg/dL"],
        ]
        let result = try FHIRLabResultParser.parseObservation(fromFHIRData: JSONSerialization.data(withJSONObject: json))
        #expect(result?.loincCodes == ["13457-7", "2089-1"])
    }

    // MARK: - FHIR date forms

    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return try #require(calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s)))
    }

    @Test func parseDate_fullDateTimeWithoutFraction() throws {
        #expect(try FHIRLabResultParser.parseDate("2024-06-15T10:30:00Z") == utc(2024, 6, 15, 10, 30))
    }

    @Test func parseDate_fullDateTimeWithOffset() throws {
        #expect(try FHIRLabResultParser.parseDate("2024-06-15T10:30:00-04:00") == utc(2024, 6, 15, 14, 30))
    }

    @Test func parseDate_fractionalSeconds() throws {
        let date = FHIRLabResultParser.parseDate("2024-06-15T10:30:00.123Z")
        #expect(date != nil)
        #expect(try abs(#require(try date?.timeIntervalSince(utc(2024, 6, 15, 10, 30))) - 0.123) <= 0.001)
    }

    @Test func parseDate_fractionalSecondsWithOffset() throws {
        let date = FHIRLabResultParser.parseDate("2024-06-15T10:30:00.5+02:00")
        #expect(date != nil)
        #expect(try abs(#require(try date?.timeIntervalSince(utc(2024, 6, 15, 8, 30))) - 0.5) <= 0.001)
    }

    @Test func parseDate_dateOnly_isStartOfDayUTC() throws {
        #expect(try FHIRLabResultParser.parseDate("2024-06-15") == utc(2024, 6, 15))
    }

    @Test func parseDate_yearMonth_isFirstOfMonthUTC() throws {
        #expect(try FHIRLabResultParser.parseDate("2024-06") == utc(2024, 6, 1))
    }

    @Test func parseDate_yearOnly_isJanuaryFirstUTC() throws {
        #expect(try FHIRLabResultParser.parseDate("2024") == utc(2024, 1, 1))
    }

    @Test(arguments: ["", "June 15, 2024", "2024-13", "2024-02-30", "24-06-15", "2024-6-15", "2024-06-15T10:30", "abcd", "2024-06-15Z"])
    func parseDate_garbage_isNil(value: String) {
        #expect(FHIRLabResultParser.parseDate(value) == nil, "\(value)")
    }

    nonisolated static let iso8601DateTimeInputs: [String] = [
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
        "2024-06-15T24:00:00Z",
        "2024-06-15T24:30:00Z",
        "2024-06-15T24:00:01Z",
        "2024-06-15T23:60:00Z",
        "2024-06-15T23:59:60Z",
        "2024-06-15T23:59:59Z",
        "2024-06-15T00:00:00Z",
        "2024-06-15T23:59:59.999+05:30",
        "2024-02-30T10:00:00Z",
        "20240615T103000Z",
        "2024-06-15T",
        "T10:30:00Z",
    ]

    /// `parseDate` used two `ISO8601DateFormatter`s before it moved to
    /// `Date.ISO8601FormatStyle`. Pin the date-time results to the old ones.
    @Test(arguments: iso8601DateTimeInputs)
    func parseDate_dateTimeMatchesISO8601DateFormatter(input: String) {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expected = fractional.date(from: input) ?? plain.date(from: input)
        let actual = FHIRLabResultParser.parseDate(input)
        #expect((actual == nil) == (expected == nil), "\(input): expected \(String(describing: expected)), got \(String(describing: actual))")
        if let expected, let actual {
            #expect(abs(actual.timeIntervalSinceReferenceDate - expected.timeIntervalSinceReferenceDate) <= 0.001, "\(input)")
        }
    }

    // MARK: - Effective date fallbacks

    private func observationData(dateFields: [String: Any]) throws -> Data {
        var json: [String: Any] = [
            "code": ["coding": [["system": "http://loinc.org", "code": "4548-4"]]],
            "valueQuantity": ["value": 7.2, "unit": "%"],
        ]
        json.merge(dateFields) { _, new in new }
        return try JSONSerialization.data(withJSONObject: json)
    }

    @Test func effectiveInstant_usedWhenDateTimeAbsent() throws {
        let data = try observationData(dateFields: ["effectiveInstant": "2024-06-15T10:30:00.250Z"])
        let result = FHIRLabResultParser.parseObservation(fromFHIRData: data)
        #expect(try abs(#require(try result?.effectiveDateTime.timeIntervalSince(utc(2024, 6, 15, 10, 30))) - 0.25) <= 0.001)
    }

    @Test func effectivePeriodStart_usedWhenDateTimeAndInstantAbsent() throws {
        let data = try observationData(dateFields: ["effectivePeriod": ["start": "2024-06-15", "end": "2024-06-16"]])
        #expect(try FHIRLabResultParser.parseObservation(fromFHIRData: data)?.effectiveDateTime == utc(2024, 6, 15))
    }

    @Test func effectiveDateTime_winsOverFallbacks() throws {
        let data = try observationData(dateFields: [
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "effectiveInstant": "2023-01-01T00:00:00Z",
            "effectivePeriod": ["start": "2022-01-01"],
        ])
        #expect(try FHIRLabResultParser.parseObservation(fromFHIRData: data)?.effectiveDateTime == utc(2024, 6, 15, 10, 30))
    }
}
