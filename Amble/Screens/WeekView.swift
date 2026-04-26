import SwiftUI

/// A true calendar-week view. The seven bars always span the user's
/// locale-defined week — Monday → Sunday in most of Europe, Sunday →
/// Saturday in the US — so "This Week" means what it says. Days that
/// haven't happened yet are rendered as hopeful placeholders instead of
/// zero-step bars; stats (daily average, goal-days trophy) are computed
/// over the days that have actually elapsed, so the numbers never
/// average in a Thursday that hasn't happened.
struct WeekView: View {
    let palette: Palette
    let type: Typography
    let scale: Double
    let goal: Int
    let stepsByDay: [Date: Int]
    let recentWalks: [WalkSession]
    let onOpenWalk: (WalkSession) -> Void

    // MARK: - Day model

    enum DayKind {
        case past      // Earlier this week. Has real step data.
        case today     // Today. Has real step data (live-ish).
        case upcoming  // Later this week. No data yet — render as placeholder.
    }

    struct DayStat: Identifiable {
        /// Stable identity: keyed on the date so SwiftUI doesn't treat
        /// each render as a fresh day and re-fire bar animations.
        var id: Date { date }
        let date: Date
        let steps: Int
        let kind: DayKind

        var isToday: Bool { kind == .today }
        var isUpcoming: Bool { kind == .upcoming }
        var isPast: Bool { kind == .past }

        var dayShort: String { AmbleDates.weekdayShort(date) }
        var dayNum: String { AmbleDates.dayNumber(date) }
    }

    /// Seven days spanning the current calendar week, respecting the
    /// user's locale. Order is always start-of-week to end-of-week.
    private var days: [DayStat] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let interval = cal.dateInterval(of: .weekOfYear, for: today) else {
            return []
        }
        return (0..<7).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: interval.start)!
            let kind: DayKind
            if cal.isDate(day, inSameDayAs: today) {
                kind = .today
            } else if day < today {
                kind = .past
            } else {
                kind = .upcoming
            }
            let steps = kind == .upcoming ? 0 : (stepsByDay[day] ?? 0)
            return DayStat(date: day, steps: steps, kind: kind)
        }
    }

    /// Days with real data this week: past days + today. Used as the
    /// denominator for the daily average and trophy so we never divide
    /// by seven when only two days have happened.
    private var elapsedDays: [DayStat] {
        days.filter { !$0.isUpcoming }
    }

    private var dailyAverage: Int {
        guard !elapsedDays.isEmpty else { return 0 }
        let total = elapsedDays.map(\.steps).reduce(0, +)
        return total / elapsedDays.count
    }

    private var goalDaysSoFar: Int {
        elapsedDays.filter { $0.steps >= goal }.count
    }

    /// Reads naturally at any point in the week:
    /// - "steps today" on day 1
    /// - "steps a day" once there's more than one day to average over
    private var averageCaption: String {
        elapsedDays.count <= 1 ? "steps today" : "steps a day"
    }

    // MARK: - Last week comparison

    /// The seven days of last calendar week, resolved via the locale's
    /// own week boundaries. Never rendered as bars — only used to feed
    /// the small "last week you averaged …" footnote on the overview card.
    private var lastWeekDays: [DayStat] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Anchor exactly 7 days before today — guaranteed to sit inside
        // last week's date interval regardless of today's weekday.
        guard let anchor = cal.date(byAdding: .day, value: -7, to: today),
              let interval = cal.dateInterval(of: .weekOfYear, for: anchor) else {
            return []
        }
        return (0..<7).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: interval.start)!
            let steps = stepsByDay[day] ?? 0
            return DayStat(date: day, steps: steps, kind: .past)
        }
    }

    /// Average over the days of last week that actually have step data
    /// (>0). Zero-step days usually mean "no data / app not installed"
    /// rather than a genuine rest day for our audience, so including
    /// them would deflate the comparison for fresh users who onboarded
    /// mid-week. Seniors who walk at all in a day almost always register
    /// non-zero steps from ambient motion.
    private var lastWeekAverage: Int {
        let withData = lastWeekDays.filter { $0.steps > 0 }
        guard !withData.isEmpty else { return 0 }
        return withData.map(\.steps).reduce(0, +) / withData.count
    }

    /// Visibility gate for the last-week footnote. All three must hold:
    /// - It's mid-week or later (3+ elapsed days) so this-week's average
    ///   is settled enough to make the comparison meaningful.
    /// - Last week has 3+ days of real step data — enough to compute a
    ///   non-noisy average, and enough to confirm the app was tracking.
    /// - Last week's average is actually non-zero (defensive).
    private var shouldShowLastWeek: Bool {
        let lastWeekWithData = lastWeekDays.filter { $0.steps > 0 }.count
        return elapsedDays.count >= 3
            && lastWeekWithData >= 3
            && lastWeekAverage > 0
    }

    /// Warm, non-judgmental copy. No arrows, no percentages, no
    /// "up/down" language — those nudge the screen toward a fitness-app
    /// competitive tone we explicitly want to avoid. Just a factual
    /// recollection.
    private var lastWeekLine: String {
        "Last week you averaged \(StepFormat.int(lastWeekAverage))."
    }

    /// Formats the week's span for the header subtitle. Collapses to
    /// "22 – 28 April" inside a single month and expands to
    /// "29 Apr – 5 May" (abbreviated months for compactness) when the
    /// week crosses a boundary. Always English via `AmbleDates`.
    private var dateRangeLabel: String {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: Date()) else {
            return ""
        }
        let start = interval.start
        let end = cal.date(byAdding: .day, value: 6, to: start)!
        let sameMonth = cal.component(.month, from: start) == cal.component(.month, from: end)

        if sameMonth {
            let startDay = cal.component(.day, from: start)
            return "\(startDay) – \(AmbleDates.dayMonth(end))"
        } else {
            return "\(AmbleDates.dayMonthShort(start)) – \(AmbleDates.dayMonthShort(end))"
        }
    }

    // MARK: - Body

    var body: some View {
        // Scale the bars against the true week max so a big day doesn't
        // dwarf its neighbours; fall back to goal so the chart is never
        // all flat on a low-step week.
        let maxVal = max(goal, days.map(\.steps).max() ?? goal)

        // No onBack — Week is a top-level tab, so the tab bar owns the
        // "return to home" affordance.
        ScreenShell(title: "This Week",
                    subtitle: dateRangeLabel,
                    palette: palette, type: type, scale: scale) {
            VStack(alignment: .leading, spacing: 14) {
                overviewCard(maxVal: maxVal)

                SectionHeader(text: "Day by day", palette: palette, type: type, scale: scale)

                VStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element.id) { i, d in
                        DayRow(day: d, goal: goal, palette: palette, type: type, scale: scale)
                        if i < days.count - 1 {
                            Rectangle().fill(Color.black.opacity(0.06))
                                .frame(height: 0.5)
                                .padding(.leading, 78)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(palette.card)
                )

                if !recentWalks.isEmpty {
                    SectionHeader(text: "Recent walks", palette: palette, type: type, scale: scale)
                        .padding(.top, 4)

                    VStack(spacing: 0) {
                        ForEach(recentWalks) { w in
                            RecentWalkRow(
                                walk: w, palette: palette, type: type, scale: scale,
                                isLast: w.id == recentWalks.last?.id,
                                action: { onOpenWalk(w) }
                            )
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous).fill(palette.card)
                    )
                }
            }
        }
    }

    // MARK: - Overview card

    private func overviewCard(maxVal: Int) -> some View {
        Card(palette: palette) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DAILY AVERAGE")
                            .font(type.body(15 * scale, weight: .semibold))
                            .kerning(0.4)
                            .foregroundStyle(palette.ink2)
                        Text(StepFormat.int(dailyAverage))
                            .font(type.display(54 * scale, weight: .semibold))
                            .kerning(-1.5)
                            .foregroundStyle(palette.ink)
                            .monospacedDigit()
                        Text(averageCaption)
                            .font(type.body(16 * scale, weight: .medium))
                            .foregroundStyle(palette.ink2)
                        // Small, quiet footnote — sits a touch apart from
                        // the primary caption so it reads as an aside
                        // rather than a peer metric. Hidden entirely on
                        // early-week days and fresh installs via the
                        // `shouldShowLastWeek` gate.
                        if shouldShowLastWeek {
                            Text(lastWeekLine)
                                .font(type.body(13 * scale, weight: .medium))
                                .foregroundStyle(palette.ink2.opacity(0.75))
                                .padding(.top, 6)
                        }
                    }
                    Spacer()
                    trophyPill
                }

                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(days) { d in
                        BarChartColumn(
                            day: d, maxVal: maxVal, goal: goal,
                            palette: palette, type: type, scale: scale
                        )
                    }
                }
                .frame(height: 180)
            }
        }
    }

    /// Denominator tracks elapsed days, not fixed /7, so mid-week the
    /// count reads as "2 of 3 chances met" rather than "2 of 7 failed".
    private var trophyPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 16, weight: .semibold))
            Text("\(goalDaysSoFar)/\(elapsedDays.count)")
                .font(type.body(17 * scale, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(palette.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(palette.soft)
        )
    }
}

// MARK: - Bar chart column

private struct BarChartColumn: View {
    let day: WeekView.DayStat
    let maxVal: Int
    let goal: Int
    let palette: Palette
    let type: Typography
    let scale: Double
    @State private var appear: CGFloat = 0

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    barShape(in: geo.size)
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            Text(day.dayShort)
                .font(type.body(14 * scale, weight: day.isToday ? .bold : .medium))
                .foregroundStyle(labelColor)
        }
        .onAppear {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.75)) { appear = 1 }
        }
        // Each bar becomes a single VoiceOver element with a complete
        // sentence. Without this, the swiping order would announce
        // an empty bar shape, then the 3-letter day abbreviation,
        // for each of the seven columns — which is just noise.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(barA11yLabel)
    }

    /// VoiceOver phrasing for one day's bar. Says the full weekday
    /// (not the 3-letter abbreviation, which can be ambiguous out of
    /// context — "Sat" vs. "Sun" sound similar synthesised), the
    /// date phase ("Today" / "Upcoming" / past), and the step count
    /// or goal-relative status.
    private var barA11yLabel: String {
        let weekday = AmbleDates.weekday(day.date)
        if day.isUpcoming { return "\(weekday), upcoming" }
        let stepsText = "\(StepFormat.int(day.steps)) steps"
        let goalText: String
        if day.steps >= goal {
            goalText = "goal reached"
        } else {
            goalText = "of \(StepFormat.int(goal)) goal"
        }
        let prefix = day.isToday ? "Today, \(weekday)" : weekday
        return "\(prefix), \(stepsText), \(goalText)"
    }

    private var labelColor: Color {
        if day.isToday { return palette.accent }
        if day.isUpcoming { return palette.ink2.opacity(0.45) }
        return palette.ink2
    }

    /// Three visual categories:
    /// - upcoming → dashed outline placeholder. Visually distinct from a
    ///   zero-step bar so the user doesn't read it as failure.
    /// - today → accent fill with cream diagonal stripes. Reads as
    ///   "live / in progress" and is clearly separable from a past
    ///   goal-hit bar (which uses the same accent but solid).
    /// - past → standard filled bar, accent-coloured if goal hit.
    ///
    /// Today and upcoming share the same minimum height, so the
    /// "today" striped bar is never shorter than the hopeful dashed
    /// placeholder for tomorrow — that visual hierarchy would read
    /// backwards (you've made progress, why does today look smaller
    /// than tomorrow's empty slot?).
    @ViewBuilder
    private func barShape(in size: CGSize) -> some View {
        // Shared minimum height for the "barely-any-data-yet" case —
        // applies to upcoming placeholders AND to today before the
        // step count grows large enough to overtake the floor.
        let placeholderMin = max(14, size.height * 0.15) * appear

        if day.isUpcoming {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    palette.ink2.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4])
                )
                .frame(height: placeholderMin)
        } else if day.isToday {
            let raw = CGFloat(day.steps) / CGFloat(max(maxVal, 1)) * size.height * appear
            // `max(raw, placeholderMin)` means the bar grows
            // proportionally with the day's steps, but never shrinks
            // below the upcoming-day floor. At low step counts the
            // bar reads as "today, in motion, just getting going";
            // at high step counts it reflects the actual progress.
            let h = max(raw, placeholderMin)
            ZStack {
                Rectangle().fill(palette.accent)
                DiagonalStripes(stripeWidth: 5, stripeGap: 6)
                    .fill(palette.soft.opacity(0.85))
            }
            .frame(height: h)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            let raw = CGFloat(day.steps) / CGFloat(max(maxVal, 1)) * size.height * appear
            let hit = day.steps >= goal
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hit ? palette.ring : palette.ringTrack)
                .frame(height: raw)
        }
    }
}

/// Diagonal stripe pattern used for the "today" bar. 45° from
/// top-left → bottom-right regardless of the bar's dimensions, so the
/// stripe angle stays constant whether the bar is 18pt tall (morning,
/// no steps yet) or 160pt tall (a big day). Designed to be composed
/// over a solid fill inside a ZStack and then clipped to the bar's
/// rounded rectangle.
private struct DiagonalStripes: Shape {
    var stripeWidth: CGFloat = 5
    var stripeGap: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let period = stripeWidth + stripeGap
        // 45°: horizontal displacement equals vertical displacement,
        // so each stripe is a parallelogram whose top and bottom edges
        // are offset by `rect.height` horizontally.
        let shift = rect.height
        var x = -shift
        while x < rect.width + shift {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x + stripeWidth, y: 0))
            path.addLine(to: CGPoint(x: x + stripeWidth + shift, y: rect.height))
            path.addLine(to: CGPoint(x: x + shift, y: rect.height))
            path.closeSubpath()
            x += period
        }
        return path
    }
}

// MARK: - Day row

private struct DayRow: View {
    let day: WeekView.DayStat
    let goal: Int
    let palette: Palette
    let type: Typography
    let scale: Double

    var body: some View {
        HStack(spacing: 14) {
            dayBadge
            detail
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        // Upcoming rows fade back so past / today rows feel primary
        // without hiding future days entirely.
        .opacity(day.isUpcoming ? 0.55 : 1.0)
    }

    private var dayBadge: some View {
        VStack(spacing: 1) {
            Text(day.dayShort.uppercased())
                .font(type.display(11 * scale, weight: .bold))
            Text(day.dayNum)
                .font(type.display(16 * scale, weight: .bold))
        }
        .foregroundStyle(badgeForeground)
        .frame(width: 44, height: 44)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(badgeBackground)
        )
    }

    private var badgeForeground: Color {
        if day.isUpcoming { return palette.ink2 }
        return day.steps >= goal ? .white : palette.ink2
    }

    private var badgeBackground: Color {
        if day.isUpcoming { return palette.soft.opacity(0.55) }
        return day.steps >= goal ? palette.accent : palette.soft
    }

    @ViewBuilder
    private var detail: some View {
        if day.isUpcoming {
            Text("Not yet")
                .font(type.body(16 * scale, weight: .medium))
                .foregroundStyle(palette.ink2)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(StepFormat.int(day.steps)) steps")
                    .font(type.body(18 * scale, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Text(day.steps >= goal
                     ? "Goal reached"
                     : "\(Int(Double(day.steps) / Double(max(goal, 1)) * 100))% of goal")
                    .font(type.body(14 * scale, weight: .medium))
                    .foregroundStyle(palette.ink2)
            }
        }
    }
}

// MARK: - Recent walks row

private struct RecentWalkRow: View {
    let walk: WalkSession
    let palette: Palette
    let type: Typography
    let scale: Double
    let isLast: Bool
    let action: () -> Void

    private var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(walk.start) { return "Today" }
        if cal.isDateInYesterday(walk.start) { return "Yesterday" }
        return AmbleDates.weekday(walk.start)
    }

    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(palette.soft)
                        Image(systemName: "figure.walk")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(palette.accent)
                    }
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(StepFormat.int(walk.steps)) steps")
                            .font(type.body(17 * scale, weight: .semibold))
                            .foregroundStyle(palette.ink)
                        Text("\(dateLabel) — \(walk.timeLabel) · \(walk.durationMinutes) min")
                            .font(type.body(14 * scale, weight: .medium))
                            .foregroundStyle(palette.ink2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.ink2)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .contentShape(Rectangle())

                if !isLast {
                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.leading, 74)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(StepFormat.int(walk.steps)) steps, \(dateLabel) at \(walk.timeLabel), \(walk.durationMinutes) minute\(walk.durationMinutes == 1 ? "" : "s")")
        .accessibilityHint("Opens the details for this walk.")
        .accessibilityAddTraits(.isButton)
    }
}
