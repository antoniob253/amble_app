import Foundation

/// Phase of a walk based on elapsed time. Coarser than the home tier
/// system — a walk has fewer distinct moods than a day's arc of progress.
enum WalkPhase: Int {
    case justStarted = 0    // 0 min
    case settlingIn         // 1–2 min
    case steady             // 3–6 min
    case inStride           // 7–14 min
    case wonderful          // 15–29 min
    case longWalk           // 30+ min

    static func from(elapsedSeconds: Int) -> Self {
        let mins = max(0, elapsedSeconds) / 60
        switch mins {
        case 0:       return .justStarted
        case 1...2:   return .settlingIn
        case 3...6:   return .steady
        case 7...14:  return .inStride
        case 15...29: return .wonderful
        default:      return .longWalk
        }
    }
}

/// Short, contemplative encouragement for the in-walk companion screen.
/// Matches the cadence of the "Walking with you…" header — three to four
/// words, trailing ellipsis, quiet. The phrase is stable per-day per-phase
/// so it doesn't flicker as the walk ticks by; crossing a phase boundary
/// swaps to a fresh line.
enum WalkEncouragement {
    static func line(elapsedSeconds: Int) -> String {
        let phase = WalkPhase.from(elapsedSeconds: elapsedSeconds)
        let pool = phrases[phase] ?? [fallback(for: phase)]
        let seed = dailySeed(phase: phase)
        return pool[seed % pool.count]
    }

    // MARK: - Selection

    private static func dailySeed(phase: WalkPhase) -> Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .dayOfYear], from: Date())
        let year = comps.year ?? 2026
        let day = comps.dayOfYear ?? 1
        return abs(year &* 733 &+ day &* 17 &+ phase.rawValue &* 11)
    }

    private static func fallback(for phase: WalkPhase) -> String {
        switch phase {
        case .justStarted: return "Off you go…"
        case .settlingIn:  return "Finding your rhythm…"
        case .steady:      return "Doing beautifully…"
        case .inStride:    return "In your stride…"
        case .wonderful:   return "A proper amble…"
        case .longWalk:    return "A long one today…"
        }
    }

    // MARK: - Pools
    //
    // 3 short lines per phase. Match the "Walking with you…" cadence —
    // a few words, trailing ellipsis, quiet. No name substitution here;
    // full sentences would break the brevity.

    private static let phrases: [WalkPhase: [String]] = [
        .justStarted: [
            "Off you go…",
            "Take your time…",
            "Gently, gently…"
        ],
        .settlingIn: [
            "Finding your rhythm…",
            "Just breathing…",
            "Softly does it…"
        ],
        .steady: [
            "Doing beautifully…",
            "Steady pace…",
            "Quiet and sure…"
        ],
        .inStride: [
            "In your stride…",
            "Comfortable going…",
            "Walking well…"
        ],
        .wonderful: [
            "A proper amble…",
            "Wonderful going…",
            "Making a day of it…"
        ],
        .longWalk: [
            "A long one today…",
            "Mind your pace…",
            "Nearly there…"
        ]
    ]
}
