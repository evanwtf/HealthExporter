import HealthKit

/// Pure helpers extracted from HealthKitManager for testability.
nonisolated enum HealthKitQueryHelpers {
    /// The HealthKit types to request read access for: the selected metrics only.
    static func readTypes(
        includeWeight: Bool,
        includeSteps: Bool,
        includeGlucose: Bool,
        includeLabs: Bool,
        vitalMetrics: Set<VitalMetric> = []
    ) -> Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if includeWeight {
            types.insert(HKQuantityType(.bodyMass))
        }
        if includeSteps {
            types.insert(HKQuantityType(.stepCount))
        }
        if includeGlucose {
            types.insert(HKQuantityType(.bloodGlucose))
        }

        for component in vitalMetrics.flatMap(\.components) {
            types.insert(HKQuantityType(component.healthKitIdentifier))
        }

        if includeLabs,
           let clinicalType = HKObjectType.clinicalType(forIdentifier: .labResultRecord)
        {
            types.insert(clinicalType)
        }

        return types
    }

    /// Builds an inclusive start-of-day to end-of-day+1 date range, suitable for
    /// `HKQuery.predicateForSamples`. Returns nil if the calendar math fails.
    static func dayAlignedRange(
        from dateRange: (startDate: Date, endDate: Date),
        calendar: Calendar = .current
    ) -> (start: Date, end: Date)? {
        let startOfDay = calendar.startOfDay(for: dateRange.startDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dateRange.endDate)) else {
            return nil
        }
        return (startOfDay, endOfDay)
    }

    /// Builds a HealthKit sample predicate for the supplied date range.
    static func predicateForDateRange(
        _ dateRange: (startDate: Date, endDate: Date),
        calendar: Calendar = .current
    ) -> NSPredicate? {
        guard let aligned = dayAlignedRange(from: dateRange, calendar: calendar) else {
            return nil
        }
        return HKQuery.predicateForSamples(withStart: aligned.start, end: aligned.end, options: .strictStartDate)
    }

    /// Filters lab result samples by date range (start-of-day inclusive, end-of-day+1 exclusive).
    static func filterLabResultsByDateRange(
        _ samples: [LabResultSample],
        dateRange: (startDate: Date, endDate: Date),
        calendar: Calendar = .current
    ) -> [LabResultSample] {
        guard let aligned = dayAlignedRange(from: dateRange, calendar: calendar) else {
            return []
        }
        return samples.filter { $0.effectiveDateTime >= aligned.start && $0.effectiveDateTime < aligned.end }
    }

    /// Keeps the newest `limit` samples for each lab metric. Alternate LOINC
    /// codes count toward their metric. `limit <= 0` (`HKObjectQueryNoLimit`)
    /// keeps everything. Kept samples stay in input order.
    static func limitLabResultsPerMetric(_ samples: [LabResultSample], limit: Int) -> [LabResultSample] {
        guard limit > 0 else { return samples }

        let newestFirst = samples.indices.sorted { samples[$0].effectiveDateTime > samples[$1].effectiveDateTime }
        var countByMetric: [String: Int] = [:]
        var kept = Set<Int>()
        for index in newestFirst {
            let code = samples[index].loincCode
            let key = LabMetricRegistry.metric(forLoincCode: code)?.loincCode ?? code
            let count = countByMetric[key, default: 0]
            guard count < limit else { continue }
            countByMetric[key] = count + 1
            kept.insert(index)
        }
        return samples.indices.filter { kept.contains($0) }.map { samples[$0] }
    }

    /// Generates a contiguous set of daily weight samples for simulator testing.
    static func generateWeightTestSamples(
        days: Int = 60,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        valueGenerator: (Int) -> Double = { _ in Double.random(in: 80.0 ... 95.0) }
    ) -> [HKQuantitySample] {
        guard days > 0 else { return [] }

        let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let unit = HKUnit.gramUnit(with: .kilo)

        return (0 ..< days).compactMap { index in
            let offset = (days - 1) - index
            guard let date = calendar.date(byAdding: .day, value: -offset, to: referenceDate) else {
                return nil
            }

            let value = valueGenerator(index)
            return HKQuantitySample(
                type: weightType,
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: date,
                end: date
            )
        }
    }

    #if targetEnvironment(simulator)
        /// The sample types the simulator test-data generator needs permission to write.
        static func simulatorTestDataShareTypes() -> Set<HKSampleType> {
            let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
            return [weightType]
        }

        /// Formats a simulator mock-data failure for display in the Settings debug UI.
        static func simulatorTestDataFailureMessage(_ error: Error?) -> String {
            if let error {
                return "Failed to generate weight data: \(error.localizedDescription)"
            }
            return "Failed to generate weight data."
        }
    #endif
}

/// The app's one `HKHealthStore`, behind the `HealthDataStore` seam.
final nonisolated class HealthKitManager: HealthDataStore {
    static let shared = HealthKitManager()

    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func requestReadAuthorization(for types: Set<HKObjectType>) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "HealthKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "HealthKit is not available"])
        }
        try await healthStore.requestAuthorization(toShare: [], read: types)
    }

    func quantitySamples(
        of identifier: HKQuantityTypeIdentifier,
        dateRange: (startDate: Date, endDate: Date)?,
        limit: Int?
    ) async throws -> [HKQuantitySample] {
        var predicate: NSPredicate?
        if let dateRange {
            guard let rangePredicate = HealthKitQueryHelpers.predicateForDateRange(dateRange) else {
                return []
            }
            predicate = rangePredicate
        }

        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: limit
        )
        return try await descriptor.result(for: healthStore)
    }

    func labResultRecords(dateRange: (startDate: Date, endDate: Date)?) async throws -> [ClinicalRecordPayload] {
        guard let clinicalType = HKObjectType.clinicalType(forIdentifier: .labResultRecord) else {
            throw NSError(domain: "HealthKit", code: 3, userInfo: [NSLocalizedDescriptionKey: "Clinical Lab Result type not available"])
        }

        let predicate = dateRange.flatMap { HealthKitQueryHelpers.predicateForDateRange($0) }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.clinicalRecord(type: clinicalType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let records = try await descriptor.result(for: healthStore)
        return records.compactMap { record in
            guard let data = record.fhirResource?.data else { return nil }
            return ClinicalRecordPayload(fhirData: data, sourceName: record.sourceRevision.source.name)
        }
    }

    func earliestAuthorizedSampleDates(for types: Set<HKObjectType>) async throws -> [HKObjectType: Date] {
        guard #available(iOS 27, *) else { return [:] }
        return try await healthStore.earliestAuthorizedSampleDate(for: types)
    }

    #if targetEnvironment(simulator)
        func generateTestData() async throws {
            let samples = HealthKitQueryHelpers.generateWeightTestSamples(days: 60)
            let shareTypes = HealthKitQueryHelpers.simulatorTestDataShareTypes()
            try await healthStore.requestAuthorization(toShare: shareTypes, read: [])
            try await healthStore.save(samples)
        }
    #endif
}
