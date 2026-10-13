import Foundation
@testable import HealthExporter
import Testing

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

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SettingsManagerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        suiteNames.append(suiteName)
        return defaults
    }

    // MARK: - Defaults when no key is set

    @Test func emptySuite_loadsTheDefaults() throws {
        let settings = try SettingsManager(defaults: makeDefaults())

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
        #expect(settings.keepExportHistory)
        #expect(settings.exportHistory.isEmpty)
    }

    @Test func loading_writesNothingToTheSuite() throws {
        let defaults = try makeDefaults()

        _ = SettingsManager(defaults: defaults)

        for key in Self.persistedKeys + Self.historyKeys {
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

    /// The keys that v2.6.0 added.
    private static let historyKeys = ["keepExportHistory", "exportHistory"]

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
        defaults.set(2000, forKey: "lastXRecordsValue")
    }

    @Test func suiteWrittenByV250_loadsUnchanged() throws {
        let defaults = try makeDefaults()
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
        #expect(settings.lastXRecordsValue == 2000)
    }

    @Test func changes_areWrittenWithTheV250KeysAndFormats() throws {
        let defaults = try makeDefaults()
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
        settings.lastXRecordsValue = 2000

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
        #expect(defaults.object(forKey: "lastXRecordsValue") as? Int == 2000)
    }

    @Test func changes_loadIntoANewInstance() throws {
        let defaults = try makeDefaults()
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

    @Test func instances_doNotShareASuite() throws {
        let first = try SettingsManager(defaults: makeDefaults())
        let second = try SettingsManager(defaults: makeDefaults())

        first.exportGlucose = true

        #expect(!second.exportGlucose)
    }

    // MARK: - Fallback for invalid raw values

    @Test func invalidRawValues_fallBackToTheDefaults() throws {
        let defaults = try makeDefaults()
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

    @Test func labSelection_writesBothSets() throws {
        let defaults = try makeDefaults()
        let settings = SettingsManager(defaults: defaults)

        settings.labSelection.setSelected(true, loincCode: LOINCCode.hemoglobinA1C)
        settings.labSelection.setSelected(true, panel: .lipid)

        #expect(settings.labSelection.isSelected(loincCode: LOINCCode.hemoglobinA1C))
        #expect(settings.labSelection.isSelected(panel: .lipid))
        #expect(defaults.array(forKey: "favoriteLabCodes") as? [String] != nil)
        #expect(defaults.array(forKey: "selectedLabPanels") as? [String] == ["lipid"])
    }

    /// #115 through the real settings: the A1C selection survives a reload.
    @Test func labPanelOnThenOff_keepsASingleLabAfterReload() throws {
        let defaults = try makeDefaults()
        let settings = SettingsManager(defaults: defaults)
        settings.labSelection.setSelected(true, loincCode: LOINCCode.hemoglobinA1C)

        settings.labSelection.setSelected(true, panel: .other)
        settings.labSelection.setSelected(false, panel: .other)

        let reloaded = SettingsManager(defaults: defaults)
        #expect(reloaded.favoriteLabCodes == [LOINCCode.hemoglobinA1C])
        #expect(reloaded.selectedLabPanels.isEmpty)
    }

    // MARK: - Export history

    private static func historyEntry(
        minutes: Int = 0,
        labCodes: Set<String> = [LOINCCode.hemoglobinA1C],
        dateRange: ExportHistoryDateRange = .lastDays(7)
    ) -> ExportHistoryEntry {
        ExportHistoryEntry(
            date: Date(timeIntervalSince1970: 1_790_000_000 + TimeInterval(minutes * 60)),
            exportWeight: false,
            exportSteps: true,
            exportGlucose: true,
            vitalMetrics: [.restingHeartRate],
            labSelection: LabSelection(panels: [.thyroid], favoriteCodes: labCodes),
            dateRange: dateRange,
            file: CSVFile(content: "abc", rowCount: 3),
            failedMetrics: []
        )
    }

    @Test func recordExport_addsTheEntry_andItLoadsIntoANewInstance() throws {
        let defaults = try makeDefaults()
        let settings = SettingsManager(defaults: defaults)
        let entry = Self.historyEntry()

        settings.recordExport(entry)

        #expect(settings.exportHistory.entries == [entry])
        #expect(defaults.data(forKey: "exportHistory") != nil)
        #expect(SettingsManager(defaults: defaults).exportHistory.entries == [entry])
    }

    @Test func recordExport_keepsTheTenNewest() throws {
        let settings = try SettingsManager(defaults: makeDefaults())
        let entries = (0 ..< 11).map { Self.historyEntry(minutes: $0) }

        for entry in entries {
            settings.recordExport(entry)
        }

        #expect(settings.exportHistory.entries.count == 10)
        #expect(settings.exportHistory.latest == entries[10])
        #expect(!settings.exportHistory.entries.contains(entries[0]))
    }

    @Test func clearExportHistory_removesEveryEntry_andTheStoredValue() throws {
        let defaults = try makeDefaults()
        let settings = SettingsManager(defaults: defaults)
        settings.recordExport(Self.historyEntry())
        settings.recordExport(Self.historyEntry(minutes: 1))

        settings.clearExportHistory()

        #expect(settings.exportHistory.isEmpty)
        #expect(defaults.object(forKey: "exportHistory") == nil)
        #expect(settings.keepExportHistory)
    }

    @Test func keepExportHistoryOff_clearsTheHistory_andStopsRecording() throws {
        let defaults = try makeDefaults()
        let settings = SettingsManager(defaults: defaults)
        settings.recordExport(Self.historyEntry())

        settings.keepExportHistory = false
        settings.recordExport(Self.historyEntry(minutes: 1))

        #expect(settings.exportHistory.isEmpty)
        #expect(defaults.object(forKey: "exportHistory") == nil)
        #expect(defaults.object(forKey: "keepExportHistory") as? Bool == false)
        #expect(!SettingsManager(defaults: defaults).keepExportHistory)
    }

    @Test func keepExportHistoryOnAgain_recordsAgain() throws {
        let settings = try SettingsManager(defaults: makeDefaults())
        settings.keepExportHistory = false

        settings.keepExportHistory = true
        settings.recordExport(Self.historyEntry())

        #expect(settings.exportHistory.entries.count == 1)
    }

    @Test func badStoredHistory_loadsAsEmpty() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not json".utf8), forKey: "exportHistory")

        let settings = SettingsManager(defaults: defaults)

        #expect(settings.exportHistory.isEmpty)
    }

    @Test func storedHistoryOfTheWrongType_loadsAsEmpty() throws {
        let defaults = try makeDefaults()
        defaults.set("not data", forKey: "exportHistory")

        let settings = SettingsManager(defaults: defaults)

        #expect(settings.exportHistory.isEmpty)
    }

    // MARK: - Export Again

    @Test func restoreSelection_setsTheSelectionAndTheDays() throws {
        let defaults = try makeDefaults()
        let settings = SettingsManager(defaults: defaults)
        settings.exportWeight = true
        settings.exportSteps = false
        settings.selectedLabPanels = [.lipid]
        settings.favoriteLabCodes = [LOINCCode.totalCholesterol]
        settings.selectedVitalMetrics = [.bloodPressure]
        let entry = Self.historyEntry(dateRange: .lastDays(14))

        let range = settings.restoreSelection(from: entry)

        #expect(range == .lastDays(14))
        #expect(!settings.exportWeight)
        #expect(settings.exportSteps)
        #expect(settings.exportGlucose)
        #expect(settings.selectedVitalMetrics == [.restingHeartRate])
        #expect(settings.selectedLabPanels == [.thyroid])
        #expect(settings.favoriteLabCodes == [LOINCCode.hemoglobinA1C])
        #expect(settings.lastXDaysValue == 14)
        // Choose Data reads the same stored values.
        let reloaded = SettingsManager(defaults: defaults)
        #expect(reloaded.selectedLabPanels == [.thyroid])
        #expect(reloaded.favoriteLabCodes == [LOINCCode.hemoglobinA1C])
        #expect(reloaded.lastXDaysValue == 14)
    }

    @Test func restoreSelection_setsTheRecords() throws {
        let settings = try SettingsManager(defaults: makeDefaults())

        let range = settings.restoreSelection(from: Self.historyEntry(dateRange: .lastRecords(3000)))

        #expect(range == .lastRecords(3000))
        #expect(settings.lastXRecordsValue == 3000)
        #expect(settings.lastXDaysValue == 30)
    }

    @Test func restoreSelection_returnsASpecificRange_andKeepsTheCounts() throws {
        let settings = try SettingsManager(defaults: makeDefaults())
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let end = Date(timeIntervalSince1970: 1_790_000_000)

        let range = settings.restoreSelection(from: Self.historyEntry(dateRange: .specific(start: start, end: end)))

        #expect(range == .specific(start: start, end: end))
        #expect(range.option == .specificDateRange)
        #expect(settings.lastXDaysValue == 30)
        #expect(settings.lastXRecordsValue == 100)
    }

    @Test func restoreSelection_skipsALabThatIsNotInTheRegistry() throws {
        let settings = try SettingsManager(defaults: makeDefaults())
        var entry = Self.historyEntry()
        entry.labCodes = ["0000-0", LOINCCode.hemoglobinA1C]
        entry.labPanels = ["notAPanel", "lipid"]
        entry.vitalMetrics = ["notAVital", "bodyTemperature"]

        settings.restoreSelection(from: entry)

        #expect(settings.favoriteLabCodes == [LOINCCode.hemoglobinA1C])
        #expect(settings.selectedLabPanels == [.lipid])
        #expect(settings.selectedVitalMetrics == [.bodyTemperature])
    }

    @Test func restoreSelection_doesNotChangeTheHistory() throws {
        let settings = try SettingsManager(defaults: makeDefaults())
        let entry = Self.historyEntry()
        settings.recordExport(entry)

        settings.restoreSelection(from: entry)

        #expect(settings.exportHistory.entries == [entry])
    }

    // MARK: - Legacy exportA1C migration

    @Test func migration_legacyExportA1CTrue_seedsFavorites() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "exportA1C")

        let settings = SettingsManager(defaults: defaults)

        #expect(settings.favoriteLabCodes == [LOINCCode.hemoglobinA1C])
        #expect(defaults.array(forKey: "favoriteLabCodes") as? [String] == [LOINCCode.hemoglobinA1C])
    }

    @Test func migration_legacyExportA1CFalse_doesNotSeedFavorites() throws {
        let defaults = try makeDefaults()
        defaults.set(false, forKey: "exportA1C")

        let settings = SettingsManager(defaults: defaults)

        #expect(settings.favoriteLabCodes.isEmpty)
        #expect(defaults.object(forKey: "favoriteLabCodes") == nil)
    }

    @Test func migration_noLegacyKey_doesNotSeedFavorites() throws {
        let defaults = try makeDefaults()

        let settings = SettingsManager(defaults: defaults)

        #expect(settings.favoriteLabCodes.isEmpty)
        #expect(defaults.object(forKey: "favoriteLabCodes") == nil)
    }

    @Test func migration_doesNotOverrideExistingFavorites() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "exportA1C")
        defaults.set(["2093-3"], forKey: "favoriteLabCodes") // user already picked something

        let settings = SettingsManager(defaults: defaults)

        #expect(settings.favoriteLabCodes == ["2093-3"], "Migration must not clobber existing user choices")
    }

    @Test func migration_doesNotOverrideAnEmptyFavoriteList() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "exportA1C")
        defaults.set([String](), forKey: "favoriteLabCodes") // user cleared every lab

        let settings = SettingsManager(defaults: defaults)

        #expect(settings.favoriteLabCodes.isEmpty)
    }

    @Test func migration_runsOnce() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "exportA1C")
        let first = SettingsManager(defaults: defaults)
        first.favoriteLabCodes = []

        let second = SettingsManager(defaults: defaults)

        #expect(second.favoriteLabCodes.isEmpty)
    }
}
