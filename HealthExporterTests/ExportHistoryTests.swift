import Foundation
@testable import HealthExporter
import Testing

struct ExportHistoryTests {
    private struct SaveFailed: Error {}

    private static let baseDate = Date(timeIntervalSince1970: 1_790_000_000)

    private static func entry(
        minutes: Int = 0,
        rows: Int = 10,
        dateRange: ExportHistoryDateRange = .lastDays(30)
    ) -> ExportHistoryEntry {
        ExportHistoryEntry(
            date: baseDate.addingTimeInterval(TimeInterval(minutes * 60)),
            exportWeight: true,
            exportSteps: false,
            exportGlucose: true,
            vitalMetrics: [.bloodPressure],
            labSelection: LabSelection(panels: [.lipid], favoriteCodes: [LOINCCode.hemoglobinA1C]),
            dateRange: dateRange,
            file: CSVFile(content: "abc", rowCount: rows),
            failedMetrics: []
        )
    }

    // MARK: - Order and cap

    @Test func add_putsTheNewestEntryFirst() {
        var history = ExportHistory()
        let older = Self.entry(minutes: 0)
        let newer = Self.entry(minutes: 5)

        history.add(older)
        history.add(newer)

        #expect(history.entries.map(\.id) == [newer.id, older.id])
        #expect(history.latest?.id == newer.id)
    }

    @Test func add_keepsTenEntries_andRemovesTheOldestFirst() {
        var history = ExportHistory()
        let entries = (0 ..< 11).map { Self.entry(minutes: $0) }

        for entry in entries.prefix(10) {
            history.add(entry)
        }
        #expect(history.entries.count == 10)

        history.add(entries[10])

        #expect(ExportHistory.maxEntries == 10)
        #expect(history.entries.count == 10)
        #expect(!history.entries.contains { $0.id == entries[0].id })
        #expect(history.entries.first?.id == entries[10].id)
        #expect(history.entries.last?.id == entries[1].id)
    }

    @Test func init_keepsOnlyTheTenNewestEntries() {
        let entries = (0 ..< 12).map { Self.entry(minutes: $0) }

        let history = ExportHistory(entries: entries)

        #expect(history.entries.map(\.id) == entries.prefix(10).map(\.id))
    }

    @Test func clear_removesEveryEntry() {
        var history = ExportHistory(entries: [Self.entry(), Self.entry(minutes: 1)])

        history.clear()

        #expect(history.isEmpty)
        #expect(history.latest == nil)
    }

    // MARK: - Only a successful save adds an entry

    @Test func shouldRecord_aSuccessfulSave() {
        #expect(ExportHistory.shouldRecord(saveResult: .success(URL(fileURLWithPath: "/tmp/file.csv"))))
    }

    @Test func shouldNotRecord_aFailedSave() {
        #expect(!ExportHistory.shouldRecord(saveResult: .failure(SaveFailed())))
    }

    // MARK: - Storage

    @Test(arguments: [
        ExportHistoryDateRange.lastDays(30),
        .lastRecords(500),
        .specific(start: Date(timeIntervalSince1970: 1_780_000_000), end: Date(timeIntervalSince1970: 1_790_000_000)),
        .allRecords,
    ])
    func codable_roundTripKeepsEveryField(_ dateRange: ExportHistoryDateRange) throws {
        var entry = Self.entry(rows: 1234, dateRange: dateRange)
        entry.failedMetrics = ["Steps", "Lab results"]
        let history = ExportHistory(entries: [entry, Self.entry(minutes: -5)])

        let data = try #require(history.encoded())
        let decoded = ExportHistory.decoded(from: data)

        #expect(decoded == history)
    }

    @Test(arguments: [
        Data("not json".utf8),
        Data("{\"entries\": 3}".utf8),
        Data(),
    ])
    func decoded_aBadValue_givesAnEmptyHistory(_ data: Data) {
        #expect(ExportHistory.decoded(from: data).isEmpty)
    }

    @Test func decoded_noValue_givesAnEmptyHistory() {
        #expect(ExportHistory.decoded(from: nil).isEmpty)
    }

    @Test func decoded_moreThanTenStoredEntries_keepsTen() throws {
        struct Stored: Encodable {
            let entries: [ExportHistoryEntry]
        }
        let stored = Stored(entries: (0 ..< 15).map { Self.entry(minutes: $0) })
        let data = try JSONEncoder().encode(stored)

        #expect(ExportHistory.decoded(from: data).entries.count == 10)
    }

    // MARK: - Entry content

    @Test func entry_holdsTheSelectionInAFixedOrder_andTheFileSize() {
        let file = CSVFile(content: "12345", rowCount: 2)

        let entry = ExportHistoryEntry(
            date: Self.baseDate,
            exportWeight: false,
            exportSteps: true,
            exportGlucose: false,
            vitalMetrics: [.bodyTemperature, .bloodPressure],
            labSelection: LabSelection(panels: [.thyroid, .lipid], favoriteCodes: [LOINCCode.hemoglobinA1C]),
            dateRange: .allRecords,
            file: file,
            failedMetrics: ["Weight"]
        )

        #expect(entry.vitalMetrics == ["bloodPressure", "bodyTemperature"])
        #expect(entry.labPanels == ["lipid", "thyroid"])
        #expect(entry.labCodes == [LOINCCode.hemoglobinA1C])
        #expect(entry.rowCount == 2)
        #expect(entry.byteCount == 5)
        #expect(entry.failedMetrics == ["Weight"])
    }

    @Test func entry_skipsUnknownLabsPanelsAndVitals() {
        var entry = Self.entry()
        entry.labCodes = ["0000-0", LOINCCode.hemoglobinA1C]
        entry.labPanels = ["notAPanel", "lipid"]
        entry.vitalMetrics = ["notAVital", "bloodPressure"]

        #expect(entry.knownLabMetrics.map(\.loincCode) == [LOINCCode.hemoglobinA1C])
        #expect(entry.knownLabPanels == [.lipid])
        #expect(entry.knownVitalMetrics == [.bloodPressure])
    }

    @Test func entry_doesNotNameALabTwice() {
        var entry = Self.entry()
        entry.labPanels = ["lipid"]
        entry.labCodes = [LOINCCode.totalCholesterol, LOINCCode.hemoglobinA1C]

        #expect(entry.labMetricsOutsideSelectedPanels.map(\.loincCode) == [LOINCCode.hemoglobinA1C])
    }

    @Test func entry_sizeText() {
        let entry = Self.entry(rows: 1)
        #expect(entry.sizeText.hasPrefix("1 row, "))
    }

    /// An entry holds no file name and no file location.
    @Test func entry_storesNoFileNameOrLocation() throws {
        let data = try #require(ExportHistory(entries: [Self.entry()]).encoded())
        let json = String(decoding: data, as: UTF8.self)

        #expect(!json.contains(".csv"))
        #expect(!json.contains("HealthExporter_"))
        #expect(!json.contains("file:"))
    }

    // MARK: - Date range

    @Test func dateRange_readsTheChooseDataControls() {
        let start = Self.baseDate
        let end = Self.baseDate.addingTimeInterval(86400)

        #expect(ExportHistoryDateRange(option: .lastXDays, lastXDays: 7, lastXRecords: 100, startDate: start, endDate: end)
            == .lastDays(7))
        #expect(ExportHistoryDateRange(option: .lastXRecords, lastXDays: 7, lastXRecords: 100, startDate: start, endDate: end)
            == .lastRecords(100))
        #expect(ExportHistoryDateRange(option: .specificDateRange, lastXDays: 7, lastXRecords: 100, startDate: start, endDate: end)
            == .specific(start: start, end: end))
        #expect(ExportHistoryDateRange(option: .allRecords, lastXDays: 7, lastXRecords: 100, startDate: start, endDate: end)
            == .allRecords)
    }

    @Test func dateRange_givesTheChooseDataOption_andTheSpecificDates() {
        let start = Self.baseDate
        let end = Self.baseDate.addingTimeInterval(86400)
        let specific = ExportHistoryDateRange.specific(start: start, end: end)

        #expect(specific.option == .specificDateRange)
        #expect(specific.specificStart == start)
        #expect(specific.specificEnd == end)
        #expect(ExportHistoryDateRange.lastDays(30).option == .lastXDays)
        #expect(ExportHistoryDateRange.lastDays(30).specificStart == nil)
        #expect(ExportHistoryDateRange.lastRecords(100).option == .lastXRecords)
        #expect(ExportHistoryDateRange.allRecords.option == .allRecords)
    }

    @Test func dateRange_text() {
        #expect(ExportHistoryDateRange.lastDays(30).text() == "Last 30 days")
        #expect(ExportHistoryDateRange.lastDays(1).text() == "Last day")
        #expect(ExportHistoryDateRange.allRecords.text() == "All records")
    }

    // MARK: - Relative date text

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
    }

    @Test func dateText_today() throws {
        let text = try ExportHistoryDateText.text(
            for: Self.date(2026, 10, 12, 15, 2),
            now: Self.date(2026, 10, 12, 17, 30),
            calendar: Self.calendar,
            locale: Locale(identifier: "en_US")
        )
        #expect(text.hasPrefix("today, 3:02"))
        #expect(text.hasSuffix("PM"))
    }

    @Test func dateText_yesterday_startsASentence() throws {
        let text = try ExportHistoryDateText.text(
            for: Self.date(2026, 10, 11, 9, 15),
            now: Self.date(2026, 10, 12, 8, 0),
            startsSentence: true,
            calendar: Self.calendar,
            locale: Locale(identifier: "en_US")
        )
        #expect(text.hasPrefix("Yesterday, 9:15"))
    }

    @Test func dateText_anOlderDate_namesTheDay_andTheYearOnlyWhenItDiffers() throws {
        let locale = Locale(identifier: "en_US")
        let now = try Self.date(2026, 10, 12, 8, 0)

        let thisYear = try ExportHistoryDateText.text(for: Self.date(2026, 10, 3, 9, 15), now: now, calendar: Self.calendar, locale: locale)
        let lastYear = try ExportHistoryDateText.text(for: Self.date(2025, 10, 3, 9, 15), now: now, calendar: Self.calendar, locale: locale)

        #expect(thisYear.hasPrefix("Oct 3, 9:15"))
        #expect(lastYear.hasPrefix("Oct 3, 2025, 9:15"))
    }
}
