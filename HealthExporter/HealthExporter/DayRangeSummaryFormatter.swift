import Foundation

enum DayRangeSummaryFormatter {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()

    static func summaryText(forDays days: Int, relativeTo referenceDate: Date, calendar: Calendar = .current) -> String {
        let offset = max(days - 1, 0)
        guard let startDate = calendar.date(byAdding: .day, value: -offset, to: referenceDate) else {
            return ""
        }

        return "\(dateFormatter.string(from: startDate)) to today"
    }
}
