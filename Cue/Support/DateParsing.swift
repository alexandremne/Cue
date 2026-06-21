import Foundation

/// Conversions between the model's ISO 8601 datetime strings and `Date`, plus
/// friendly formatting for the UI.
///
/// The model resolves relative expressions ("tomorrow", "next Tuesday at 3") to
/// absolute datetimes because the system prompt carries the current date/time and
/// timezone (see `ToolDefinitions.systemPrompt`). This type handles the final
/// ISO 8601 → `Date` step, including the spec's rule that a dated task with no
/// time defaults to 9:00 AM local.
enum DateParsing {
    /// Default time-of-day applied when the model supplies a date with no time.
    static let defaultHour = 9
    static let defaultMinute = 0

    /// Parses an ISO 8601 string into an absolute `Date`.
    ///
    /// Handles full datetimes ("2026-06-23T15:00:00", with or without a zone) and
    /// date-only values ("2026-06-23"). For date-only input the time defaults to
    /// 9:00 AM local and `timeWasDefaulted` is `true` so the UI can surface it for
    /// adjustment. Returns `nil` for blank or unrecognizable input.
    static func parse(_ raw: String,
                      calendar: Calendar = .current,
                      timeZone: TimeZone = .current) -> (date: Date, timeWasDefaulted: Bool)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let date = datetime(from: trimmed, timeZone: timeZone) {
            return (date, false)
        }

        if let day = dateOnly(from: trimmed, timeZone: timeZone) {
            var cal = calendar
            cal.timeZone = timeZone
            let defaulted = cal.date(bySettingHour: defaultHour, minute: defaultMinute,
                                     second: 0, of: day) ?? day
            return (defaulted, true)
        }
        return nil
    }

    /// ISO 8601 string (local time, no fractional seconds) for the tasks snapshot
    /// embedded in the system prompt.
    static func iso(from date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Compact, friendly label for a task row, e.g. "Today · 3:00 PM",
    /// "Tue · 3:00 PM", or "Jun 24 · 3:00 PM".
    static func friendly(_ date: Date, relativeTo now: Date = Date(),
                         calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today · \(time)" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow · \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday · \(time)" }

        let startNow = calendar.startOfDay(for: now)
        let startDate = calendar.startOfDay(for: date)
        if let days = calendar.dateComponents([.day], from: startNow, to: startDate).day,
           (0...6).contains(days) {
            let weekday = date.formatted(.dateTime.weekday(.abbreviated))
            return "\(weekday) · \(time)"
        }
        let day = date.formatted(.dateTime.month(.abbreviated).day())
        return "\(day) · \(time)"
    }

    /// Fuller label for the confirmation card, e.g. "Tue, Jun 24 at 3:00 PM".
    static func friendlyFull(_ date: Date) -> String {
        let day = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let time = date.formatted(date: .omitted, time: .shortened)
        return "\(day) at \(time)"
    }

    // MARK: - Private

    private static func datetime(from raw: String, timeZone: TimeZone) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.timeZone = timeZone
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }

        // The model often omits the zone ("2026-06-23T15:00:00"); parse as local.
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    private static func dateOnly(from raw: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }
}
