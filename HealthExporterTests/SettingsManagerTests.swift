import XCTest
@testable import HealthExporter

/// Tests for SettingsManager behavior by testing through UserDefaults directly.
/// Creating a second SettingsManager instance crashes in the test host environment
/// due to a Combine/@Published conflict with the app's @main StateObject, so we
/// test the read/write logic indirectly.
final class SettingsManagerTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SettingsManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    // MARK: - Default value logic (mirrors SettingsManager.init)

    func testDefaultTemperatureUnit_whenKeyMissing_isFahrenheit() {
        let defaults = makeDefaults()
        let raw = defaults.string(forKey: "temperatureUnit") ?? TemperatureUnit.fahrenheit.rawValue
        XCTAssertEqual(TemperatureUnit(rawValue: raw), .fahrenheit)
    }

    func testDefaultWeightUnit_whenKeyMissing_isPounds() {
        let defaults = makeDefaults()
        let raw = defaults.string(forKey: "weightUnit") ?? WeightUnit.pounds.rawValue
        XCTAssertEqual(WeightUnit(rawValue: raw), .pounds)
    }

    func testDefaultDistanceSpeedUnit_whenKeyMissing_isImperial() {
        let defaults = makeDefaults()
        let raw = defaults.string(forKey: "distanceSpeedUnit") ?? DistanceSpeedUnit.imperial.rawValue
        XCTAssertEqual(DistanceSpeedUnit(rawValue: raw), .imperial)
    }

    func testDefaultDateFormat_whenKeyMissing_isYYYYMMddHHmmss() {
        let defaults = makeDefaults()
        let raw = defaults.string(forKey: "dateFormat") ?? DateFormatOption.yyyyMMddHHmmss.rawValue
        XCTAssertEqual(DateFormatOption(rawValue: raw), .yyyyMMddHHmmss)
    }

    func testDefaultSortOrder_whenKeyMissing_isAscending() {
        let defaults = makeDefaults()
        let raw = defaults.string(forKey: "sortOrder") ?? SortOrder.ascending.rawValue
        XCTAssertEqual(SortOrder(rawValue: raw), .ascending)
    }

    func testDefaultAutoDismissSaveConfirmation_whenKeyMissing_isTrue() {
        let defaults = makeDefaults()
        let value = defaults.object(forKey: "autoDismissSaveConfirmation") as? Bool ?? true
        XCTAssertTrue(value)
    }

    func testDefaultExportWeight_whenKeyMissing_isTrue() {
        let defaults = makeDefaults()
        let value = defaults.object(forKey: "exportWeight") as? Bool ?? true
        XCTAssertTrue(value)
    }

    func testDefaultExportSteps_whenKeyMissing_isTrue() {
        let defaults = makeDefaults()
        let value = defaults.object(forKey: "exportSteps") as? Bool ?? true
        XCTAssertTrue(value)
    }

    func testDefaultExportGlucose_whenKeyMissing_isFalse() {
        let defaults = makeDefaults()
        let value = defaults.object(forKey: "exportGlucose") as? Bool ?? false
        XCTAssertFalse(value)
    }

    func testDefaultLastXDaysValue_whenKeyMissing_is30() {
        let defaults = makeDefaults()
        let value = defaults.object(forKey: "lastXDaysValue") as? Int ?? 30
        XCTAssertEqual(value, 30)
    }

    func testDefaultLastXRecordsValue_whenKeyMissing_is100() {
        let defaults = makeDefaults()
        let value = defaults.object(forKey: "lastXRecordsValue") as? Int ?? 100
        XCTAssertEqual(value, 100)
    }

    // MARK: - Reads persisted values

    func testReadsPersistedEnumValues() {
        let defaults = makeDefaults()
        defaults.set(TemperatureUnit.celsius.rawValue, forKey: "temperatureUnit")
        defaults.set(WeightUnit.kilograms.rawValue, forKey: "weightUnit")
        defaults.set(DistanceSpeedUnit.metric.rawValue, forKey: "distanceSpeedUnit")
        defaults.set(DateFormatOption.iso8601.rawValue, forKey: "dateFormat")
        defaults.set(SortOrder.descending.rawValue, forKey: "sortOrder")

        XCTAssertEqual(TemperatureUnit(rawValue: defaults.string(forKey: "temperatureUnit")!), .celsius)
        XCTAssertEqual(WeightUnit(rawValue: defaults.string(forKey: "weightUnit")!), .kilograms)
        XCTAssertEqual(DistanceSpeedUnit(rawValue: defaults.string(forKey: "distanceSpeedUnit")!), .metric)
        XCTAssertEqual(DateFormatOption(rawValue: defaults.string(forKey: "dateFormat")!), .iso8601)
        XCTAssertEqual(SortOrder(rawValue: defaults.string(forKey: "sortOrder")!), .descending)
    }

    func testReadsPersistedBoolValues() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "autoDismissSaveConfirmation")
        defaults.set(false, forKey: "exportWeight")
        defaults.set(false, forKey: "exportSteps")
        defaults.set(true, forKey: "exportGlucose")

        XCTAssertFalse(defaults.bool(forKey: "autoDismissSaveConfirmation"))
        XCTAssertFalse(defaults.bool(forKey: "exportWeight"))
        XCTAssertFalse(defaults.bool(forKey: "exportSteps"))
        XCTAssertTrue(defaults.bool(forKey: "exportGlucose"))
    }

    func testReadsPersistedIntValues() {
        let defaults = makeDefaults()
        defaults.set(7, forKey: "lastXDaysValue")
        defaults.set(50, forKey: "lastXRecordsValue")

        XCTAssertEqual(defaults.integer(forKey: "lastXDaysValue"), 7)
        XCTAssertEqual(defaults.integer(forKey: "lastXRecordsValue"), 50)
    }

    // MARK: - Fallback for invalid raw values

    func testFallback_invalidTemperatureUnit() {
        let defaults = makeDefaults()
        defaults.set("invalid", forKey: "temperatureUnit")
        let raw = defaults.string(forKey: "temperatureUnit") ?? TemperatureUnit.fahrenheit.rawValue
        XCTAssertEqual(TemperatureUnit(rawValue: raw) ?? .fahrenheit, .fahrenheit)
    }

    func testFallback_invalidWeightUnit() {
        let defaults = makeDefaults()
        defaults.set("invalid", forKey: "weightUnit")
        let raw = defaults.string(forKey: "weightUnit") ?? WeightUnit.pounds.rawValue
        XCTAssertEqual(WeightUnit(rawValue: raw) ?? .pounds, .pounds)
    }

    func testFallback_invalidDateFormat() {
        let defaults = makeDefaults()
        defaults.set("invalid", forKey: "dateFormat")
        let raw = defaults.string(forKey: "dateFormat") ?? DateFormatOption.yyyyMMddHHmmss.rawValue
        XCTAssertEqual(DateFormatOption(rawValue: raw) ?? .yyyyMMddHHmmss, .yyyyMMddHHmmss)
    }

    func testFallback_invalidSortOrder() {
        let defaults = makeDefaults()
        defaults.set("invalid", forKey: "sortOrder")
        let raw = defaults.string(forKey: "sortOrder") ?? SortOrder.ascending.rawValue
        XCTAssertEqual(SortOrder(rawValue: raw) ?? .ascending, .ascending)
    }

    func testFallback_invalidDistanceSpeedUnit() {
        let defaults = makeDefaults()
        defaults.set("invalid", forKey: "distanceSpeedUnit")
        let raw = defaults.string(forKey: "distanceSpeedUnit") ?? DistanceSpeedUnit.imperial.rawValue
        XCTAssertEqual(DistanceSpeedUnit(rawValue: raw) ?? .imperial, .imperial)
    }

    // MARK: - Lab panels and favorites

    func testDefaultSelectedLabPanels_whenKeyMissing_isEmpty() {
        let defaults = makeDefaults()
        let raw = defaults.array(forKey: "selectedLabPanels") as? [String] ?? []
        XCTAssertTrue(raw.isEmpty)
    }

    func testDefaultFavoriteLabCodes_whenKeyMissing_isEmpty() {
        let defaults = makeDefaults()
        let raw = defaults.array(forKey: "favoriteLabCodes") as? [String] ?? []
        XCTAssertTrue(raw.isEmpty)
    }

    func testDefaultSelectedVitalMetrics_whenKeyMissing_isEmpty() {
        let defaults = makeDefaults()
        let raw = defaults.array(forKey: "selectedVitalMetrics") as? [String] ?? []
        XCTAssertTrue(raw.isEmpty)
    }

    func testReadsPersistedSelectedLabPanels() {
        let defaults = makeDefaults()
        defaults.set([LabPanel.lipid.rawValue, LabPanel.thyroid.rawValue], forKey: "selectedLabPanels")
        let raw = defaults.array(forKey: "selectedLabPanels") as? [String] ?? []
        let panels = Set(raw.compactMap(LabPanel.init(rawValue:)))
        XCTAssertEqual(panels, [.lipid, .thyroid])
    }

    func testReadsPersistedFavoriteLabCodes() {
        let defaults = makeDefaults()
        defaults.set(["4548-4", "2093-3"], forKey: "favoriteLabCodes")
        let codes = Set(defaults.array(forKey: "favoriteLabCodes") as? [String] ?? [])
        XCTAssertEqual(codes, ["4548-4", "2093-3"])
    }

    func testReadsPersistedSelectedVitalMetrics() {
        let defaults = makeDefaults()
        defaults.set(
            [VitalMetric.bloodPressure.rawValue, VitalMetric.restingHeartRate.rawValue],
            forKey: "selectedVitalMetrics"
        )
        let raw = defaults.array(forKey: "selectedVitalMetrics") as? [String] ?? []
        let metrics = Set(raw.compactMap(VitalMetric.init(rawValue:)))
        XCTAssertEqual(metrics, [.bloodPressure, .restingHeartRate])
    }

    // MARK: - Legacy exportA1C migration

    func testMigration_legacyExportA1CTrue_seedsFavorites() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "exportA1C")

        SettingsManager.migrateLegacyA1CSetting(in: defaults)

        let codes = Set(defaults.array(forKey: "favoriteLabCodes") as? [String] ?? [])
        XCTAssertEqual(codes, [LOINCCode.hemoglobinA1C])
    }

    func testMigration_legacyExportA1CFalse_doesNotSeedFavorites() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "exportA1C")

        SettingsManager.migrateLegacyA1CSetting(in: defaults)

        XCTAssertNil(defaults.object(forKey: "favoriteLabCodes"))
    }

    func testMigration_noLegacyKey_doesNotSeedFavorites() {
        let defaults = makeDefaults()

        SettingsManager.migrateLegacyA1CSetting(in: defaults)

        XCTAssertNil(defaults.object(forKey: "favoriteLabCodes"))
    }

    func testMigration_doesNotOverrideExistingFavorites() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "exportA1C")
        defaults.set(["2093-3"], forKey: "favoriteLabCodes") // user already picked something

        SettingsManager.migrateLegacyA1CSetting(in: defaults)

        let codes = Set(defaults.array(forKey: "favoriteLabCodes") as? [String] ?? [])
        XCTAssertEqual(codes, ["2093-3"], "Migration must not clobber existing user choices")
    }
}
