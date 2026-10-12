import Foundation
import Testing
@testable import HealthExporter

/// Tests for SettingsManager behavior by testing through UserDefaults directly.
/// Creating a second SettingsManager instance crashes in the test host environment
/// due to a Combine/@Published conflict with the app's @main StateObject, so we
/// test the read/write logic indirectly.
///
/// Swift Testing makes a new instance for each test, so `deinit` runs as the
/// teardown and removes every suite that the test made.
final class SettingsManagerTests {

    private var suiteNames: [String] = []

    deinit {
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "SettingsManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        suiteNames.append(suiteName)
        return defaults
    }

    // MARK: - Default value logic (mirrors SettingsManager.init)

    @Test func defaultTemperatureUnit_whenKeyMissing_isFahrenheit() {
        let defaults = makeDefaults()
        let raw = defaults.string(forKey: "temperatureUnit") ?? TemperatureUnit.fahrenheit.rawValue
        #expect(TemperatureUnit(rawValue: raw) == .fahrenheit)
    }

    @Test func defaultWeightUnit_whenKeyMissing_isPounds() {
        let defaults = makeDefaults()
        let raw = defaults.string(forKey: "weightUnit") ?? WeightUnit.pounds.rawValue
        #expect(WeightUnit(rawValue: raw) == .pounds)
    }

    @Test func defaultDateFormat_whenKeyMissing_isYYYYMMddHHmmss() {
        let defaults = makeDefaults()
        let raw = defaults.string(forKey: "dateFormat") ?? DateFormatOption.yyyyMMddHHmmss.rawValue
        #expect(DateFormatOption(rawValue: raw) == .yyyyMMddHHmmss)
    }

    @Test func defaultSortOrder_whenKeyMissing_isAscending() {
        let defaults = makeDefaults()
        let raw = defaults.string(forKey: "sortOrder") ?? SortOrder.ascending.rawValue
        #expect(SortOrder(rawValue: raw) == .ascending)
    }

    @Test func defaultAutoDismissSaveConfirmation_whenKeyMissing_isTrue() {
        let defaults = makeDefaults()
        let value = defaults.object(forKey: "autoDismissSaveConfirmation") as? Bool ?? true
        #expect(value)
    }

    @Test func defaultExportWeight_whenKeyMissing_isTrue() {
        let defaults = makeDefaults()
        let value = defaults.object(forKey: "exportWeight") as? Bool ?? true
        #expect(value)
    }

    @Test func defaultExportSteps_whenKeyMissing_isTrue() {
        let defaults = makeDefaults()
        let value = defaults.object(forKey: "exportSteps") as? Bool ?? true
        #expect(value)
    }

    @Test func defaultExportGlucose_whenKeyMissing_isFalse() {
        let defaults = makeDefaults()
        let value = defaults.object(forKey: "exportGlucose") as? Bool ?? false
        #expect(!value)
    }

    @Test func defaultLastXDaysValue_whenKeyMissing_is30() {
        let defaults = makeDefaults()
        let value = defaults.object(forKey: "lastXDaysValue") as? Int ?? 30
        #expect(value == 30)
    }

    @Test func defaultLastXRecordsValue_whenKeyMissing_is100() {
        let defaults = makeDefaults()
        let value = defaults.object(forKey: "lastXRecordsValue") as? Int ?? 100
        #expect(value == 100)
    }

    // MARK: - Reads persisted values

    @Test func readsPersistedEnumValues() {
        let defaults = makeDefaults()
        defaults.set(TemperatureUnit.celsius.rawValue, forKey: "temperatureUnit")
        defaults.set(WeightUnit.kilograms.rawValue, forKey: "weightUnit")
        defaults.set(DateFormatOption.iso8601.rawValue, forKey: "dateFormat")
        defaults.set(SortOrder.descending.rawValue, forKey: "sortOrder")

        #expect(TemperatureUnit(rawValue: defaults.string(forKey: "temperatureUnit")!) == .celsius)
        #expect(WeightUnit(rawValue: defaults.string(forKey: "weightUnit")!) == .kilograms)
        #expect(DateFormatOption(rawValue: defaults.string(forKey: "dateFormat")!) == .iso8601)
        #expect(SortOrder(rawValue: defaults.string(forKey: "sortOrder")!) == .descending)
    }

    @Test func readsPersistedBoolValues() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "autoDismissSaveConfirmation")
        defaults.set(false, forKey: "exportWeight")
        defaults.set(false, forKey: "exportSteps")
        defaults.set(true, forKey: "exportGlucose")

        #expect(!defaults.bool(forKey: "autoDismissSaveConfirmation"))
        #expect(!defaults.bool(forKey: "exportWeight"))
        #expect(!defaults.bool(forKey: "exportSteps"))
        #expect(defaults.bool(forKey: "exportGlucose"))
    }

    @Test func readsPersistedIntValues() {
        let defaults = makeDefaults()
        defaults.set(7, forKey: "lastXDaysValue")
        defaults.set(50, forKey: "lastXRecordsValue")

        #expect(defaults.integer(forKey: "lastXDaysValue") == 7)
        #expect(defaults.integer(forKey: "lastXRecordsValue") == 50)
    }

    // MARK: - Fallback for invalid raw values

    @Test func fallback_invalidTemperatureUnit() {
        let defaults = makeDefaults()
        defaults.set("invalid", forKey: "temperatureUnit")
        let raw = defaults.string(forKey: "temperatureUnit") ?? TemperatureUnit.fahrenheit.rawValue
        #expect((TemperatureUnit(rawValue: raw) ?? .fahrenheit) == .fahrenheit)
    }

    @Test func fallback_invalidWeightUnit() {
        let defaults = makeDefaults()
        defaults.set("invalid", forKey: "weightUnit")
        let raw = defaults.string(forKey: "weightUnit") ?? WeightUnit.pounds.rawValue
        #expect((WeightUnit(rawValue: raw) ?? .pounds) == .pounds)
    }

    @Test func fallback_invalidDateFormat() {
        let defaults = makeDefaults()
        defaults.set("invalid", forKey: "dateFormat")
        let raw = defaults.string(forKey: "dateFormat") ?? DateFormatOption.yyyyMMddHHmmss.rawValue
        #expect((DateFormatOption(rawValue: raw) ?? .yyyyMMddHHmmss) == .yyyyMMddHHmmss)
    }

    @Test func fallback_invalidSortOrder() {
        let defaults = makeDefaults()
        defaults.set("invalid", forKey: "sortOrder")
        let raw = defaults.string(forKey: "sortOrder") ?? SortOrder.ascending.rawValue
        #expect((SortOrder(rawValue: raw) ?? .ascending) == .ascending)
    }

    // MARK: - Lab panels and favorites

    @Test func defaultSelectedLabPanels_whenKeyMissing_isEmpty() {
        let defaults = makeDefaults()
        let raw = defaults.array(forKey: "selectedLabPanels") as? [String] ?? []
        #expect(raw.isEmpty)
    }

    @Test func defaultFavoriteLabCodes_whenKeyMissing_isEmpty() {
        let defaults = makeDefaults()
        let raw = defaults.array(forKey: "favoriteLabCodes") as? [String] ?? []
        #expect(raw.isEmpty)
    }

    @Test func defaultSelectedVitalMetrics_whenKeyMissing_isEmpty() {
        let defaults = makeDefaults()
        let raw = defaults.array(forKey: "selectedVitalMetrics") as? [String] ?? []
        #expect(raw.isEmpty)
    }

    @Test func readsPersistedSelectedLabPanels() {
        let defaults = makeDefaults()
        defaults.set([LabPanel.lipid.rawValue, LabPanel.thyroid.rawValue], forKey: "selectedLabPanels")
        let raw = defaults.array(forKey: "selectedLabPanels") as? [String] ?? []
        let panels = Set(raw.compactMap(LabPanel.init(rawValue:)))
        #expect(panels == [.lipid, .thyroid])
    }

    @Test func readsPersistedFavoriteLabCodes() {
        let defaults = makeDefaults()
        defaults.set(["4548-4", "2093-3"], forKey: "favoriteLabCodes")
        let codes = Set(defaults.array(forKey: "favoriteLabCodes") as? [String] ?? [])
        #expect(codes == ["4548-4", "2093-3"])
    }

    @Test func readsPersistedSelectedVitalMetrics() {
        let defaults = makeDefaults()
        defaults.set(
            [VitalMetric.bloodPressure.rawValue, VitalMetric.restingHeartRate.rawValue],
            forKey: "selectedVitalMetrics"
        )
        let raw = defaults.array(forKey: "selectedVitalMetrics") as? [String] ?? []
        let metrics = Set(raw.compactMap(VitalMetric.init(rawValue:)))
        #expect(metrics == [.bloodPressure, .restingHeartRate])
    }

    // MARK: - Legacy exportA1C migration

    @Test func migration_legacyExportA1CTrue_seedsFavorites() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "exportA1C")

        SettingsManager.migrateLegacyA1CSetting(in: defaults)

        let codes = Set(defaults.array(forKey: "favoriteLabCodes") as? [String] ?? [])
        #expect(codes == [LOINCCode.hemoglobinA1C])
    }

    @Test func migration_legacyExportA1CFalse_doesNotSeedFavorites() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "exportA1C")

        SettingsManager.migrateLegacyA1CSetting(in: defaults)

        #expect(defaults.object(forKey: "favoriteLabCodes") == nil)
    }

    @Test func migration_noLegacyKey_doesNotSeedFavorites() {
        let defaults = makeDefaults()

        SettingsManager.migrateLegacyA1CSetting(in: defaults)

        #expect(defaults.object(forKey: "favoriteLabCodes") == nil)
    }

    @Test func migration_doesNotOverrideExistingFavorites() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "exportA1C")
        defaults.set(["2093-3"], forKey: "favoriteLabCodes") // user already picked something

        SettingsManager.migrateLegacyA1CSetting(in: defaults)

        let codes = Set(defaults.array(forKey: "favoriteLabCodes") as? [String] ?? [])
        #expect(codes == ["2093-3"], "Migration must not clobber existing user choices")
    }
}
