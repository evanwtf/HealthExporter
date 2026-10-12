import Foundation
import Testing
@testable import HealthExporter

/// Tests the real `SettingsManager` against a `UserDefaults` suite of its own.
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

    // MARK: - Defaults when no key is set

    @Test func emptySuite_loadsTheDefaults() {
        let settings = SettingsManager(defaults: makeDefaults())

        #expect(settings.temperatureUnit == .fahrenheit)
        #expect(settings.weightUnit == .pounds)
        #expect(settings.dateFormat == .yyyyMMddHHmmss)
        #expect(settings.sortOrder == .ascending)
        #expect(settings.autoDismissSaveConfirmation)
        #expect(settings.exportWeight)
        #expect(settings.exportSteps)
        #expect(!settings.exportGlucose)
        #expect(settings.selectedLabPanels.isEmpty)
        #expect(settings.favoriteLabCodes.isEmpty)
        #expect(settings.selectedVitalMetrics.isEmpty)
        #expect(settings.expandedLabPanels.isEmpty)
        #expect(!settings.expandedVitalsSection)
        #expect(settings.lastXDaysValue == 30)
        #expect(settings.lastXRecordsValue == 100)
    }

    @Test func loading_writesNothingToTheSuite() {
        let defaults = makeDefaults()

        _ = SettingsManager(defaults: defaults)

        for key in Self.persistedKeys {
            #expect(defaults.object(forKey: key) == nil, "\(key)")
        }
    }

    // MARK: - Existing users keep their settings

    /// Every key, written in the format that v2.5.0 and earlier wrote.
    private static let persistedKeys = [
        "temperatureUnit", "weightUnit", "dateFormat", "sortOrder",
        "autoDismissSaveConfirmation", "exportWeight", "exportSteps", "exportGlucose",
        "selectedLabPanels", "favoriteLabCodes", "selectedVitalMetrics",
        "expandedLabPanels", "expandedVitalsSection", "lastXDaysValue", "lastXRecordsValue",
    ]

    private func writeV250Settings(to defaults: UserDefaults) {
        defaults.set("Celsius (°C)", forKey: "temperatureUnit")
        defaults.set("Kilograms (kg)", forKey: "weightUnit")
        defaults.set("ISO8601", forKey: "dateFormat")
        defaults.set("Newest → Oldest", forKey: "sortOrder")
        defaults.set(false, forKey: "autoDismissSaveConfirmation")
        defaults.set(false, forKey: "exportWeight")
        defaults.set(false, forKey: "exportSteps")
        defaults.set(true, forKey: "exportGlucose")
        defaults.set(["lipid", "thyroid"], forKey: "selectedLabPanels")
        defaults.set(["4548-4", "2093-3"], forKey: "favoriteLabCodes")
        defaults.set(["bloodPressure", "restingHeartRate"], forKey: "selectedVitalMetrics")
        defaults.set(["cbc"], forKey: "expandedLabPanels")
        defaults.set(true, forKey: "expandedVitalsSection")
        defaults.set(7, forKey: "lastXDaysValue")
        defaults.set(2_000, forKey: "lastXRecordsValue")
    }

    @Test func suiteWrittenByV250_loadsUnchanged() {
        let defaults = makeDefaults()
        writeV250Settings(to: defaults)

        let settings = SettingsManager(defaults: defaults)

        #expect(settings.temperatureUnit == .celsius)
        #expect(settings.weightUnit == .kilograms)
        #expect(settings.dateFormat == .iso8601)
        #expect(settings.sortOrder == .descending)
        #expect(!settings.autoDismissSaveConfirmation)
        #expect(!settings.exportWeight)
        #expect(!settings.exportSteps)
        #expect(settings.exportGlucose)
        #expect(settings.selectedLabPanels == [.lipid, .thyroid])
        #expect(settings.favoriteLabCodes == ["4548-4", "2093-3"])
        #expect(settings.selectedVitalMetrics == [.bloodPressure, .restingHeartRate])
        #expect(settings.expandedLabPanels == [.cbc])
        #expect(settings.expandedVitalsSection)
        #expect(settings.lastXDaysValue == 7)
        #expect(settings.lastXRecordsValue == 2_000)
    }

    @Test func changes_areWrittenWithTheV250KeysAndFormats() {
        let defaults = makeDefaults()
        let settings = SettingsManager(defaults: defaults)

        settings.temperatureUnit = .celsius
        settings.weightUnit = .kilograms
        settings.dateFormat = .iso8601
        settings.sortOrder = .descending
        settings.autoDismissSaveConfirmation = false
        settings.exportWeight = false
        settings.exportSteps = false
        settings.exportGlucose = true
        settings.selectedLabPanels = [.lipid]
        settings.favoriteLabCodes = ["4548-4"]
        settings.selectedVitalMetrics = [.bloodPressure]
        settings.expandedLabPanels = [.cbc]
        settings.expandedVitalsSection = true
        settings.lastXDaysValue = 7
        settings.lastXRecordsValue = 2_000

        #expect(defaults.string(forKey: "temperatureUnit") == "Celsius (°C)")
        #expect(defaults.string(forKey: "weightUnit") == "Kilograms (kg)")
        #expect(defaults.string(forKey: "dateFormat") == "ISO8601")
        #expect(defaults.string(forKey: "sortOrder") == "Newest → Oldest")
        #expect(defaults.object(forKey: "autoDismissSaveConfirmation") as? Bool == false)
        #expect(defaults.object(forKey: "exportWeight") as? Bool == false)
        #expect(defaults.object(forKey: "exportSteps") as? Bool == false)
        #expect(defaults.object(forKey: "exportGlucose") as? Bool == true)
        #expect(defaults.array(forKey: "selectedLabPanels") as? [String] == ["lipid"])
        #expect(defaults.array(forKey: "favoriteLabCodes") as? [String] == ["4548-4"])
        #expect(defaults.array(forKey: "selectedVitalMetrics") as? [String] == ["bloodPressure"])
        #expect(defaults.array(forKey: "expandedLabPanels") as? [String] == ["cbc"])
        #expect(defaults.object(forKey: "expandedVitalsSection") as? Bool == true)
        #expect(defaults.object(forKey: "lastXDaysValue") as? Int == 7)
        #expect(defaults.object(forKey: "lastXRecordsValue") as? Int == 2_000)
    }

    @Test func changes_loadIntoANewInstance() {
        let defaults = makeDefaults()
        let first = SettingsManager(defaults: defaults)
        first.weightUnit = .kilograms
        first.favoriteLabCodes = [LOINCCode.hemoglobinA1C]
        first.selectedVitalMetrics = [.bodyTemperature]
        first.lastXRecordsValue = 300

        let second = SettingsManager(defaults: defaults)

        #expect(second.weightUnit == .kilograms)
        #expect(second.favoriteLabCodes == [LOINCCode.hemoglobinA1C])
        #expect(second.selectedVitalMetrics == [.bodyTemperature])
        #expect(second.lastXRecordsValue == 300)
    }

    @Test func instances_doNotShareASuite() {
        let first = SettingsManager(defaults: makeDefaults())
        let second = SettingsManager(defaults: makeDefaults())

        first.exportGlucose = true

        #expect(!second.exportGlucose)
    }

    // MARK: - Fallback for invalid raw values

    @Test func invalidRawValues_fallBackToTheDefaults() {
        let defaults = makeDefaults()
        for key in ["temperatureUnit", "weightUnit", "dateFormat", "sortOrder"] {
            defaults.set("invalid", forKey: key)
        }
        defaults.set(["notAPanel", "lipid"], forKey: "selectedLabPanels")
        defaults.set(["notAVital", "bloodPressure"], forKey: "selectedVitalMetrics")

        let settings = SettingsManager(defaults: defaults)

        #expect(settings.temperatureUnit == .fahrenheit)
        #expect(settings.weightUnit == .pounds)
        #expect(settings.dateFormat == .yyyyMMddHHmmss)
        #expect(settings.sortOrder == .ascending)
        #expect(settings.selectedLabPanels == [.lipid])
        #expect(settings.selectedVitalMetrics == [.bloodPressure])
    }

    // MARK: - Lab selection

    @Test func labSelection_writesBothSets() {
        let defaults = makeDefaults()
        let settings = SettingsManager(defaults: defaults)

        settings.labSelection.setSelected(true, loincCode: LOINCCode.hemoglobinA1C)
        settings.labSelection.setSelected(true, panel: .lipid)

        #expect(settings.labSelection.isSelected(loincCode: LOINCCode.hemoglobinA1C))
        #expect(settings.labSelection.isSelected(panel: .lipid))
        #expect(defaults.array(forKey: "favoriteLabCodes") as? [String] != nil)
        #expect(defaults.array(forKey: "selectedLabPanels") as? [String] == ["lipid"])
    }

    /// #115 through the real settings: the A1C selection survives a reload.
    @Test func labPanelOnThenOff_keepsASingleLabAfterReload() {
        let defaults = makeDefaults()
        let settings = SettingsManager(defaults: defaults)
        settings.labSelection.setSelected(true, loincCode: LOINCCode.hemoglobinA1C)

        settings.labSelection.setSelected(true, panel: .other)
        settings.labSelection.setSelected(false, panel: .other)

        let reloaded = SettingsManager(defaults: defaults)
        #expect(reloaded.favoriteLabCodes == [LOINCCode.hemoglobinA1C])
        #expect(reloaded.selectedLabPanels.isEmpty)
    }

    // MARK: - Legacy exportA1C migration

    @Test func migration_legacyExportA1CTrue_seedsFavorites() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "exportA1C")

        let settings = SettingsManager(defaults: defaults)

        #expect(settings.favoriteLabCodes == [LOINCCode.hemoglobinA1C])
        #expect(defaults.array(forKey: "favoriteLabCodes") as? [String] == [LOINCCode.hemoglobinA1C])
    }

    @Test func migration_legacyExportA1CFalse_doesNotSeedFavorites() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "exportA1C")

        let settings = SettingsManager(defaults: defaults)

        #expect(settings.favoriteLabCodes.isEmpty)
        #expect(defaults.object(forKey: "favoriteLabCodes") == nil)
    }

    @Test func migration_noLegacyKey_doesNotSeedFavorites() {
        let defaults = makeDefaults()

        let settings = SettingsManager(defaults: defaults)

        #expect(settings.favoriteLabCodes.isEmpty)
        #expect(defaults.object(forKey: "favoriteLabCodes") == nil)
    }

    @Test func migration_doesNotOverrideExistingFavorites() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "exportA1C")
        defaults.set(["2093-3"], forKey: "favoriteLabCodes") // user already picked something

        let settings = SettingsManager(defaults: defaults)

        #expect(settings.favoriteLabCodes == ["2093-3"], "Migration must not clobber existing user choices")
    }

    @Test func migration_doesNotOverrideAnEmptyFavoriteList() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "exportA1C")
        defaults.set([String](), forKey: "favoriteLabCodes") // user cleared every lab

        let settings = SettingsManager(defaults: defaults)

        #expect(settings.favoriteLabCodes.isEmpty)
    }

    @Test func migration_runsOnce() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "exportA1C")
        let first = SettingsManager(defaults: defaults)
        first.favoriteLabCodes = []

        let second = SettingsManager(defaults: defaults)

        #expect(second.favoriteLabCodes.isEmpty)
    }
}
