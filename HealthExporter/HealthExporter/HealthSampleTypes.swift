import HealthKit
import os

private let logger = Logger(subsystem: "com.HealthExporter", category: "HealthSampleTypes")

// MARK: - Glucose Sample Type
struct GlucoseSampleMgDl {
    let startDate: Date
    let value: Double // mg/dL value (e.g., 145.0 for 145 mg/dL)
    let source: String

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
    }
}

// MARK: - LOINC Code Constants
/// Common LOINC codes for lab results
struct LOINCCode {
    static let hemoglobinA1C = "4548-4"
    // Add future LOINC codes here:
    // static let totalCholesterol = "2093-3"
    // static let hdlCholesterol = "2085-9"
    // static let ldlCholesterol = "2089-1"
    // static let triglycerides = "2571-8"
}

// MARK: - FHIR Lab Result Helper
/// Helper struct for extracting lab result data from FHIR resources
struct FHIRLabResultParser {
    /// Extracts lab result data from a clinical record for a specific LOINC code
    /// - Parameters:
    ///   - clinicalRecord: The HKClinicalRecord containing FHIR data
    ///   - loincCode: The LOINC code to search for (e.g., "4548-4" for Hemoglobin A1C)
    /// - Returns: Tuple of (effectiveDateTime, value, unit) if found, nil otherwise
    /// Extracts lab result data from a clinical record for a specific LOINC code
    static func extractLabResult(from clinicalRecord: HKClinicalRecord, loincCode: String) -> (effectiveDateTime: Date, value: Double, unit: String)? {
        guard let fhirResource = clinicalRecord.fhirResource else {
            return nil
        }
        return extractLabResult(fromFHIRData: fhirResource.data, loincCode: loincCode)
    }

    /// Extracts lab result data from raw FHIR JSON data for a specific LOINC code.
    /// This is the pure parsing logic, separated from HKClinicalRecord for testability.
    static func extractLabResult(fromFHIRData fhirData: Data, loincCode: String) -> (effectiveDateTime: Date, value: Double, unit: String)? {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: fhirData, options: []),
              let json = jsonObject as? [String: Any] else {
            return nil
        }

        // Check if this is a lab result with the specified LOINC code
        guard let code = json["code"] as? [String: Any],
              let coding = code["coding"] as? [[String: Any]],
              coding.contains(where: { ($0["system"] as? String) == "http://loinc.org" && ($0["code"] as? String) == loincCode }) else {
            return nil
        }

        // Extract effective date time
        guard let effectiveDateTimeStr = json["effectiveDateTime"] as? String else {
            return nil
        }

        // Parse ISO 8601 datetime
        let iso8601Formatter = ISO8601DateFormatter()
        guard let effectiveDateTime = iso8601Formatter.date(from: effectiveDateTimeStr) else {
            return nil
        }

        // Extract value from valueQuantity
        guard let valueQuantity = json["valueQuantity"] as? [String: Any],
              let value = valueQuantity["value"] as? NSNumber,
              let unit = valueQuantity["unit"] as? String else {
            return nil
        }

        return (effectiveDateTime, value.doubleValue, unit)
    }
}

// MARK: - Generic Lab Result Sample

/// Generic lab result row used by the lab pipeline. Carries everything needed
/// to render a CSV row: human-readable metric name, LOINC identifier, and the
/// observation's date/value/unit/source.
struct LabResultSample {
    let metricName: String
    let loincCode: String
    let effectiveDateTime: Date
    let value: Double
    let unit: String
    let source: String

    init(
        metricName: String,
        loincCode: String,
        effectiveDateTime: Date,
        value: Double,
        unit: String,
        source: String = ""
    ) {
        self.metricName = metricName
        self.loincCode = loincCode
        self.effectiveDateTime = effectiveDateTime
        self.value = value
        self.unit = unit
        self.source = source
    }

    /// Builds a LabResultSample from raw FHIR JSON data for a known LOINC code.
    /// Returns nil if the FHIR resource cannot be parsed or the LOINC code is
    /// not registered in `LabMetricRegistry`.
    init?(fromFHIRData fhirData: Data, loincCode: String, source: String) {
        guard let metric = LabMetricRegistry.metric(forLoincCode: loincCode),
              let result = FHIRLabResultParser.extractLabResult(fromFHIRData: fhirData, loincCode: loincCode) else {
            return nil
        }
        self.metricName = metric.name
        self.loincCode = loincCode
        self.effectiveDateTime = result.effectiveDateTime
        self.value = result.value
        self.unit = result.unit
        self.source = source
    }

    /// Builds a LabResultSample from an HKClinicalRecord for a known LOINC code.
    init?(from clinicalRecord: HKClinicalRecord, loincCode: String) {
        guard let fhirResource = clinicalRecord.fhirResource else {
            return nil
        }
        self.init(
            fromFHIRData: fhirResource.data,
            loincCode: loincCode,
            source: clinicalRecord.sourceRevision.source.name
        )
    }
}

