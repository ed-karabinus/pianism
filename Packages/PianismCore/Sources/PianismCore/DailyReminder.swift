import Foundation

/// When the daily reminder comes (SET-1). The system can't skip a day by itself, so each day's is added ahead of time,
/// and the app adds more when it's opened. Someone who stops opening it stops being reminded after `daysAhead` days
/// (decided with Ed, 2026-11-05).
public enum DailyReminder {
    /// 6:00 PM, in minutes after midnight (decided with Ed, 2026-11-02).
    public static let defaultMinute = 18 * 60
    public static let daysAhead = 14

    /// The next `daysAhead` reminders at `minute` after midnight, from the first still to come. In the calendar's
    /// terms but no time zone's, so a reminder comes at that time wherever the phone has got to.
    public static func dates(atMinute minute: Int, after now: Date, in calendar: Calendar) -> [DateComponents] {
        let today = calendar.startOfDay(for: now)
        let times = (0...daysAhead).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)
        }
        return times.filter { $0 > now }.prefix(daysAhead).map {
            calendar.dateComponents([.year, .month, .day, .hour, .minute], from: $0)
        }
    }
}
