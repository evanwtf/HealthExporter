import HealthKit

struct ExportPreviewEstimate {
    static let confirmationRowThreshold = 500
    static let confirmationByteThreshold = 1_000_000

    let rowCount: Int
    let estimatedByteCount: Int

    var roundedRowCount: Int {
        Self.roundedRowCount(for: rowCount)
    }

    var formattedRowCount: String {
        roundedRowCount.formatted()
    }

    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(estimatedByteCount), countStyle: .file)
    }

    var summaryText: String {
        "This will export around \(formattedRowCount) rows (\(formattedByteCount))."
    }

    var shouldShowConfirmation: Bool {
        rowCount > Self.confirmationRowThreshold || estimatedByteCount > Self.confirmationByteThreshold
    }

    static func roundedRowCount(for count: Int) -> Int {
        guard count > 0 else { return 0 }

        if count < 1_000 {
            return max(100, ((count + 50) / 100) * 100)
        }

        return ((count + 500) / 1_000) * 1_000
    }
}

class CSVGenerator {

    static let csvHeader = "Date,Metric,Value,Unit,Source"

    private static func makeDateFormatter(for option: DateFormatOption) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = option.dateFormat
        if option.isUTC {
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
        }
        return formatter
    }

    /// Wraps a value in double quotes if it contains commas or quotes (RFC 4180).
    private static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    private static func weightRow(for sample: HKQuantitySample, unit: WeightUnit, dateFormatter: DateFormatter) -> String {
        let date = dateFormatter.string(from: sample.startDate)
        let weightKg = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
        let (value, unitString) = convertWeight(weightKg, to: unit)
        let source = csvEscape(sample.sourceRevision.source.name)
        return "\(date),Weight,\(String(format: "%.2f", value)),\(unitString),\(source)\n"
    }

    private static func stepsRow(for sample: HKQuantitySample, dateFormatter: DateFormatter) -> String {
        let date = dateFormatter.string(from: sample.startDate)
        let steps = sample.quantity.doubleValue(for: HKUnit.count())
        let source = csvEscape(sample.sourceRevision.source.name)
        return "\(date),Steps,\(Int(steps)),steps,\(source)\n"
    }

    private static func glucoseRow(for sample: GlucoseSampleMgDl, dateFormatter: DateFormatter) -> String {
        let date = dateFormatter.string(from: sample.startDate)
        let source = csvEscape(sample.source)
        return "\(date),Blood Glucose,\(String(format: "%.0f", sample.value)),mg/dL,\(source)\n"
    }

    private static func labResultRow(for sample: LabResultSample, dateFormatter: DateFormatter) -> String {
        let date = dateFormatter.string(from: sample.effectiveDateTime)
        let metric = csvEscape(sample.metricName)
        let source = csvEscape(sample.source)
        let precision = LabMetricRegistry.metric(forLoincCode: sample.loincCode)?.valuePrecision ?? 2
        let value = String(format: "%.\(precision)f", sample.value)
        return "\(date),\(metric),\(value),\(sample.unit),\(source)\n"
    }

    // MARK: - Append methods (memory-efficient, sort in-place, write directly to string)

    static func appendWeightRows(to csv: inout String, samples: inout [HKQuantitySample], unit: WeightUnit, dateFormat: DateFormatOption = .yyyyMMddHHmmss, sortOrder: SortOrder = .ascending) {
        let dateFormatter = makeDateFormatter(for: dateFormat)
        samples.sort { sortOrder == .ascending ? $0.startDate < $1.startDate : $0.startDate > $1.startDate }
        for sample in samples {
            csv.append(weightRow(for: sample, unit: unit, dateFormatter: dateFormatter))
        }
    }

    static func appendStepsRows(to csv: inout String, samples: inout [HKQuantitySample], dateFormat: DateFormatOption = .yyyyMMddHHmmss, sortOrder: SortOrder = .ascending) {
        let dateFormatter = makeDateFormatter(for: dateFormat)
        samples.sort { sortOrder == .ascending ? $0.startDate < $1.startDate : $0.startDate > $1.startDate }
        for sample in samples {
            csv.append(stepsRow(for: sample, dateFormatter: dateFormatter))
        }
    }

    static func appendGlucoseRows(to csv: inout String, samples: inout [GlucoseSampleMgDl], dateFormat: DateFormatOption = .yyyyMMddHHmmss, sortOrder: SortOrder = .ascending) {
        let dateFormatter = makeDateFormatter(for: dateFormat)
        samples.sort { sortOrder == .ascending ? $0.startDate < $1.startDate : $0.startDate > $1.startDate }
        for sample in samples {
            csv.append(glucoseRow(for: sample, dateFormatter: dateFormatter))
        }
    }

    static func appendLabResultRows(to csv: inout String, samples: inout [LabResultSample], dateFormat: DateFormatOption = .yyyyMMddHHmmss, sortOrder: SortOrder = .ascending) {
        let dateFormatter = makeDateFormatter(for: dateFormat)
        samples.sort { sortOrder == .ascending ? $0.effectiveDateTime < $1.effectiveDateTime : $0.effectiveDateTime > $1.effectiveDateTime }
        for sample in samples {
            csv.append(labResultRow(for: sample, dateFormatter: dateFormatter))
        }
    }

    static func makePreviewEstimate(weightSamples: [HKQuantitySample]?, stepsSamples: [HKQuantitySample]?, glucoseSamples: [GlucoseSampleMgDl]?, labResults: [LabResultSample]?, weightUnit: WeightUnit, dateFormat: DateFormatOption = .yyyyMMddHHmmss) -> ExportPreviewEstimate {
        let weightCount = weightSamples?.count ?? 0
        let stepsCount = stepsSamples?.count ?? 0
        let glucoseCount = glucoseSamples?.count ?? 0
        let labCount = labResults?.count ?? 0
        let rowCount = weightCount + stepsCount + glucoseCount + labCount

        let dateFormatter = makeDateFormatter(for: dateFormat)
        var estimatedByteCount = (csvHeader + "\n").utf8.count

        if let samples = weightSamples {
            for sample in samples {
                estimatedByteCount += weightRow(for: sample, unit: weightUnit, dateFormatter: dateFormatter).utf8.count
            }
        }

        if let samples = stepsSamples {
            for sample in samples {
                estimatedByteCount += stepsRow(for: sample, dateFormatter: dateFormatter).utf8.count
            }
        }

        if let samples = glucoseSamples {
            for sample in samples {
                estimatedByteCount += glucoseRow(for: sample, dateFormatter: dateFormatter).utf8.count
            }
        }

        if let samples = labResults {
            for sample in samples {
                estimatedByteCount += labResultRow(for: sample, dateFormatter: dateFormatter).utf8.count
            }
        }

        return ExportPreviewEstimate(rowCount: rowCount, estimatedByteCount: estimatedByteCount)
    }

    // MARK: - Legacy convenience methods (used by tests and single-metric exports)

    static func generateWeightCSV(from samples: [HKQuantitySample], unit: WeightUnit, dateFormat: DateFormatOption = .yyyyMMddHHmmss, sortOrder: SortOrder = .ascending) -> String {
        var csv = csvHeader + "\n"
        var mutableSamples = samples
        appendWeightRows(to: &csv, samples: &mutableSamples, unit: unit, dateFormat: dateFormat, sortOrder: sortOrder)
        return csv
    }

    static func generateStepsCSV(from samples: [HKQuantitySample], dateFormat: DateFormatOption = .yyyyMMddHHmmss, sortOrder: SortOrder = .ascending) -> String {
        var csv = csvHeader + "\n"
        var mutableSamples = samples
        appendStepsRows(to: &csv, samples: &mutableSamples, dateFormat: dateFormat, sortOrder: sortOrder)
        return csv
    }

    static func generateCombinedCSV(weightSamples: [HKQuantitySample]?, stepsSamples: [HKQuantitySample]?, glucoseSamples: [GlucoseSampleMgDl]?, labResults: [LabResultSample]?, weightUnit: WeightUnit, dateFormat: DateFormatOption = .yyyyMMddHHmmss, sortOrder: SortOrder = .ascending) -> String {
        var csv = csvHeader + "\n"

        if var samples = weightSamples {
            appendWeightRows(to: &csv, samples: &samples, unit: weightUnit, dateFormat: dateFormat, sortOrder: sortOrder)
        }

        if var samples = stepsSamples {
            appendStepsRows(to: &csv, samples: &samples, dateFormat: dateFormat, sortOrder: sortOrder)
        }

        if var samples = glucoseSamples {
            appendGlucoseRows(to: &csv, samples: &samples, dateFormat: dateFormat, sortOrder: sortOrder)
        }

        if var samples = labResults {
            appendLabResultRows(to: &csv, samples: &samples, dateFormat: dateFormat, sortOrder: sortOrder)
        }

        return csv
    }

    private static func convertWeight(_ weightKg: Double, to unit: WeightUnit) -> (Double, String) {
        switch unit {
        case .kilograms:
            return (weightKg, "kg")
        case .pounds:
            let weightLbs = weightKg * 2.2046226218
            return (weightLbs, "lbs")
        }
    }
}
