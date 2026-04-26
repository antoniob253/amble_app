import Foundation

/// Duration buckets for the walk-detail afterglow message.
enum WalkDurationBucket: Int {
    case brief = 0   // under 5 minutes
    case gentle      // 5–14 minutes
    case proper      // 15–29 minutes
    case long        // 30+ minutes

    static func from(minutes: Int) -> Self {
        switch minutes {
        case ..<5:    return .brief
        case 5...14:  return .gentle
        case 15...29: return .proper
        default:      return .long
        }
    }
}

/// Warm closing line shown on the walk-detail screen. Four duration
/// buckets × three hand-written variations each. Selection is seeded by
/// the walk's start timestamp, so revisiting a specific walk always
/// shows the same line (different walks get different lines even if
/// they share a bucket).
enum WalkAfterglow {
    static func line(for walk: WalkSession) -> String {
        let bucket = WalkDurationBucket.from(minutes: walk.durationMinutes)
        let pool = phrases[bucket] ?? [fallback(for: bucket)]
        let seed = abs(Int(walk.start.timeIntervalSinceReferenceDate))
        return pool[seed % pool.count]
    }

    // MARK: - Pools
    //
    // Tone: warm, slightly wistful, complete sentences. Matches the
    // "kind companion" voice. Avoid coaching / gamey phrasing.

    private static let phrases: [WalkDurationBucket: [String]] = [
        .brief: [
            "A little walk still counts. Every step matters.",
            "Short, but never wasted. Well done.",
            "A quiet turn is still a turn."
        ],
        .gentle: [
            "A lovely little walk. Well done.",
            "A pleasant stretch of the day.",
            "Time well spent on your feet."
        ],
        .proper: [
            "A proper stroll. Your body will thank you.",
            "Just the right sort of walk.",
            "A walk to be glad of."
        ],
        .long: [
            "What a walk. Take it easy the rest of the day.",
            "A real day on your feet. Well earned.",
            "That's a serious walk. Mind the knees tonight."
        ]
    ]

    private static func fallback(for bucket: WalkDurationBucket) -> String {
        switch bucket {
        case .brief:  return "A little walk still counts."
        case .gentle: return "A lovely little walk."
        case .proper: return "A proper stroll."
        case .long:   return "A long walk — well earned."
        }
    }
}
