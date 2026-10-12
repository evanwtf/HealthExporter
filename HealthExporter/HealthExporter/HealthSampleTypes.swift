import HealthKit
import os

nonisolated private let logger = Logger(subsystem: "com.HealthExporter", category: "HealthSampleTypes")

// MARK: - Glucose Sample Type
nonisolated struct GlucoseSampleMgDl: Sendable {
    let startDate: Date
    let value: Double // mg/dL value (e.g., 145.0 for 145 mg/dL)
    let source: String
    let mealTime: HKBloodGlucoseMealTime?

    init(startDate: Date, value: Double, source: String, mealTime: HKBloodGlucoseMealTime? = nil) {
        self.startDate = startDate
        self.value = value
        self.source = source
        self.mealTime = mealTime
    }

    init?(from sample: HKQuantitySample) {
        let glucoseUnit = HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))
        let mgDlValue = sample.quantity.doubleValue(for: glucoseUnit)
        // Blood glucose values are typically 20-600 mg/dL, reject values < 20 (likely % misinterpreted)
        guard mgDlValue >= 20 else {
            logger.debug("Filtered glucose value \(mgDlValue, privacy: .private) mg/dL (below 20 threshold) from \(sample.startDate, privacy: .private)")
            return nil
        }
        self.startDate = sample.startDate
        self.value = mgDlValue
        self.source = sample.sourceRevision.source.name
        self.mealTime = Self.mealTime(fromMetadata: sample.metadata)
    }

    /// Imported C enums accept any raw value, so map the known cases explicitly.
    static func mealTime(fromMetadata metadata: [String: Any]?) -> HKBloodGlucoseMealTime? {
        guard let raw = metadata?[HKMetadataKeyBloodGlucoseMealTime] as? NSNumber else {
            return nil
        }
        switch raw.intValue {
        case HKBloodGlucoseMealTime.preprandial.rawValue: return .preprandial
        case HKBloodGlucoseMealTime.postprandial.rawValue: return .postprandial
        default: return nil
        }
    }
}

// MARK: - LOINC Code Constants
/// Common LOINC codes for lab results
nonisolated struct LOINCCode {
    static let hemoglobinA1C = "4548-4"
    static let hemoglobinA1CHPLC = "17856-6"

    static let totalCholesterol = "2093-3"
    static let hdlCholesterol = "2085-9"
    static let ldlCholesterolDirect = "2089-1"
    static let ldlCholesterolCalculated = "13457-7"
    static let ldlCholesterolDirectAssay = "18262-6"
    static let triglycerides = "2571-8"

    static let whiteBloodCellCount = "6690-2"
    static let redBloodCellCount = "789-8"
    static let hemoglobin = "718-7"
    static let hematocrit = "4544-3"
    static let platelets = "777-3"
    static let meanCorpuscularVolume = "787-2"
    static let meanCorpuscularHemoglobin = "785-6"
    static let meanCorpuscularHemoglobinConcentration = "786-4"
    static let redCellDistributionWidth = "788-0"

    static let fastingGlucose = "1558-6"
    static let glucoseSerumPlasma = "2345-7"
    static let bloodUreaNitrogen = "3094-0"
    static let creatinine = "2160-0"
    static let estimatedGlomerularFiltrationRate = "33914-3"
    static let eGFRCKDEPI2021 = "98979-8"
    static let eGFRCKDEPI = "62238-1"
    static let sodium = "2951-2"
    static let potassium = "2823-3"
    static let chloride = "2075-0"
    static let carbonDioxideBicarbonate = "2028-9"
    static let calcium = "17861-6"
    static let totalProtein = "2885-2"
    static let albumin = "1751-7"
    static let bilirubinTotal = "1975-2"
    static let alanineAminotransferase = "1742-6"
    static let aspartateAminotransferase = "1920-8"
    static let alkalinePhosphatase = "6768-6"

    static let thyroidStimulatingHormone = "3016-3"
    static let freeT4 = "3024-7"
    static let freeT3 = "3051-0"

    static let vitaminD25Hydroxy = "1989-3"
    static let vitaminB12 = "2132-9"
    static let ferritin = "2276-4"
    static let iron = "2498-4"
    static let totalIronBindingCapacity = "2500-7"
    static let highSensitivityCRP = "30522-7"
}

// MARK: - FHIR Lab Result Helper

/// The fields of one FHIR Observation that the exporter uses.
nonisolated struct FHIRObservation: Sendable {
    /// LOINC codes from `code.coding`, in record order.
    let loincCodes: [String]
    let effectiveDateTime: Date
    let value: Double
    let unit: String
    /// One of `<`, `<=`, `>`, `>=`, or nil.
    let comparator: String?
}

nonisolated struct FHIRLabResultParser {
    static let loincSystem = "http://loinc.org"
    static let allowedComparators: Set<String> = ["<", "<=", ">", ">="]

    /// Parses the JSON once. Returns nil when the date or numeric value is missing or invalid.
    static func parseObservation(fromFHIRData fhirData: Data) -> FHIRObservation? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: fhirData, options: []),
              let json = jsonObject as? [String: Any] else {
            return nil
        }

        let coding = (json["code"] as? [String: Any])?["coding"] as? [[String: Any]] ?? []
        let loincCodes = coding.compactMap { entry -> String? in
            guard (entry["system"] as? String) == loincSystem else { return nil }
            return entry["code"] as? String
        }

        let dateString = json["effectiveDateTime"] as? String
            ?? json["effectiveInstant"] as? String
            ?? (json["effectivePeriod"] as? [String: Any])?["start"] as? String
        guard let dateString, let effectiveDateTime = parseDate(dateString) else {
            return nil
        }

        guard let valueQuantity = json["valueQuantity"] as? [String: Any],
              let value = valueQuantity["value"] as? NSNumber else {
            return nil
        }
        let unit = valueQuantity["unit"] as? String ?? valueQuantity["code"] as? String ?? ""
        let comparator = (valueQuantity["comparator"] as? String).flatMap { allowedComparators.contains($0) ? $0 : nil }

        return FHIRObservation(
            loincCodes: loincCodes,
            effectiveDateTime: effectiveDateTime,
            value: value.doubleValue,
            unit: unit,
            comparator: comparator
        )
    }

    /// Parses the observation and returns it only when it carries `loincCode`.
    static func extractLabResult(fromFHIRData fhirData: Data, loincCode: String) -> FHIRObservation? {
        guard let observation = parseObservation(fromFHIRData: fhirData),
              observation.loincCodes.contains(loincCode) else {
            return nil
        }
        return observation
    }

    // Sendable format styles, so the parser can run off the main actor.
    private static let dateTimeStyle = Date.ISO8601FormatStyle()
    private static let fractionalDateTimeStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// Parses a FHIR `dateTime` or `instant`: a full date-time with or without
    /// fractional seconds, or a partial date (`YYYY-MM-DD`, `YYYY-MM`, `YYYY`).
    /// A partial date resolves to the start of that period in UTC.
    static func parseDate(_ string: String) -> Date? {
        if string.contains("T") {
            return (try? fractionalDateTimeStyle.parse(string)) ?? (try? dateTimeStyle.parse(string))
        }

        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count),
              parts[0].count == 4,
              parts.dropFirst().allSatisfy({ $0.count == 2 }),
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }) else {
            return nil
        }
        let numbers = parts.compactMap { Int($0) }
        var components = DateComponents()
        components.year = numbers[0]
        components.month = numbers.count > 1 ? numbers[1] : 1
        components.day = numbers.count > 2 ? numbers[2] : 1
        guard components.isValidDate(in: utcCalendar) else {
            return nil
        }
        return utcCalendar.date(from: components)
    }
}

// MARK: - Generic Lab Result Sample

/// Generic lab result row used by the lab pipeline. Carries everything needed
/// to render a CSV row: human-readable metric name, the LOINC code found in the
/// record, and the observation's date/value/unit/source/comparator.
nonisolated struct LabResultSample: Sendable {
    let metricName: String
    let loincCode: String
    let effectiveDateTime: Date
    let value: Double
    let unit: String
    let source: String
    let comparator: String?

    init(
        metricName: String,
        loincCode: String,
        effectiveDateTime: Date,
        value: Double,
        unit: String,
        source: String = "",
        comparator: String? = nil
    ) {
        self.metricName = metricName
        self.loincCode = loincCode
        self.effectiveDateTime = effectiveDateTime
        self.value = value
        self.unit = unit
        self.source = source
        self.comparator = comparator
    }

    /// Builds one sample from a parsed observation. The first LOINC coding (in
    /// record order) found in `codeIndex` picks the metric, so a record coded
    /// for two requested metrics produces one row, not two.
    init?(observation: FHIRObservation, source: String, codeIndex: [String: LabMetric]) {
        guard let match = observation.loincCodes.lazy.compactMap({ code in codeIndex[code].map { (code, $0) } }).first else {
            return nil
        }
        self.init(
            metricName: match.1.name,
            loincCode: match.0,
            effectiveDateTime: observation.effectiveDateTime,
            value: observation.value,
            unit: observation.unit,
            source: source,
            comparator: observation.comparator
        )
    }

    init?(fromFHIRData fhirData: Data, source: String, codeIndex: [String: LabMetric] = LabMetricRegistry.codeIndex) {
        guard let observation = FHIRLabResultParser.parseObservation(fromFHIRData: fhirData) else {
            return nil
        }
        self.init(observation: observation, source: source, codeIndex: codeIndex)
    }
}
