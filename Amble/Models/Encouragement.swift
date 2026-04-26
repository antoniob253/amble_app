import Foundation

/// Progress bucket the user is in. Tiers change infrequently (only when you
/// cross a meaningful threshold), so the encouragement line feels stable
/// rather than re-rolling on every step.
enum EncouragementTier: Int {
    case none = 0   // 0 steps
    case starting   // > 0, < 25%
    case steady     // 25–50%
    case halfway    // 50–75%
    case closing    // 75–99%
    case almost     // within 500 steps of goal
    case done       // 100–149%
    case beyond     // 150%+

    static func from(steps: Int, goal: Int) -> Self {
        guard goal > 0 else { return .none }
        if steps <= 0 { return .none }
        let pct = Double(steps) / Double(goal)
        if pct >= 1.5 { return .beyond }
        if pct >= 1.0 { return .done }
        let remaining = goal - steps
        if remaining < 500 { return .almost }
        if pct >= 0.75 { return .closing }
        if pct >= 0.50 { return .halfway }
        if pct >= 0.25 { return .steady }
        return .starting
    }
}

/// Coarse time-of-day buckets. Matches the greeting logic in HomeView.
enum DayPart: Int {
    case morning = 0, midday, afternoon, evening, lateNight

    static var current: Self {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 5 || h >= 22 { return .lateNight }
        if h < 11 { return .morning }
        if h < 14 { return .midday }
        if h < 18 { return .afternoon }
        return .evening
    }
}

/// Warm, context-aware copy for the home screen's encouragement line.
///
/// Selection is deterministic per-day: a given user sees the same phrase
/// for the same (tier × daypart) throughout a given day so it doesn't
/// flicker as their step count ticks up. Crossing a tier boundary (e.g.
/// hitting 50%) swaps to a fresh line immediately. Tomorrow the rotation
/// advances and the user sees a different phrase in the same situation.
///
/// Lines may contain `{name}` and `{remaining}` placeholders. Name is
/// substituted with the user's first name when known, or gracefully elided
/// (with adjacent commas) when not.
enum Encouragement {
    static func line(steps: Int, goal: Int, name: String) -> String {
        let tier = EncouragementTier.from(steps: steps, goal: goal)
        let part = DayPart.current
        let pool = phrases(for: tier, part: part)
        guard !pool.isEmpty else { return fallback(for: tier) }
        let seed = dailySeed(tier: tier, part: part)
        let raw = pool[seed % pool.count]
        return personalize(raw, name: name, remaining: max(0, goal - steps))
    }

    // MARK: - Selection

    private static func dailySeed(tier: EncouragementTier, part: DayPart) -> Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .dayOfYear], from: Date())
        let year = comps.year ?? 2026
        let day = comps.dayOfYear ?? 1
        // Prime-ish multipliers so nearby (tier, part) cells don't collide
        // to the same index on the same day.
        return abs(year &* 733 &+ day &* 17 &+ tier.rawValue &* 11 &+ part.rawValue &* 7)
    }

    private static func personalize(_ raw: String, name: String, remaining: Int) -> String {
        var s = raw
        let first = name.components(separatedBy: .whitespacesAndNewlines)
            .first(where: { !$0.isEmpty }) ?? ""
        if first.isEmpty {
            // Strip ", {name}" or "{name}, " patterns so we don't leave
            // stranded commas when the user hasn't set a name yet.
            s = s.replacingOccurrences(of: ", {name}", with: "")
            s = s.replacingOccurrences(of: "{name}, ", with: "")
            s = s.replacingOccurrences(of: "{name}", with: "friend")
        } else {
            s = s.replacingOccurrences(of: "{name}", with: first)
        }
        s = s.replacingOccurrences(of: "{remaining}", with: formatted(remaining))
        return s
    }

    private static func formatted(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private static func fallback(for tier: EncouragementTier) -> String {
        switch tier {
        case .none:      return "A short walk would feel good right now."
        case .starting:  return "A gentle start."
        case .steady:    return "You're doing well."
        case .halfway:   return "You're past the middle."
        case .closing:   return "Almost there."
        case .almost:    return "Nearly there."
        case .done:      return "Wonderful walking today."
        case .beyond:    return "Quite a day of walking."
        }
    }

    // MARK: - Pools
    //
    // Each cell has 4+ variations. Keep lines short (ideally ≤ 55 chars),
    // warm, unhurried. Avoid em dashes. Use {name} sparingly so it doesn't
    // feel performative.

    private static func phrases(for tier: EncouragementTier, part: DayPart) -> [String] {
        switch tier {
        case .none:     return none[part] ?? []
        case .starting: return starting[part] ?? []
        case .steady:   return steady[part] ?? []
        case .halfway:  return halfway[part] ?? []
        case .closing:  return closing[part] ?? []
        case .almost:   return almost
        case .done:     return done
        case .beyond:   return beyond
        }
    }

    // 0 steps — an invitation, never a nag.
    private static let none: [DayPart: [String]] = [
        .morning: [
            "Good morning. The day's just opening.",
            "A cup of tea, then a short stroll?",
            "The morning light is easy on the knees.",
            "Gentle shoes and a loop of the block?"
        ],
        .midday: [
            "A short walk before lunch would feel good.",
            "Still a fine time for a little amble.",
            "The air is waiting, {name}.",
            "Shake out the morning with a stroll."
        ],
        .afternoon: [
            "The afternoon's a lovely time for fresh air.",
            "A stroll now makes the evening sweeter.",
            "A walk, then a rest. Sounds about right.",
            "The day has hours in it yet."
        ],
        .evening: [
            "Even a few minutes will feel lovely.",
            "A soft walk before dinner?",
            "A turn around the block settles the day.",
            "No hurry, {name}. Whenever you're ready."
        ],
        .lateNight: [
            "It's late, but a few steps still count.",
            "Tomorrow's a new chance.",
            "Rest well. The path will still be there.",
            "The day's nearly done. Sleep will help."
        ]
    ]

    // 1% – 24% — acknowledging you've begun.
    private static let starting: [DayPart: [String]] = [
        .morning: [
            "A lovely beginning.",
            "Off to a gentle start, {name}.",
            "One step leads to the next.",
            "Good. Quiet and steady."
        ],
        .midday: [
            "The day's under way.",
            "You've begun. That's the hardest part.",
            "A fine pace for midday.",
            "Keep it light, {name}."
        ],
        .afternoon: [
            "A good time to be moving.",
            "Steady as you go, {name}.",
            "The afternoon suits you.",
            "On your way."
        ],
        .evening: [
            "A slow start to the evening.",
            "Well enough for this hour.",
            "Softly does it.",
            "A gentle evening pace."
        ],
        .lateNight: [
            "Better than nothing.",
            "Every step is something.",
            "Quiet walking at a quiet hour.",
            "{name}, a little is enough."
        ]
    ]

    // 25% – 49% — rhythm forming.
    private static let steady: [DayPart: [String]] = [
        .morning: [
            "A rhythm's forming.",
            "Nicely along, {name}.",
            "You're finding your feet.",
            "The day is opening for you."
        ],
        .midday: [
            "Good going. Keep your pace.",
            "A quarter of the way, just about.",
            "Steady does it.",
            "You're doing well, {name}."
        ],
        .afternoon: [
            "Right on track.",
            "The legs know what they're doing.",
            "Keep at it, {name}.",
            "A fine afternoon's work."
        ],
        .evening: [
            "You've been moving. Well done.",
            "A steady evening.",
            "Good. Keep it unhurried.",
            "You're walking beautifully."
        ],
        .lateNight: [
            "Slowly and well, {name}.",
            "Every step still counts this late.",
            "Gentle pace, soft light.",
            "You're doing enough."
        ]
    ]

    // 50% – 74% — past the hard middle.
    private static let halfway: [DayPart: [String]] = [
        .morning: [
            "More than halfway, and it's still morning.",
            "You're past the middle of it.",
            "Over the hill, {name}.",
            "The rest will come easily."
        ],
        .midday: [
            "Halfway's the hardest. You're through it.",
            "Good work. Take a breath.",
            "You're past the middle now.",
            "Right where you should be, {name}."
        ],
        .afternoon: [
            "The second half is always gentler.",
            "Past halfway, {name}.",
            "You've done the heavy lifting.",
            "Keep your rhythm."
        ],
        .evening: [
            "More behind you than ahead.",
            "Turn for home when you're ready.",
            "You're well past the middle, {name}.",
            "Nearly there, gently."
        ],
        .lateNight: [
            "Past halfway, even at this hour.",
            "Good work for a late day.",
            "The rest will be easy.",
            "You've done plenty, {name}."
        ]
    ]

    // 75% – 99% (but more than 500 steps to go) — the home straight.
    private static let closing: [DayPart: [String]] = [
        .morning: [
            "You can feel it now.",
            "The last stretch, {name}.",
            "Home straight.",
            "A good morning's walking."
        ],
        .midday: [
            "Almost there.",
            "The finish is close, {name}.",
            "Keep your pace. You've got this.",
            "Nearly done for the day."
        ],
        .afternoon: [
            "You can see the goal from here.",
            "The last stretch is the best.",
            "Home straight, {name}.",
            "Well done, really."
        ],
        .evening: [
            "Almost there, and the day's been good.",
            "The last bit, {name}.",
            "You're close. Keep walking.",
            "Nearly. Gently."
        ],
        .lateNight: [
            "So close, and it's nearly bedtime.",
            "The last stretch, {name}.",
            "Nearly home.",
            "Keep going, quiet and steady."
        ]
    ]

    // Fewer than 500 steps remain — specific, a little urgent. These use
    // {remaining} so the number feels personal.
    private static let almost: [String] = [
        "Almost there. Just {remaining} more steps.",
        "{remaining} to go. A short stroll.",
        "{remaining} more, {name}.",
        "{remaining} steps. A turn around the room a few times.",
        "Nearly. {remaining} left.",
        "{remaining} and you're there."
    ]

    // Goal reached (100%–149%) — a warm, unshowy well-done.
    private static let done: [String] = [
        "You did it, {name}. Well walked.",
        "Goal reached. Wonderful.",
        "That's the day's walking done.",
        "A fine day on your feet.",
        "You made it. Time to rest.",
        "Well done. Really."
    ]

    // Well beyond goal (150%+) — gentle, mind your knees.
    private static let beyond: [String] = [
        "More than the goal. Quite a day.",
        "Beyond. Take it gently the rest of the day.",
        "{name}, that's a serious day of walking.",
        "Your body will thank you tomorrow.",
        "Well past. Mind the knees.",
        "A proper day, {name}."
    ]
}
