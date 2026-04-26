import Foundation

/// A single piece of poetry or wisdom. Loaded from `reflections.json`
/// in the app bundle — all public-domain, hand-curated.
struct Reflection: Identifiable, Codable, Hashable {
    let id: String
    let text: String
    let author: String
    /// Rough year of writing or publication. Negative values = BCE.
    /// Nil for pieces where a date is genuinely unknown.
    let year: Int?
    /// Optional piece/collection title (e.g. "Song of Myself").
    let title: String?
    /// True = line-broken verse; false = flowing prose.
    let isVerse: Bool

    /// Human-readable year label ("1856", "175 CE", "c. 500 BCE", or "" when nil).
    var yearLabel: String {
        guard let year else { return "" }
        if year > 1500 { return String(year) }
        if year > 0 { return "\(year) CE" }
        return "c. \(abs(year)) BCE"
    }

    /// Formatted plain-text payload for the iOS share sheet. Preserves
    /// the piece's line breaks so verse lands intact in Messages / Mail,
    /// with an em-dashed attribution beneath and a single quiet "via
    /// Amble" footer. The user can always edit this in the target app
    /// before sending — iOS's share flow allows that for text messages
    /// and mail.
    var shareText: String {
        let attribution: String
        if yearLabel.isEmpty {
            attribution = "— \(author)"
        } else {
            attribution = "— \(author), \(yearLabel)"
        }
        return "\(text)\n\n\(attribution)\n\nvia Amble"
    }
}

/// Central access point for the reflections pool. Loads the curated set
/// once from the app bundle's JSON and serves one piece per day via a
/// deterministic seed.
enum Reflections {
    static let all: [Reflection] = loadFromBundle()

    /// Today's piece — stable across the whole day, different tomorrow.
    static func forToday() -> Reflection? {
        forDate(Date())
    }

    /// Piece for a specific day. Same user sees the same piece on the
    /// same day; rotation advances by day.
    static func forDate(_ date: Date) -> Reflection? {
        guard !all.isEmpty else { return nil }
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .dayOfYear], from: date)
        let year = comps.year ?? 2026
        let day = comps.dayOfYear ?? 1
        // Large prime multipliers so year-over-year rotation doesn't
        // repeat the exact same schedule — today-this-year and
        // today-next-year will differ.
        let seed = abs(year &* 397 &+ day &* 17)
        return all[seed % all.count]
    }

    // MARK: - Bundle loading

    private static func loadFromBundle() -> [Reflection] {
        guard let url = Bundle.main.url(forResource: "reflections", withExtension: "json") else {
            assertionFailure("reflections.json missing from bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Container.self, from: data).pieces
        } catch {
            assertionFailure("Failed to decode reflections.json: \(error)")
            return []
        }
    }

    private struct Container: Decodable {
        let version: Int
        let pieces: [Reflection]
    }
}
