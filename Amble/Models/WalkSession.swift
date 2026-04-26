import Foundation

/// A real walk the user started and ended on purpose. Unlike the old
/// hourly-derived HealthWalk, start/end here are exact wall-clock timestamps
/// from the tracker, so duration and time-of-day labels are honest.
struct WalkSession: Identifiable, Codable, Hashable {
    let id: UUID
    let start: Date
    let end: Date
    let steps: Int

    init(id: UUID = UUID(), start: Date, end: Date, steps: Int) {
        self.id = id
        self.start = start
        self.end = end
        self.steps = steps
    }

    var durationSeconds: Int { max(0, Int(end.timeIntervalSince(start))) }
    var durationMinutes: Int { max(1, Int((Double(durationSeconds) / 60).rounded())) }

    /// Approximate meters walked. 0.762 m/step is the CDC/Healthline average
    /// adult stride — close enough for copy like "0.6 mi".
    var distanceMeters: Double { Double(steps) * 0.762 }

    /// Shared 12-hour wall-clock formatter, pinned to Amble's English
    /// display locale via `AmbleDates` so "AM/PM" stays consistent
    /// regardless of the user's region. All walk time labels
    /// (timeLabel / endTimeLabel) flow through this single formatter.
    static let timeFormatter: DateFormatter = AmbleDates.formatter(format: "h:mm a")

    var timeLabel: String { Self.timeFormatter.string(from: start) }
    var endTimeLabel: String { Self.timeFormatter.string(from: end) }

    var windowLabel: String {
        let h = Calendar.current.component(.hour, from: start)
        if h < 5  { return "Night" }
        if h < 11 { return "Morning" }
        if h < 14 { return "Around noon" }
        if h < 18 { return "Afternoon" }
        if h < 21 { return "Evening" }
        return "Night"
    }

    var title: String {
        switch windowLabel {
        case "Morning":     return "Morning Walk"
        case "Around noon": return "Midday Walk"
        case "Afternoon":   return "Afternoon Walk"
        case "Evening":     return "Evening Walk"
        case "Night":       return "Night Walk"
        default:            return "Walk"
        }
    }
}
