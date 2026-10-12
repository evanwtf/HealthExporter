import Foundation
@testable import HealthExporter
import HealthKit
import Synchronization
import Testing

/// A store that serves canned samples and can fail one metric.
/// It honors `limit` and returns samples newest first, as HealthKit does.
private final nonisolated class FakeHealthDataStore: HealthDataStore {
    struct QuantityCall: Equatable {
        let identifier: HKQuantityTypeIdentifier
        let limit: Int?
    }

    private let quantityResults: [HKQuantityTypeIdentifier: Result<[HKQuantitySample], any Error>]
    private let labResult: Result<[ClinicalRecordPayload], any Error>
    private let earliestDates: Result<[HKObjectType: Date], any Error>
    private let state = Mutex<(types: Set<HKObjectType>?, calls: [QuantityCall])>((nil, []))

    init(
        quantity: [HKQuantityTypeIdentifier: Result<[HKQuantitySample], any Error>] = [:],
        labs: Result<[ClinicalRecordPayload], any Error> = .success([]),
        earliestDates: Result<[HKObjectType: Date], any Error> = .success([:])
    ) {
        quantityResults = quantity
        labResult = labs
        self.earliestDates = earliestDates
    }

    var requestedTypes: Set<HKObjectType>? {
        state.withLock { $0.types }
    }

    var quantityCalls: [QuantityCall] {
        state.withLock { $0.calls }
    }

    func requestReadAuthorization(for types: Set<HKObjectType>) async throws {
        state.withLock { $0.types = types }
    }

    func quantitySamples(
        of identifier: HKQuantityTypeIdentifier,
        dateRange _: (startDate: Date, endDate: Date)?,
        limit: Int?
    ) async throws -> [HKQuantitySample] {
        state.withLock { $0.calls.append(QuantityCall(identifier: identifier, limit: limit)) }
        let samples = try (quantityResults[identifier] ?? .success([])).get()
        let newestFirst = samples.sorted { $0.startDate > $1.startDate }
        guard let limit else { return newestFirst }
        return Array(newestFirst.prefix(limit))
    }

    func labResultRecords(dateRange _: (startDate: Date, endDate: Date)?) async throws -> [ClinicalRecordPayload] {
        try labResult.get()
    }

    func earliestAuthorizedSampleDates(for types: Set<HKObjectType>) async throws -> [HKObjectType: Date] {
        try earliestDates.get().filter { types.contains($0.key) }
    }
}

nonisolated struct ExportDataLoaderTests {
    private let referenceDate = Date(timeIntervalSince1970: 1_750_000_000)
    private let mgDl = HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))

    private func quantitySamples(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        values: [Double]
    ) -> [HKQuantitySample] {
        let type = HKQuantityType(identifier)
        // values[0] is the newest sample; each next one is one minute older.
        return values.enumerated().map { index, value in
            let date = referenceDate.addingTimeInterval(TimeInterval(-60 * index))
            return HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value), start: date, end: date)
        }
    }

    private func weightSamples(_ count: Int) -> [HKQuantitySample] {
        quantitySamples(.bodyMass, unit: .gramUnit(with: .kilo), values: (0 ..< count).map { 80 + Double($0) })
    }

    private func stepsSamples(_ count: Int) -> [HKQuantitySample] {
        quantitySamples(.stepCount, unit: .count(), values: (0 ..< count).map { 1000 + Double($0) })
    }

    private func a1cRecord(value: Double, date: String) -> ClinicalRecordPayload {
        let json = """
        {"resourceType":"Observation",
         "code":{"coding":[{"system":"http://loinc.org","code":"\(LOINCCode.hemoglobinA1C)"}]},
         "effectiveDateTime":"\(date)",
         "valueQuantity":{"value":\(value),"unit":"%"}}
        """
        return ClinicalRecordPayload(fhirData: Data(json.utf8), sourceName: "Clinic")
    }

    private func request(
        weight: Bool = false,
        steps: Bool = false,
        glucose: Bool = false,
        labs: [LabMetric] = [],
        vitals: Set<VitalMetric> = [],
        dateRange: (startDate: Date, endDate: Date)? = nil,
        limit: Int = HKObjectQueryNoLimit
    ) -> ExportRequest {
        ExportRequest(
            includeWeight: weight,
            includeSteps: steps,
            includeGlucose: glucose,
            labMetrics: labs,
            vitalMetrics: vitals,
            dateRange: dateRange,
            recordLimit: limit
        )
    }

    private var a1c: LabMetric {
        get throws {
            try #require(LabMetricRegistry.metric(forLoincCode: LOINCCode.hemoglobinA1C))
        }
    }

    private let labsUnavailable = NSError(domain: "HealthKit", code: 3, userInfo: [
        NSLocalizedDescriptionKey: "Clinical Lab Result type not available",
    ])

    // MARK: - #112: one failed metric does not discard the others

    @Test func load_labFailure_keepsWeightAndSteps() async throws {
        let store = FakeHealthDataStore(
            quantity: [.bodyMass: .success(weightSamples(2)), .stepCount: .success(stepsSamples(3))],
            labs: .failure(labsUnavailable)
        )

        let result = try await ExportDataLoader(store: store).load(request(weight: true, steps: true, labs: [a1c]))

        #expect(result.weightSamples?.count == 2)
        #expect(result.stepsSamples?.count == 3)
        #expect(result.labResults == nil)
        #expect(result.failures.map(\.metric) == [.labResults])
        #expect(result.hasAnyData)
        #expect(result.blockingErrorMessage == nil)
    }

    @Test func load_labFailure_reportsTheFailureInPlainWords() async throws {
        let store = FakeHealthDataStore(
            quantity: [.bodyMass: .success(weightSamples(2))],
            labs: .failure(labsUnavailable)
        )

        let result = try await ExportDataLoader(store: store).load(request(weight: true, labs: [a1c]))

        #expect(result.partialFailureNotice == ("Lab results could not be read: Clinical Lab Result type not available\n\n"
                + "The file will contain the other selected data."))
    }

    @Test func load_labFailure_csvMatchesTheLoadedSamples() async throws {
        let weight = weightSamples(4)
        let steps = stepsSamples(5)
        let store = FakeHealthDataStore(
            quantity: [.bodyMass: .success(weight), .stepCount: .success(steps)],
            labs: .failure(labsUnavailable)
        )

        var result = try await ExportDataLoader(store: store).load(request(weight: true, steps: true, labs: [a1c]))

        var expectedWeight: [HKQuantitySample]? = weight
        var expectedSteps: [HKQuantitySample]? = steps
        var noGlucose: [GlucoseSampleMgDl]?
        var noLabs: [LabResultSample]?
        var noVitals: [VitalMetricComponent: [HKQuantitySample]] = [:]
        let expected = CSVGenerator.generateCombinedCSV(
            weightSamples: &expectedWeight,
            stepsSamples: &expectedSteps,
            glucoseSamples: &noGlucose,
            labResults: &noLabs,
            vitalSamples: &noVitals,
            weightUnit: .kilograms,
            dateFormat: .yyyyMMddHHmmss,
            sortOrder: .ascending
        )
        let actual = CSVGenerator.generateCombinedCSV(
            weightSamples: &result.weightSamples,
            stepsSamples: &result.stepsSamples,
            glucoseSamples: &result.glucoseSamples,
            labResults: &result.labResults,
            vitalSamples: &result.vitalSamples,
            weightUnit: .kilograms,
            dateFormat: .yyyyMMddHHmmss,
            sortOrder: .ascending
        )

        #expect(actual == expected)
        #expect((actual.components(separatedBy: "\n").filter { $0.contains(",Weight,") }.count) == 4)
        #expect((actual.components(separatedBy: "\n").filter { $0.contains(",Steps,") }.count) == 5)
    }

    @Test func load_oneVitalFails_otherVitalStillLoads() async {
        let failure = NSError(domain: "HealthKit", code: 5, userInfo: [NSLocalizedDescriptionKey: "denied"])
        let store = FakeHealthDataStore(quantity: [
            .restingHeartRate: .failure(failure),
            .respiratoryRate: .success(quantitySamples(.respiratoryRate, unit: .count().unitDivided(by: .minute()), values: [14, 15])),
        ])

        let result = await ExportDataLoader(store: store).load(request(vitals: [.restingHeartRate, .respiratoryRate]))

        #expect(result.vitalSamples[.respiratoryRate]?.count == 2)
        #expect(result.failures.map(\.metric) == [.vital(.restingHeartRate)])
        #expect(result.partialFailureNotice == "Resting Heart Rate could not be read: denied\n\nThe file will contain the other selected data.")
        #expect(result.blockingErrorMessage == nil)
    }

    @Test func load_everyMetricFails_showsTheFirstErrorAsBefore() async throws {
        let weightFailure = NSError(domain: "HealthKit", code: 6, userInfo: [NSLocalizedDescriptionKey: "Weight failed"])
        let store = FakeHealthDataStore(
            quantity: [.bodyMass: .failure(weightFailure)],
            labs: .failure(labsUnavailable)
        )

        let result = try await ExportDataLoader(store: store).load(request(weight: true, labs: [a1c]))

        #expect(result.failures.map(\.metric) == [.weight, .labResults])
        #expect(result.blockingErrorMessage == "Failed to fetch Weight data: Weight failed")
        #expect(result.partialFailureNotice == nil)
    }

    @Test func load_failureAndNoOtherData_saysNoFileWasExported() async throws {
        let store = FakeHealthDataStore(
            quantity: [.bodyMass: .success([])],
            labs: .failure(labsUnavailable)
        )

        let result = try await ExportDataLoader(store: store).load(request(weight: true, labs: [a1c]))

        #expect(result.blockingErrorMessage == ("No file was exported.\n\n"
                + "Lab results could not be read: Clinical Lab Result type not available\n\n"
                + "No data found for the other selected metrics and date range."))
    }

    @Test func load_noFailuresAndNoData_reportsNoDataFound() async {
        let store = FakeHealthDataStore(quantity: [.bodyMass: .success([])])

        let result = await ExportDataLoader(store: store).load(request(weight: true))

        #expect(result.failures.isEmpty)
        #expect(result.blockingErrorMessage == ExportError.noDataFound.localizedDescription)
    }

    @Test func load_labsLoad_parsesAndKeepsNewestPerLab() async throws {
        let store = FakeHealthDataStore(labs: .success([
            a1cRecord(value: 6.1, date: "2024-06-15T10:00:00Z"),
            a1cRecord(value: 5.9, date: "2024-03-15T10:00:00Z"),
            a1cRecord(value: 5.7, date: "2023-12-15T10:00:00Z"),
        ]))

        let result = try await ExportDataLoader(store: store).load(request(labs: [a1c], limit: 2))

        #expect(result.labResults?.map(\.value) == [6.1, 5.9])
        #expect(result.labResults?.first?.source == "Clinic")
        #expect(result.failures.isEmpty)
    }

    @Test func load_unselectedMetricsAreNotQueried() async {
        let store = FakeHealthDataStore(quantity: [.bodyMass: .success(weightSamples(1))])

        _ = await ExportDataLoader(store: store).load(request(weight: true, limit: 7))

        #expect(store.quantityCalls == [.init(identifier: .bodyMass, limit: 7)])
    }

    // MARK: - #113: glucose filter before the record limit

    @Test func load_glucoseLastRecords_filtersBeforeTheLimit() async {
        // 103 readings, newest first. Three of the newest 100 are below 20 mg/dL.
        var values = (0 ..< 103).map { 100 + Double($0 % 50) }
        for invalidIndex in [1, 50, 99] {
            values[invalidIndex] = 5
        }
        let samples = quantitySamples(.bloodGlucose, unit: mgDl, values: values)
        let store = FakeHealthDataStore(quantity: [.bloodGlucose: .success(samples)])

        let result = await ExportDataLoader(store: store).load(request(glucose: true, limit: 100))

        let glucose = result.glucoseSamples ?? []
        #expect(glucose.count == 100)
        #expect(glucose.allSatisfy { $0.value >= 20 })
        let expectedDates = samples.enumerated()
            .filter { ![1, 50, 99].contains($0.offset) }
            .map(\.element.startDate)
        #expect(glucose.map(\.startDate) == expectedDates)
    }

    @Test func load_glucoseLastRecords_longInvalidRun_keepsQueryingUntilFull() async {
        // The 30 newest readings are invalid; the limit is 10.
        let values = Array(repeating: 5.0, count: 30) + (0 ..< 40).map { 120 + Double($0) }
        let samples = quantitySamples(.bloodGlucose, unit: mgDl, values: values)
        let store = FakeHealthDataStore(quantity: [.bloodGlucose: .success(samples)])

        let result = await ExportDataLoader(store: store).load(request(glucose: true, limit: 10))

        #expect(result.glucoseSamples?.map(\.value) == ((0 ..< 10).map { 120 + Double($0) }))
    }

    @Test func load_glucoseLastRecords_fewerValidThanLimit_returnsAllValid() async {
        let values = (0 ..< 30).map { $0 % 6 == 0 ? 10.0 : 110.0 }
        let samples = quantitySamples(.bloodGlucose, unit: mgDl, values: values)
        let store = FakeHealthDataStore(quantity: [.bloodGlucose: .success(samples)])

        let result = await ExportDataLoader(store: store).load(request(glucose: true, limit: 100))

        #expect(result.glucoseSamples?.count == 25)
    }

    @Test func load_glucoseNoLimit_dropsInvalidReadings() async {
        let samples = quantitySamples(.bloodGlucose, unit: mgDl, values: [110, 4, 95, 19.9, 20])
        let store = FakeHealthDataStore(quantity: [.bloodGlucose: .success(samples)])

        let result = await ExportDataLoader(store: store).load(request(glucose: true))

        #expect(result.glucoseSamples?.map(\.value) == [110, 95, 20])
        #expect(store.quantityCalls == [.init(identifier: .bloodGlucose, limit: nil)])
    }

    // MARK: - #119 WP12: limited-history read access (iOS 27)

    /// A fixed style, so the expected text does not depend on the test machine.
    private let dateStyle = Date.FormatStyle(
        date: .abbreviated,
        time: .omitted,
        locale: Locale(identifier: "en_US"),
        timeZone: .gmt
    )

    /// 2026-03-03T12:00:00Z.
    private let march3 = Date(timeIntervalSince1970: 1_772_539_200)
    /// 2026-01-01T12:00:00Z to 2026-06-01T12:00:00Z.
    private let januaryToJune = (
        startDate: Date(timeIntervalSince1970: 1_767_268_800),
        endDate: Date(timeIntervalSince1970: 1_780_315_200)
    )

    @Test func load_fullAccess_addsNoAccessLine() async {
        let store = FakeHealthDataStore(quantity: [.bodyMass: .success(weightSamples(2))])

        let result = await ExportDataLoader(store: store).load(request(weight: true, dateRange: januaryToJune))

        #expect(result.accessLimits.isEmpty)
        #expect(result.accessLimitNotice(dateStyle: dateStyle) == nil)
    }

    @Test func load_accessStartsAfterTheExportStart_addsALineWithTheDate() async {
        let store = FakeHealthDataStore(
            quantity: [.bodyMass: .success(weightSamples(2)), .stepCount: .success(stepsSamples(2))],
            earliestDates: .success([HKQuantityType(.bodyMass): march3])
        )

        let result = await ExportDataLoader(store: store).load(request(weight: true, steps: true, dateRange: januaryToJune))

        #expect(result.accessLimits == [ExportAccessLimit(metric: .weight, earliestDate: march3)])
        #expect(result.accessLimitNotice(dateStyle: dateStyle)
            == "Health access for Weight starts on Mar 3, 2026, so older samples are not in the file.")
        #expect(result.partialFailureNotice == nil)
    }

    @Test func load_accessStartsBeforeTheExportStart_addsNoAccessLine() async {
        let december = Date(timeIntervalSince1970: 1_764_590_400) // 2025-12-01T12:00:00Z
        let store = FakeHealthDataStore(
            quantity: [.bodyMass: .success(weightSamples(2))],
            earliestDates: .success([HKQuantityType(.bodyMass): december])
        )

        let result = await ExportDataLoader(store: store).load(request(weight: true, dateRange: januaryToJune))

        #expect(result.accessLimits.isEmpty)
        #expect(result.accessLimitNotice(dateStyle: dateStyle) == nil)
    }

    @Test func load_allRecordsWithALimit_addsALinePerLimitedMetric() async {
        let store = FakeHealthDataStore(
            quantity: [
                .bodyMass: .success(weightSamples(2)),
                .restingHeartRate: .success(quantitySamples(.restingHeartRate, unit: .count().unitDivided(by: .minute()), values: [60])),
            ],
            earliestDates: .success([
                HKQuantityType(.bodyMass): march3,
                HKQuantityType(.restingHeartRate): march3,
            ])
        )

        let result = await ExportDataLoader(store: store).load(request(weight: true, vitals: [.restingHeartRate]))

        #expect(result.accessLimits.map(\.metric) == [.weight, .vital(.restingHeartRate)])
        #expect(result.accessLimitNotice(dateStyle: dateStyle) == (
            "Health access for Weight starts on Mar 3, 2026, so older samples are not in the file.\n"
                + "Health access for Resting Heart Rate starts on Mar 3, 2026, so older samples are not in the file."
        ))
    }

    @Test func load_accessLookupFails_exportsWithNoAccessLine() async {
        let failure = NSError(domain: "HealthKit", code: 7, userInfo: [NSLocalizedDescriptionKey: "lookup failed"])
        let store = FakeHealthDataStore(
            quantity: [.bodyMass: .success(weightSamples(2))],
            earliestDates: .failure(failure)
        )

        let result = await ExportDataLoader(store: store).load(request(weight: true))

        #expect(result.weightSamples?.count == 2)
        #expect(result.failures.isEmpty)
        #expect(result.accessLimitNotice(dateStyle: dateStyle) == nil)
    }

    // MARK: - #114: request read access for the selected metrics only

    @Test func requestAuthorization_vitalsOnly_doesNotAskForWeightStepsOrGlucose() async throws {
        let store = FakeHealthDataStore()

        try await ExportDataLoader(store: store).requestAuthorization(for: request(vitals: [.restingHeartRate]))

        #expect(store.requestedTypes == [HKQuantityType(.restingHeartRate)])
    }

    @Test func requestAuthorization_glucoseAndLabs_asksForThoseOnly() async throws {
        let store = FakeHealthDataStore()

        try await ExportDataLoader(store: store).requestAuthorization(for: request(glucose: true, labs: [a1c]))

        var expected: Set<HKObjectType> = [HKQuantityType(.bloodGlucose)]
        if let clinical = HKObjectType.clinicalType(forIdentifier: .labResultRecord) {
            expected.insert(clinical)
        }
        #expect(store.requestedTypes == expected)
    }
}
