import Foundation
@testable import HealthExporter
import Testing

struct DayRangeSummaryFormatterTests {
    /// 2026-03-20T10:00:00Z.
    private let referenceDate = Date(timeIntervalSince1970: 1_774_000_800)

    @Test func summaryText_formatsSevenDayRangeRelativeToToday() {
        let calendar = Calendar(identifier: .gregorian)

        let summary = DayRangeSummaryFormatter.summaryText(forDays: 7, relativeTo: referenceDate, calendar: calendar)

        #expect(summary == "March 14, 2026 to today")
    }

    @Test func summaryText_formatsOneDayRange() {
        let calendar = Calendar(identifier: .gregorian)

        let summary = DayRangeSummaryFormatter.summaryText(forDays: 1, relativeTo: referenceDate, calendar: calendar)

        #expect(summary == "March 20, 2026 to today")
    }
}
