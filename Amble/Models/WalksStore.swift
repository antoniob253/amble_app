import Foundation
import Observation

@Observable
@MainActor
final class WalksStore {
    private(set) var sessions: [WalkSession]

    private static let storageKey = "amble_walks"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let arr = try? JSONDecoder().decode([WalkSession].self, from: data) {
            self.sessions = arr.sorted { $0.start > $1.start }
        } else {
            self.sessions = []
        }
    }

    func add(_ session: WalkSession) {
        sessions.insert(session, at: 0)
        persist()
    }

    func remove(id: UUID) {
        sessions.removeAll { $0.id == id }
        persist()
    }

    var today: [WalkSession] {
        sessions.filter { Calendar.current.isDateInToday($0.start) }
    }

    /// Walks from the current calendar week, newest first. Respects the
    /// locale's first-day-of-week (Monday in most of Europe, Sunday in
    /// the US) via `Calendar.current`. Matches the WeekView's framing so
    /// walks from a week the user considers "last week" don't bleed into
    /// the current week's list.
    var thisWeek: [WalkSession] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: Date()) else {
            return []
        }
        return sessions.filter { $0.start >= interval.start && $0.start < interval.end }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
