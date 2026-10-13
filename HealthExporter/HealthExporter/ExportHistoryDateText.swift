import Foundation

/// The date of an export, relative to now: "today, 3:02 PM",
/// "yesterday, 3:02 PM", "Oct 3, 3:02 PM" or "Oct 3, 2025, 3:02 PM".
/// Tests and screenshots pass a fixed `now`.
nonisolated enum ExportHistoryDateText {
    static func text(
        for date: Date,
        now: Date,
        startsSentence: Bool = false,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        var timeStyle = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar)
        timeStyle.timeZone = calendar.timeZone
        let time = date.formatted(timeStyle)

        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = startsSentence ? "Today" : "today"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(date, inSameDayAs: yesterday)
        {
            day = startsSentence ? "Yesterday" : "yesterday"
        } else {
            var dayStyle = Date.FormatStyle(locale: locale, calendar: calendar).month(.abbreviated).day()
            if !calendar.isDate(date, equalTo: now, toGranularity: .year) {
                dayStyle = dayStyle.year()
            }
            dayStyle.timeZone = calendar.timeZone
            day = date.formatted(dayStyle)
        }
        return "\(day), \(time)"
    }
}
