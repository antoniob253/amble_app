import SwiftUI
import Lottie

struct HomeView: View {
    let palette: Palette
    let type: Typography
    let scale: Double
    let steps: Int
    let goal: Int
    let userName: String
    let contactName: String
    let contactRole: String
    let todaysWalks: [WalkSession]
    let healthAuthorized: Bool
    let walkActive: Bool
    let walkStartDate: Date?
    let walkSteps: Int
    let onCall: () -> Void
    let onSOS: () -> Void
    let onOpenWalk: (WalkSession) -> Void
    let onOpenGoal: () -> Void
    let onStartOrResumeWalk: () -> Void
    let onRequestHealth: () -> Void

    @State private var pulseScale: CGFloat = 1

    private var pct: Double { min(1, Double(steps) / Double(max(goal, 1))) }
    private var remaining: Int { max(0, goal - steps) }
    private var celebrating: Bool { steps >= goal }

    /// First name only — keeps the Call card width predictable no matter how
    /// long the full contact name is (e.g. "John Appleseed").
    private var callLabel: String {
        let first = contactName
            .components(separatedBy: .whitespacesAndNewlines)
            .first(where: { !$0.isEmpty }) ?? ""
        return first.isEmpty ? "Call" : "Call \(first)"
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 5 || h >= 22 { return "Still up" }
        if h < 12 { return "Good morning" }
        if h < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private var encouragement: String {
        Encouragement.line(steps: steps, goal: goal, name: userName)
    }

    var body: some View {
        ZStack {
            palette.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(greeting),")
                            .font(type.body(18 * scale, weight: .medium))
                            .foregroundStyle(palette.ink2)
                        Text(userName.isEmpty ? "friend" : userName)
                            .font(type.display(34 * scale, weight: .semibold))
                            .kerning(-0.5)
                            .foregroundStyle(palette.ink)
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)

                    heroCard

                    HStack(spacing: 12) {
                        ActionCard(
                            icon: "phone.fill",
                            label: callLabel,
                            palette: palette, type: type, scale: scale,
                            tint: palette.accent2, emphasis: false,
                            action: onCall
                        )
                        ActionCard(
                            icon: "exclamationmark.circle.fill",
                            label: "Get Help",
                            palette: palette, type: type, scale: scale,
                            tint: palette.danger, emphasis: true,
                            action: onSOS
                        )
                    }

                    walkCard

                    if !healthAuthorized {
                        healthPermissionCard
                    }

                    if !todaysWalks.isEmpty {
                        todaysWalksSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) {
                pulseScale = 1.018
            }
        }
    }

    // MARK: - Walk CTA / resume banner

    /// VoiceOver announcement for the walk start/resume card. The
    /// active variant includes a coarse step count + time-since-start
    /// rather than a live-ticking counter, so VoiceOver doesn't
    /// re-announce on every TimelineView refresh while the user is
    /// holding focus on it.
    private var walkCardA11yLabel: String {
        if walkActive, let start = walkStartDate {
            let mins = max(0, Int(Date().timeIntervalSince(start) / 60))
            return "Walk in progress, \(StepFormat.int(walkSteps)) steps, \(mins) minute\(mins == 1 ? "" : "s") so far"
        }
        return "Take a walk with Amble"
    }

    private var walkCard: some View {
        Button {
            Haptics.medium()
            onStartOrResumeWalk()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(walkActive ? palette.accent : palette.accent.opacity(0.15))
                    // Same Lottie in both states for visual consistency —
                    // only the fill color changes. In the walking state we
                    // recolor the sage fills to white via a Lottie color
                    // value provider so the figure stays legible on top
                    // of the filled accent background.
                    LottieView(animation: .named("walker"))
                        .configure { animationView in
                            if walkActive {
                                let white = ColorValueProvider(
                                    LottieColor(r: 1, g: 1, b: 1, a: 1)
                                )
                                animationView.setValueProvider(
                                    white,
                                    keypath: AnimationKeypath(keypath: "**.Color")
                                )
                            }
                        }
                        .playing(loopMode: .loop)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                        .id(walkActive)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(walkActive ? "You're walking" : "Take a walk")
                        .font(type.display(20 * scale, weight: .bold))
                        .kerning(-0.3)
                        .foregroundStyle(palette.ink)

                    if walkActive, let start = walkStartDate {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(liveBannerText(start: start, now: ctx.date))
                                .font(type.body(14 * scale, weight: .medium))
                                .foregroundStyle(palette.ink2)
                                .monospacedDigit()
                        }
                    } else {
                        Text("Amble will walk with you.")
                            .font(type.body(14 * scale, weight: .medium))
                            .foregroundStyle(palette.ink2)
                    }
                }

                Spacer()

                Image(systemName: walkActive ? "chevron.up" : "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.ink2)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(walkActive ? palette.accent.opacity(0.4) : Color.clear,
                                    lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 14, x: 0, y: 4)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(walkCardA11yLabel)
        .accessibilityHint(walkActive
                           ? "Returns to the walk-in-progress screen."
                           : "Starts a new walk.")
        .accessibilityAddTraits(.isButton)
    }

    private func liveBannerText(start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let m = seconds / 60
        let s = seconds % 60
        let time = String(format: "%d:%02d", m, s)
        return "\(StepFormat.int(walkSteps)) steps · \(time)"
    }

    // MARK: - Sections

    private var healthPermissionCard: some View {
        Button {
            Haptics.tap()
            onRequestHealth()
        } label: {
            // Visual structure preserved; we override accessibility
            // below the buttonStyle to skip the decorative chevron
            // and merge the title + body into one VoiceOver line.
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.soft)
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow step tracking")
                        .font(type.display(18 * scale, weight: .bold))
                        .foregroundStyle(palette.ink)
                    Text("Share your steps with Amble to see today's progress.")
                        .font(type.body(14 * scale, weight: .medium))
                        .foregroundStyle(palette.ink2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(palette.ink2)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(palette.card)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Allow step tracking. Share your steps with Amble to see today's progress.")
        .accessibilityHint("Opens the system Health permission prompt.")
        .accessibilityAddTraits(.isButton)
    }

    private var todaysWalksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TODAY'S WALKS")
                .font(type.body(15 * scale, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(palette.ink2)
                .padding(.horizontal, 10)
                .padding(.top, 8)

            VStack(spacing: 0) {
                ForEach(todaysWalks) { w in
                    WalkRow(walk: w, palette: palette, type: type, scale: scale,
                            isLast: w.id == todaysWalks.last?.id, action: { onOpenWalk(w) })
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(palette.card)
            )
        }
    }

    private var heroCard: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 22) {
                Button {
                    Haptics.tap()
                    onOpenGoal()
                } label: {
                    ZStack {
                        ProgressRing(value: steps, goal: goal, size: 280, stroke: 18,
                                     color: palette.ring, track: palette.ringTrack)
                            .scaleEffect(pulseScale)
                        VStack(spacing: 4) {
                            Text("STEPS TODAY")
                                .font(type.body(15 * scale, weight: .medium))
                                .kerning(0.4)
                                .foregroundStyle(palette.ink2)
                            TickingCounter(
                                target: steps,
                                font: type.display(72 * scale, weight: .semibold),
                                kerning: -2
                            )
                            .foregroundStyle(palette.ink)
                            Text(goalCaption(goal: goal, type: type, scale: scale))
                                .font(type.body(16 * scale, weight: .semibold))
                                .foregroundStyle(palette.accent)
                                .padding(.top, 4)
                        }
                        .frame(width: 240)
                    }
                }
                .buttonStyle(.pressable)
                // Single accessible element for the whole hero ring.
                // Without this VoiceOver reads "STEPS TODAY", then the
                // ticking counter (which can refire on every animation
                // frame), then the goal caption — three separate
                // announcements for one logical control. We collapse
                // it into a single sentence: "5,432 of 7,000 steps,
                // 78 percent of today's goal."
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(StepFormat.int(steps)) of \(StepFormat.int(goal)) steps, \(Int(pct * 100)) percent of today's goal")
                .accessibilityHint("Opens the daily goal editor.")
                .accessibilityAddTraits(.isButton)

                VStack(spacing: 14) {
                    // Hairline divider — same editorial motif used on
                    // the Reflect tab above its attribution line.
                    Rectangle()
                        .fill(palette.ink2.opacity(0.2))
                        .frame(width: 40, height: 0.6)

                    // Fraunces italic, muted ink — reads as a quiet
                    // contemplative aside, not a UI badge.
                    Text(encouragement)
                        .font(type.display(18 * scale, weight: .regular).italic())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(palette.ink2)
                        .lineSpacing(3)
                        .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(palette.card)
                    .shadow(color: .black.opacity(0.04), radius: 24, x: 0, y: 8)
            )
            .overlay(alignment: .top) {
                if celebrating {
                    Confetti(palette: palette)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 32))
                }
            }
        }
    }
}

// Builds an AttributedString for the hero ring's "of 5,000 goal" caption
// where the number sits in the display (Fraunces) face while the rest of
// the line stays in the regular body font, matching the big step count
// above it.
private func goalCaption(goal: Int, type: Typography, scale: Double) -> AttributedString {
    let numStr = StepFormat.int(goal)
    var attr = AttributedString("of \(numStr) goal")
    if let range = attr.range(of: numStr) {
        attr[range].font = type.display(16 * scale, weight: .semibold)
    }
    return attr
}

struct ActionCard: View {
    let icon: String
    let label: String
    let palette: Palette
    let type: Typography
    let scale: Double
    let tint: Color
    let emphasis: Bool
    let action: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(emphasis ? Color.black.opacity(0.2) : tint.opacity(0.12))
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(emphasis ? Color.white : tint)
                }
                .frame(width: 44, height: 44)
                // A whisper-pulse on the emergency card's badge only —
                // signals "ready when you need me" without shouting.
                .scaleEffect(emphasis && pulse ? 1.04 : 1.0)
                .animation(emphasis ? .easeInOut(duration: 2.0).repeatForever(autoreverses: true) : .default,
                           value: pulse)

                Text(label)
                    .font(type.display(24 * scale, weight: .semibold))
                    .kerning(-0.3)
                    .foregroundStyle(emphasis ? .white : palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(emphasis ? tint : palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(emphasis ? Color.clear : Color.black.opacity(0.06), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(emphasis ? 0.12 : 0.04), radius: 14, x: 0, y: 6)
            )
        }
        .buttonStyle(.pressable)
        // The visible label ("Call John" / "Get Help") is already
        // descriptive enough on its own; we just need to ensure the
        // decorative pulsing badge isn't read separately. The
        // accessibilityHint contextualises what the button does — for
        // the Get Help variant especially, "opens the SOS screen" is
        // a meaningful clarification for first-time users on
        // VoiceOver.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint(emphasis
                           ? "Opens the emergency SOS screen."
                           : "Starts a phone call.")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            if emphasis { pulse = true }
        }
    }
}

struct WalkRow: View {
    let walk: WalkSession
    let palette: Palette
    let type: Typography
    let scale: Double
    let isLast: Bool
    let action: () -> Void

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
                        Text("\(walk.windowLabel) — \(walk.timeLabel) · \(walk.durationMinutes) min")
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
                // Make the whole row width tappable — without this,
                // SwiftUI's Button with `.plain` style doesn't hit-test
                // the region occupied by Spacer, so taps near the right
                // edge (before the chevron) silently miss.
                .contentShape(Rectangle())

                if !isLast {
                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.leading, 20)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(StepFormat.int(walk.steps)) steps, \(walk.windowLabel) at \(walk.timeLabel), \(walk.durationMinutes) minute\(walk.durationMinutes == 1 ? "" : "s")")
        .accessibilityHint("Opens the details for this walk.")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Ticking counter

/// Counts up from the previously-displayed value to `target` with ease-out
/// timing. Driven by `TimelineView(.animation)` so every frame re-renders at
/// the display refresh rate — actually ticking, not cross-fading. Duration
/// scales with delta: large jumps (e.g. 0 → 7,000 on first load) take ~1.6s,
/// small live updates (~1–20 steps from CMPedometer) are near-instant.
struct TickingCounter: View {
    let target: Int
    let font: Font
    var kerning: Double = 0

    @State private var fromValue: Int = 0
    @State private var toValue: Int = 0
    @State private var startTime: Date = .now
    @State private var duration: Double = 1.6

    var body: some View {
        TimelineView(.animation) { context in
            Text(StepFormat.int(displayedValue(at: context.date)))
                .font(font)
                .kerning(kerning)
                .monospacedDigit()
        }
        .onAppear { restart(to: target, from: 0) }
        .onChange(of: target) { _, newValue in
            restart(to: newValue, from: displayedValue(at: .now))
        }
    }

    private func displayedValue(at date: Date) -> Int {
        guard duration > 0 else { return toValue }
        let elapsed = max(0, date.timeIntervalSince(startTime))
        let progress = min(1, elapsed / duration)
        // Cubic ease-out — starts fast, settles gently.
        let eased = 1 - pow(1 - progress, 3)
        let delta = Double(toValue - fromValue) * eased
        return fromValue + Int(delta.rounded())
    }

    private func restart(to newTarget: Int, from newFrom: Int) {
        fromValue = newFrom
        toValue = newTarget
        startTime = .now
        let delta = abs(newTarget - newFrom)
        // Short deltas are live updates — keep them snappy so the number
        // feels reactive as the user walks. First-load (big delta) gets the
        // satisfying long tick-up.
        switch delta {
        case ..<10:     duration = 0.25
        case ..<100:    duration = 0.5
        case ..<1_000:  duration = 0.9
        default:        duration = 1.6
        }
    }
}
