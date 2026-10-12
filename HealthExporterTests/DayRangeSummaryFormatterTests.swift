import Foundation
@testable import HealthExporter
import Testing

struct DayRangeSummaryFormatterTests {
    private var referenceDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 20
        components.hour = 10
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }

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
