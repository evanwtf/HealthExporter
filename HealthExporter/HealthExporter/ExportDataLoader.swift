import HealthKit
import os

nonisolated private let logger = Logger(subsystem: "com.HealthExporter", category: "ExportDataLoader")

/// The fields of one clinical record that the export reads.
/// Tests cannot build an `HKClinicalRecord`, so the store hands these over.
nonisolated struct ClinicalRecordPayload: Sendable {
    let fhirData: Data
    let sourceName: String
}

/// The HealthKit calls the export needs. `HealthKitManager` is the real store;
/// tests inject a fake.
nonisolated protocol HealthDataStore: Sendable {
    func requestReadAuthorization(for types: Set<HKObjectType>) async throws

    /// Returns samples newest first. A nil `limit` returns every sample.
    func quantitySamples(
        of identifier: HKQuantityTypeIdentifier,
        dateRange: (startDate: Date, endDate: Date)?,
        limit: Int?
    ) async throws -> [HKQuantitySample]

    /// Returns every lab-result clinical record in the date range, newest first.
    func labResultRecords(dateRange: (startDate: Date, endDate: Date)?) async throws -> [ClinicalRecordPayload]

    /// Returns the earliest date the app can read, for each type the user
    /// gave limited-history access to (iOS 27). A type with full access is
    /// not in the result. Before iOS 27 the result is empty.
    func earliestAuthorizedSampleDates(for types: Set<HKObjectType>) async throws -> [HKObjectType: Date]
}

/// What the user selected for one export.
nonisolated struct ExportRequest: Sendable {
    var includeWeight: Bool
    var includeSteps: Bool
    var includeGlucose: Bool
    var labMetrics: [LabMetric]
    var vitalMetrics: Set<VitalMetric>
    var dateRange: (startDate: Date, endDate: Date)?
    /// `HKObjectQueryNoLimit` (0) means no limit.
    var recordLimit: Int

    /// The selected vital components, in display order.
    var vitalComponents: [VitalMetricComponent] {
        let components = Set(vitalMetrics.flatMap(\.components))
        return VitalMetricComponent.allCases.filter { components.contains($0) }
    }

    /// The metrics to fetch, in display order.
    var metrics: [ExportMetric] {
        var metrics: [ExportMetric] = []
        if includeWeight { metrics.append(.weight) }
        if includeSteps { metrics.append(.steps) }
        if includeGlucose { metrics.append(.glucose) }
        if !labMetrics.isEmpty { metrics.append(.labResults) }
        metrics.append(contentsOf: vitalComponents.map(ExportMetric.vital))
        return metrics
    }

    var readTypes: Set<HKObjectType> {
        HealthKitQueryHelpers.readTypes(
            includeWeight: includeWeight,
            includeSteps: includeSteps,
            includeGlucose: includeGlucose,
            includeLabs: !labMetrics.isEmpty,
            vitalMetrics: vitalMetrics
        )
    }
}

/// One fetch in the export. Each one succeeds or fails on its own.
nonisolated enum ExportMetric: Hashable, Sendable {
    case weight
    case steps
    case glucose
    case labResults
    case vital(VitalMetricComponent)

    /// The name used in a failure message.
    var plainName: String {
        switch self {
        case .weight: return "Weight"
        case .steps: return "Steps"
        case .glucose: return "Blood glucose"
        case .labResults: return "Lab results"
        case .vital(let component): return component.displayName
        }
    }

    /// The HealthKit type that holds this metric's samples.
    var objectType: HKObjectType? {
        switch self {
        case .weight: return HKQuantityType(.bodyMass)
        case .steps: return HKQuantityType(.stepCount)
        case .glucose: return HKQuantityType(.bloodGlucose)
        case .labResults: return HKObjectType.clinicalType(forIdentifier: .labResultRecord)
        case .vital(let component): return HKQuantityType(component.healthKitIdentifier)
        }
    }
}

/// A metric the user gave limited-history read access to (iOS 27), where the
/// access starts after the export's start date. Older samples are not in the file.
nonisolated struct ExportAccessLimit: Equatable, Sendable {
    let metric: ExportMetric
    let earliestDate: Date

    func message(dateStyle: Date.FormatStyle) -> String {
        "Health access for \(metric.plainName) starts on \(earliestDate.formatted(dateStyle)), "
            + "so older samples are not in the file."
    }
}

nonisolated struct ExportMetricFailure: Sendable {
    let metric: ExportMetric
    let error: any Error

    var message: String {
        "\(metric.plainName) could not be read: \(error.localizedDescription)"
    }
}

/// The samples that loaded, and the metrics that failed.
nonisolated struct ExportFetchResult: Sendable {
    var weightSamples: [HKQuantitySample]?
    var stepsSamples: [HKQuantitySample]?
    var glucoseSamples: [GlucoseSampleMgDl]?
    var labResults: [LabResultSample]?
    var vitalSamples: [VitalMetricComponent: [HKQuantitySample]] = [:]
    /// In display order.
    var failures: [ExportMetricFailure] = []
    /// In display order.
    var accessLimits: [ExportAccessLimit] = []
    var requestedMetricCount = 0

    /// The number of CSV rows: one per sample.
    var rowCount: Int {
        (weightSamples?.count ?? 0)
            + (stepsSamples?.count ?? 0)
            + (glucoseSamples?.count ?? 0)
            + (labResults?.count ?? 0)
            + vitalSamples.values.reduce(0) { $0 + $1.count }
    }

    var hasAnyData: Bool {
        ExportLogic.hasAnyData(
            weightSamples: weightSamples,
            stepsSamples: stepsSamples,
            glucoseSamples: glucoseSamples,
            labResults: labResults,
            vitalSamples: vitalSamples
        )
    }

    /// The error to show when no file can be exported, or nil when the export can go ahead.
    var blockingErrorMessage: String? {
        if hasAnyData {
            return nil
        }
        if failures.isEmpty {
            return ExportError.noDataFound.localizedDescription
        }
        if failures.count == requestedMetricCount {
            return firstFetchError?.localizedDescription
        }
        return "No file was exported.\n\n"
            + failureLines
            + "\n\nNo data found for the other selected metrics and date range."
    }

    /// The note to show before a partial export, or nil when every metric loaded.
    var partialFailureNotice: String? {
        guard hasAnyData, !failures.isEmpty else { return nil }
        return failureLines + "\n\nThe file will contain the other selected data."
    }

    /// The note to show before an export that limited-history access cut
    /// short, or nil when every selected metric has full access.
    func accessLimitNotice(
        dateStyle: Date.FormatStyle = Date.FormatStyle(date: .abbreviated, time: .omitted)
    ) -> String? {
        guard hasAnyData, !accessLimits.isEmpty else { return nil }
        return accessLimits.map { $0.message(dateStyle: dateStyle) }.joined(separator: "\n")
    }

    private var failureLines: String {
        failures.map(\.message).joined(separator: "\n")
    }

    /// The message shown when every metric failed, as before partial exports existed.
    private var firstFetchError: ExportError? {
        func error(for metric: ExportMetric) -> Error? {
            failures.first { $0.metric == metric }?.error
        }
        let vitalError = failures.first {
            if case .vital = $0.metric { return true }
            return false
        }?.error
        return ExportLogic.firstFetchError(
            weightError: error(for: .weight),
            stepsError: error(for: .steps),
            glucoseError: error(for: .glucose),
            labError: error(for: .labResults),
            vitalError: vitalError
        )
    }
}

/// Fetches the selected metrics in parallel. A failed metric does not discard the others.
nonisolated struct ExportDataLoader: Sendable {
    let store: any HealthDataStore

    private enum MetricData: Sendable {
        case quantity([HKQuantitySample])
        case glucose([GlucoseSampleMgDl])
        case labs([LabResultSample])
    }

    func requestAuthorization(for request: ExportRequest) async throws {
        try await store.requestReadAuthorization(for: request.readTypes)
    }

    @concurrent
    func load(_ request: ExportRequest) async -> ExportFetchResult {
        let metrics = request.metrics
        let limit: Int? = request.recordLimit > 0 ? request.recordLimit : nil
        async let pendingAccessLimits = accessLimits(for: request, metrics: metrics)

        let outcomes = await withTaskGroup(of: (ExportMetric, Result<MetricData, any Error>).self) { group in
            for metric in metrics {
                group.addTask {
                    (metric, await fetch(metric, request: request, limit: limit))
                }
            }
            var outcomes: [ExportMetric: Result<MetricData, any Error>] = [:]
            for await (metric, outcome) in group {
                outcomes[metric] = outcome
            }
            return outcomes
        }

        var result = ExportFetchResult(requestedMetricCount: metrics.count)
        for metric in metrics {
            switch outcomes[metric] {
            case .success(.quantity(let samples)):
                switch metric {
                case .weight: result.weightSamples = samples
                case .steps: result.stepsSamples = samples
                case .vital(let component): result.vitalSamples[component] = samples
                case .glucose, .labResults: break
                }
            case .success(.glucose(let samples)):
                result.glucoseSamples = samples
            case .success(.labs(let samples)):
                result.labResults = samples
            case .failure(let error):
                logger.error("Fetch failed for \(metric.plainName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                result.failures.append(ExportMetricFailure(metric: metric, error: error))
            case nil:
                break
            }
        }
        result.accessLimits = await pendingAccessLimits
        return result
    }

    /// The metrics whose limited-history access starts after the export's
    /// start. Every limit counts when the export has no start date ("All
    /// Records", "Last N Records"). A failed lookup reports no limits.
    private func accessLimits(for request: ExportRequest, metrics: [ExportMetric]) async -> [ExportAccessLimit] {
        let earliestDates: [HKObjectType: Date]
        do {
            earliestDates = try await store.earliestAuthorizedSampleDates(for: request.readTypes)
        } catch {
            logger.error("Earliest authorized dates failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
        guard !earliestDates.isEmpty else { return [] }

        let exportStart = request.dateRange.flatMap { HealthKitQueryHelpers.dayAlignedRange(from: $0)?.start }
        return metrics.compactMap { metric in
            guard let type = metric.objectType, let earliestDate = earliestDates[type] else { return nil }
            if let exportStart, earliestDate <= exportStart { return nil }
            return ExportAccessLimit(metric: metric, earliestDate: earliestDate)
        }
    }

    private func fetch(_ metric: ExportMetric, request: ExportRequest, limit: Int?) async -> Result<MetricData, any Error> {
        do {
            switch metric {
            case .weight:
                return .success(.quantity(try await store.quantitySamples(of: .bodyMass, dateRange: request.dateRange, limit: limit)))
            case .steps:
                return .success(.quantity(try await store.quantitySamples(of: .stepCount, dateRange: request.dateRange, limit: limit)))
            case .glucose:
                return .success(.glucose(try await fetchGlucose(dateRange: request.dateRange, limit: limit)))
            case .labResults:
                return .success(.labs(try await fetchLabResults(request)))
            case .vital(let component):
                return .success(.quantity(try await store.quantitySamples(
                    of: component.healthKitIdentifier,
                    dateRange: request.dateRange,
                    limit: limit
                )))
            }
        } catch {
            return .failure(error)
        }
    }

    /// Drops readings below 20 mg/dL before the record limit, so "Last N Records"
    /// gives N rows when N valid readings exist (#113). The query asks for a margin
    /// above the limit and doubles it while invalid readings leave the result short.
    private func fetchGlucose(dateRange: (startDate: Date, endDate: Date)?, limit: Int?) async throws -> [GlucoseSampleMgDl] {
        guard let limit else {
            let raw = try await store.quantitySamples(of: .bloodGlucose, dateRange: dateRange, limit: nil)
            return raw.compactMap(GlucoseSampleMgDl.init(from:))
        }

        var queryLimit = limit + max(limit / 10, 10)
        while true {
            let raw = try await store.quantitySamples(of: .bloodGlucose, dateRange: dateRange, limit: queryLimit)
            let valid = raw.compactMap(GlucoseSampleMgDl.init(from:))
            if valid.count >= limit || raw.count < queryLimit {
                logger.debug("Glucose: \(raw.count) raw samples, \(valid.count) valid, keeping \(min(valid.count, limit))")
                return Array(valid.prefix(limit))
            }
            queryLimit *= 2
        }
    }

    private func fetchLabResults(_ request: ExportRequest) async throws -> [LabResultSample] {
        let records = try await store.labResultRecords(dateRange: request.dateRange)
        let codeIndex = LabMetricRegistry.codeIndex(for: request.labMetrics)
        var samples = records.compactMap {
            LabResultSample(fromFHIRData: $0.fhirData, source: $0.sourceName, codeIndex: codeIndex)
        }
        if let dateRange = request.dateRange {
            samples = HealthKitQueryHelpers.filterLabResultsByDateRange(samples, dateRange: dateRange)
        }
        return HealthKitQueryHelpers.limitLabResultsPerMetric(samples, limit: request.recordLimit)
    }
}
