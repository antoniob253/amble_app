import Foundation

/// Centralised English-locale date formatting for Amble's UI strings.
/// The app ships in English only for v1. Without a fixed locale, a user
/// with a German or French system locale would otherwise see mixed-
/// language strings — "Montag's Thought" on the Reflect tab, "20. – 26.
/// April" with German punctuation on the Week screen, etc. — mismatched
/// against the rest of the English UI. Every user-visible date string
/// in the app goes through this helper so the rendering is predictable.
///
/// Uses `en_US_POSIX` specifically rather than `en_US`: POSIX is a
/// fixed locale that never changes with iOS updates or user region
/// preferences, which is exactly what we want for UI strings that
/// always have to read the same way. `en_US` can drift (AM/PM
/// capitalisation, weekday abbreviations) across iOS versions.
enum AmbleDates {
    /// Fixed English locale used for every user-visible date string.
    static let locale = Locale(identifier: "en_US_POSIX")

    /// A DateFormatter preconfigured with `locale` and the given
    /// format string. Caller picks the format; everything else is
    /// handled so we can't forget the locale at a call site.
    static func formatter(format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = format
        return f
    }

    /// A DateFormatter preconfigured with `locale` and a system
    /// `dateStyle` — e.g. `.long` for "April 24, 2026" renewal dates.
    static func formatter(dateStyle: DateFormatter.Style) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = dateStyle
        return f
    }

    // MARK: - Common queries
    //
    // Named helpers for the formats we actually use in the UI. Prefer
    // these over hand-building a DateFormatter at a call site so the
    // set of formats stays small and auditable.

    /// Full weekday name: "Monday", "Tuesday"…
    static func weekday(_ date: Date) -> String {
        formatter(format: "EEEE").string(from: date)
    }

    /// Abbreviated weekday: "Mon", "Tue"…
    static func weekdayShort(_ date: Date) -> String {
        formatter(format: "EEE").string(from: date)
    }

    /// Day of month as a bare number: "24"
    static func dayNumber(_ date: Date) -> String {
        formatter(format: "d").string(from: date)
    }

    /// Day + full month: "24 April"
    static func dayMonth(_ date: Date) -> String {
        formatter(format: "d MMMM").string(from: date)
    }

    /// Day + abbreviated month: "24 Apr" — used when a line has to fit
    /// two month names (e.g. a cross-month week range).
    static func dayMonthShort(_ date: Date) -> String {
        formatter(format: "d MMM").string(from: date)
    }
}
