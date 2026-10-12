import Foundation
import Testing
@testable import HealthExporter

struct FHIRLabResultParserTests {

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

    @Test func matchingLOINCCode_returnsResult() {
        let data = makeFHIRJSON(loincCode: "4548-4")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")

        #expect(result != nil)
        #expect(abs(result!.value - 7.2) <= 0.001)
        #expect(result?.unit == "%")
    }

    @Test func matchingLOINCCode_parsesDateCorrectly() {
        let data = makeFHIRJSON(effectiveDateTime: "2024-06-15T10:30:00Z")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")

        #expect(result != nil)
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: result!.effectiveDateTime)
        #expect(components.year == 2024)
        #expect(components.month == 6)
        #expect(components.day == 15)
        #expect(components.hour == 10)
        #expect(components.minute == 30)
    }

    // MARK: - Non-matching LOINC code

    @Test func nonMatchingLOINCCode_returnsNil() {
        let data = makeFHIRJSON(loincCode: "4548-4")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "2093-3")
        #expect(result == nil)
    }

    @Test func wrongSystem_returnsNil() {
        let data = makeFHIRJSON(system: "http://snomed.org")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    // MARK: - Invalid/missing JSON

    @Test func invalidJSON_returnsNil() {
        let data = "not json".data(using: .utf8)!
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    @Test func emptyData_returnsNil() {
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: Data(), loincCode: "4548-4")
        #expect(result == nil)
    }

    @Test func emptyJSONObject_returnsNil() {
        let data = try! JSONSerialization.data(withJSONObject: [:] as [String: Any])
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    // MARK: - Missing required fields

    @Test func missingCodeField_returnsNil() {
        let data = makeFHIRJSONWithout("code")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    @Test func missingEffectiveDateTime_returnsNil() {
        let data = makeFHIRJSONWithout("effectiveDateTime")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    @Test func missingValueQuantity_returnsNil() {
        let data = makeFHIRJSONWithout("valueQuantity")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    // MARK: - Invalid field values

    @Test func invalidDateTimeFormat_returnsNil() {
        let data = makeFHIRJSON(effectiveDateTime: "June 15, 2024")
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    @Test func missingValueInValueQuantity_returnsNil() {
        let json: [String: Any] = [
            "resourceType": "Observation",
            "code": ["coding": [["system": "http://loinc.org", "code": "4548-4"]]],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": ["unit": "%"]  // missing "value"
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    @Test func missingUnitInValueQuantity_fallsBackToEmptyUnit() {
        let json: [String: Any] = [
            "resourceType": "Observation",
            "code": ["coding": [["system": "http://loinc.org", "code": "4548-4"]]],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": ["value": 7.2]  // missing "unit" and "code"
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result?.unit == "")
        #expect(abs((result?.value ?? 0) - 7.2) <= 0.001)
    }

    // MARK: - Empty coding array

    @Test func emptyCodingArray_returnsNil() {
        let json: [String: Any] = [
            "resourceType": "Observation",
            "code": ["coding": []],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": ["value": 7.2, "unit": "%"]
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let result = FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")
        #expect(result == nil)
    }

    // MARK: - Multiple codings (one matching)

    @Test func multipleCodings_oneMatchingLOINC_returnsResult() {
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

        #expect(result != nil)
        #expect(abs(result!.value - 6.8) <= 0.001)
    }

    // MARK: - Unit fallback

    @Test func missingUnit_fallsBackToUCUMCode() {
        let json: [String: Any] = [
            "code": ["coding": [["system": "http://loinc.org", "code": "4548-4"]]],
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "valueQuantity": ["value": 7.2, "system": "http://unitsofmeasure.org", "code": "%"]
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        #expect(FHIRLabResultParser.extractLabResult(fromFHIRData: data, loincCode: "4548-4")?.unit == "%")
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

    @Test(arguments: ["<", "<=", ">", ">="])
    func comparator_eachAllowedValueIsKept(comparator: String) {
        let result = observation(valueQuantity: ["value": 60, "unit": "mL/min", "comparator": comparator])
        #expect(result?.comparator == comparator)
    }

    @Test func comparator_absentIsNil() {
        #expect(observation(valueQuantity: ["value": 60, "unit": "mL/min"])?.comparator == nil)
    }

    @Test func comparator_unknownValueIsNil() {
        #expect(observation(valueQuantity: ["value": 60, "unit": "mL/min", "comparator": "ad"])?.comparator == nil)
    }

    // MARK: - Codes

    @Test func parseObservation_returnsLOINCCodesInRecordOrder() {
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
        #expect(result?.loincCodes == ["13457-7", "2089-1"])
    }

    // MARK: - FHIR date forms

    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    @Test func parseDate_fullDateTimeWithoutFraction() {
        #expect(FHIRLabResultParser.parseDate("2024-06-15T10:30:00Z") == utc(2024, 6, 15, 10, 30))
    }

    @Test func parseDate_fullDateTimeWithOffset() {
        #expect(FHIRLabResultParser.parseDate("2024-06-15T10:30:00-04:00") == utc(2024, 6, 15, 14, 30))
    }

    @Test func parseDate_fractionalSeconds() {
        let date = FHIRLabResultParser.parseDate("2024-06-15T10:30:00.123Z")
        #expect(date != nil)
        #expect(abs(date!.timeIntervalSince(utc(2024, 6, 15, 10, 30)) - 0.123) <= 0.001)
    }

    @Test func parseDate_fractionalSecondsWithOffset() {
        let date = FHIRLabResultParser.parseDate("2024-06-15T10:30:00.5+02:00")
        #expect(date != nil)
        #expect(abs(date!.timeIntervalSince(utc(2024, 6, 15, 8, 30)) - 0.5) <= 0.001)
    }

    @Test func parseDate_dateOnly_isStartOfDayUTC() {
        #expect(FHIRLabResultParser.parseDate("2024-06-15") == utc(2024, 6, 15))
    }

    @Test func parseDate_yearMonth_isFirstOfMonthUTC() {
        #expect(FHIRLabResultParser.parseDate("2024-06") == utc(2024, 6, 1))
    }

    @Test func parseDate_yearOnly_isJanuaryFirstUTC() {
        #expect(FHIRLabResultParser.parseDate("2024") == utc(2024, 1, 1))
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

    private func observationData(dateFields: [String: Any]) -> Data {
        var json: [String: Any] = [
            "code": ["coding": [["system": "http://loinc.org", "code": "4548-4"]]],
            "valueQuantity": ["value": 7.2, "unit": "%"]
        ]
        json.merge(dateFields) { _, new in new }
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test func effectiveInstant_usedWhenDateTimeAbsent() {
        let data = observationData(dateFields: ["effectiveInstant": "2024-06-15T10:30:00.250Z"])
        let result = FHIRLabResultParser.parseObservation(fromFHIRData: data)
        #expect(abs(result!.effectiveDateTime.timeIntervalSince(utc(2024, 6, 15, 10, 30)) - 0.25) <= 0.001)
    }

    @Test func effectivePeriodStart_usedWhenDateTimeAndInstantAbsent() {
        let data = observationData(dateFields: ["effectivePeriod": ["start": "2024-06-15", "end": "2024-06-16"]])
        #expect(FHIRLabResultParser.parseObservation(fromFHIRData: data)?.effectiveDateTime == utc(2024, 6, 15))
    }

    @Test func effectiveDateTime_winsOverFallbacks() {
        let data = observationData(dateFields: [
            "effectiveDateTime": "2024-06-15T10:30:00Z",
            "effectiveInstant": "2023-01-01T00:00:00Z",
            "effectivePeriod": ["start": "2022-01-01"]
        ])
        #expect(FHIRLabResultParser.parseObservation(fromFHIRData: data)?.effectiveDateTime == utc(2024, 6, 15, 10, 30))
    }
}
