import SwiftUI
import CoreMotion

enum OnboardingStep: Int, CaseIterable {
    case welcome, name, age, mobility, activity, gender, goal, contact, location, health, notify, done, paywall

    var progressIndex: Int? {
        switch self {
        case .welcome, .done, .paywall: return nil
        case .name:     return 0
        case .age:      return 1
        case .mobility: return 2
        case .activity: return 3
        case .gender:   return 4
        case .goal:     return 5
        case .contact:  return 6
        case .location: return 7
        case .health:   return 8
        case .notify:   return 9
        }
    }
    static var progressTotal: Int { 10 }
}

@Observable
@MainActor
final class OnboardingState {
    var step: OnboardingStep = .welcome
    var name: String = ""
    var age: Int = 70
    var mobility: Mobility = .none
    var activity: ActivityLevel = .someWalks
    var gender: Gender = .notSaid
    var goal: Int = 5000
    var contactName: String = ""
    var contactRole: String = ""
    var contactPhone: String = ""
    var notificationsEnabled: Bool = false

    func recomputeGoal() {
        goal = UserProfile.suggestedGoal(
            age: age, mobility: mobility, activity: activity, gender: gender
        )
    }
}

struct OnboardingView: View {
    @Environment(Theme.self) private var theme
    @Environment(UserProfile.self) private var profile
    @Environment(StoreManager.self) private var store
    @Environment(HealthStore.self) private var health
    @Environment(NotificationManager.self) private var notifications
    @Environment(LocationManager.self) private var location
    @State private var s = OnboardingState()

    var body: some View {
        let palette = theme.palette
        let type = theme.type
        let scale = theme.textScale

        VStack(spacing: 0) {
            header(palette: palette)
                .padding(.top, 62)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            currentStepView(palette: palette, type: type, scale: scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 28)
                .id(s.step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

            bottomButton(palette: palette, type: type, scale: scale)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
        .background(palette.bg.ignoresSafeArea())
    }

    // MARK: Header
    @ViewBuilder
    private func header(palette: Palette) -> some View {
        HStack(spacing: 14) {
            ZStack {
                if canGoBack {
                    Button {
                        back()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(palette.card))
                            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Back")
                    .accessibilityHint("Returns to the previous step.")
                    .transition(.opacity)
                }
            }
            .frame(width: 44, height: 44)

            HStack(spacing: 6) {
                ForEach(0..<OnboardingStep.progressTotal, id: \.self) { i in
                    let filled: Bool = {
                        if let idx = s.step.progressIndex { return i <= idx }
                        return s.step.rawValue >= OnboardingStep.done.rawValue
                    }()
                    RoundedRectangle(cornerRadius: 2)
                        .fill(filled ? palette.accent : palette.ringTrack)
                        .frame(height: 4)
                        .animation(.easeInOut(duration: 0.4), value: filled)
                }
            }
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var canGoBack: Bool {
        switch s.step {
        case .welcome, .done, .paywall: return false
        default: return true
        }
    }

    private func back() {
        Haptics.tap()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            if let prev = OnboardingStep(rawValue: s.step.rawValue - 1) {
                s.step = prev
            }
        }
    }

    // MARK: Step router
    @ViewBuilder
    private func currentStepView(palette: Palette, type: Typography, scale: Double) -> some View {
        switch s.step {
        case .welcome:  StepWelcome(palette: palette, type: type, scale: scale)
        case .name:     StepName(state: s, palette: palette, type: type, scale: scale)
        case .age:      StepAge(state: s, palette: palette, type: type, scale: scale)
        case .mobility: StepMobility(state: s, palette: palette, type: type, scale: scale)
        case .activity: StepActivity(state: s, palette: palette, type: type, scale: scale)
        case .gender:   StepGender(state: s, palette: palette, type: type, scale: scale)
        case .goal:     StepGoal(state: s, palette: palette, type: type, scale: scale)
        case .contact:  StepContact(state: s, palette: palette, type: type, scale: scale)
        case .location: StepLocation(palette: palette, type: type, scale: scale,
                                     location: location,
                                     contactFirstName: s.contactName
                                         .components(separatedBy: " ").first ?? "",
                                     contactRole: s.contactRole)
        case .health:   StepHealth(palette: palette, type: type, scale: scale,
                                   health: health)
        case .notify:   StepNotify(palette: palette, type: type, scale: scale,
                                   notifications: notifications)
        case .done:     StepDone(state: s, palette: palette, type: type, scale: scale)
        case .paywall:  StepPaywall(palette: palette, type: type, scale: scale,
                                    store: store, onFinish: finish)
        }
    }

    // MARK: Primary button
    @ViewBuilder
    private func bottomButton(palette: Palette, type: Typography, scale: Double) -> some View {
        // The paywall step owns its own CTAs (the two-plan chooser
        // — yearly and monthly buttons live inside StepPaywall
        // itself). Rendering an additional generic "Continue"
        // button at the bottom of the onboarding flow would just
        // add a third confusing primary action. Hide it.
        if s.step == .paywall {
            EmptyView()
        } else {
            let label: String = {
                switch s.step {
                case .welcome:  return "Get started"
                case .contact:  return "Continue"
                // Permission priming steps: always "Continue" regardless
                // of the determination state. Apple App Review (Submission
                // 98bfe2fa, April 28 2026) flagged the previous "Share my
                // steps" / "Share my location" / "Yes, please" labels —
                // combined with the "Maybe later" skip option below — as
                // pre-empting the user's permission decision in our own
                // UI before the iOS system dialog. Plain "Continue" is
                // neutral, iOS-standard, and lets the brand voice live
                // in the screen explainer text above the button rather
                // than on the CTA itself.
                case .location: return "Continue"
                case .health:   return "Continue"
                case .notify:   return "Continue"
                case .done:    return "Almost done"
                default:       return "Continue"
                }
            }()

            PrimaryButton(title: label, palette: palette, type: type, scale: scale, enabled: canNext) {
                advance()
            }
        }
    }

    private var canNext: Bool {
        switch s.step {
        case .name:    return !s.name.trimmingCharacters(in: .whitespaces).isEmpty
        case .contact: return !s.contactName.trimmingCharacters(in: .whitespaces).isEmpty
                        && !s.contactPhone.trimmingCharacters(in: .whitespaces).isEmpty
                        && !s.contactRole.isEmpty
        default: return true
        }
    }

    // MARK: Advance & finish
    private func advance() {
        Haptics.medium()
        switch s.step {
        case .location:
            // Surface the iOS dialog with full context: the user just set up
            // their emergency contact, and now we ask if Amble may share
            // their location with that person if they ever press SOS.
            // `requestAuthorization` no-ops when the user has already chosen,
            // so tapping Continue from the determined state just advances.
            Task {
                await location.requestAuthorization()
                advanceStep()
            }
            return
        case .health:
            // HealthKit prompt first, then Motion — both on the same step so
            // the user has the "share your steps" context loaded in their
            // head when iOS shows the two dialogs back-to-back. Motion has
            // to be primed with a real pedometer query (startUpdates alone
            // doesn't surface the dialog before we move on).
            Task {
                if !health.authorizationDetermined {
                    await health.requestAuthorization()
                }
                await health.primeMotionPermission()
                health.startLiveUpdates()
                advanceStep()
            }
            return
        case .notify:
            Task {
                if !notifications.authorized {
                    let granted = await notifications.requestAuthorization()
                    s.notificationsEnabled = granted
                }
                advanceStep()
            }
            return
        // .paywall is intentionally absent — StepPaywall owns its
        // own CTAs (yearly + monthly buttons) and calls `onFinish`
        // directly when a purchase grants access. The bottom-of-
        // flow button is hidden during the paywall step (see
        // bottomButton above), so there's no advance() entry path
        // from the paywall that needs handling here.
        default:
            advanceStep()
        }
    }

    private func advanceStep() {
        if let next = OnboardingStep(rawValue: s.step.rawValue + 1) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                s.step = next
            }
        }
    }

    private func finish() {
        profile.name = s.name
        profile.age = s.age
        profile.mobility = s.mobility
        profile.activity = s.activity
        profile.gender = s.gender
        profile.dailyGoal = s.goal
        profile.contact = EmergencyContact(name: s.contactName, role: s.contactRole, phone: s.contactPhone)
        profile.notificationsEnabled = s.notificationsEnabled
        if s.notificationsEnabled && notifications.authorized {
            notifications.scheduleDailyReminder(hour: profile.reminderHour)
        }
        withAnimation(.easeInOut(duration: 0.4)) {
            profile.onboarded = true
        }
        Haptics.success()
    }
}

// MARK: Step — Welcome
private struct StepWelcome: View {
    let palette: Palette
    let type: Typography
    let scale: Double
    @State private var dotOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 32) {
            WalkingDotHero(palette: palette)
                .frame(width: 240, height: 100)

            VStack(spacing: 6) {
                Text("Welcome to")
                    .font(type.display(44 * scale, weight: .semibold))
                    .kerning(-1)
                    .foregroundStyle(palette.ink)

                Text("Amble")
                    .font(type.display(52 * scale, weight: .semibold))
                    .italic()
                    .kerning(-0.5)
                    .foregroundStyle(palette.ink)
            }
            .multilineTextAlignment(.center)

            Text("A kind companion for your daily walks. Let's set things up together. Just a few questions.")
                .font(type.body(19 * scale, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.ink2)
                .lineSpacing(4)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct WalkingDotHero: View {
    let palette: Palette

    // Drawing canvas: 240 x 100. The path coords are padded 35 / 30 from edges
    // so the 22px dot + up to 14px halo never clips at either end.
    private static let canvasSize = CGSize(width: 240, height: 100)

    // Path control points, in the same coordinate space as PathShape.
    // Shifted +20, +15 from the original design so the halo breathes on all sides.
    private static let p0 = CGPoint(x: 35,  y: 65)
    private static let c1 = CGPoint(x: 70,  y: 33)
    private static let p1 = CGPoint(x: 115, y: 50)
    // SVG T reflects previous control about current end: 2·p1 − c1 = (160, 67)
    private static let c2 = CGPoint(x: 160, y: 67)
    private static let p2 = CGPoint(x: 205, y: 50)

    /// 240 points sampled along the full two-quadratic path, re-parameterized
    /// so that consecutive points are equidistant by arc length.
    /// With TimelineView driving redraws at display refresh, the dot glides
    /// at visually constant speed and stays exactly on the curve.
    private static let samples: [CGPoint] = buildArcLengthSamples()

    private static func buildArcLengthSamples() -> [CGPoint] {
        // 1. Dense raw sampling of both halves by parameter t ∈ [0,1]
        let dense = 600
        var raw: [CGPoint] = []
        raw.reserveCapacity(dense + 1)
        for i in 0...dense {
            let t = Double(i) / Double(dense)
            raw.append(rawPoint(at: t))
        }
        // 2. Cumulative arc length
        var cum: [Double] = [0]
        cum.reserveCapacity(raw.count)
        var total: Double = 0
        for i in 1..<raw.count {
            let dx = raw[i].x - raw[i-1].x
            let dy = raw[i].y - raw[i-1].y
            total += hypot(dx, dy)
            cum.append(total)
        }
        guard total > 0 else { return raw }
        // 3. Re-sample uniformly by arc length
        let out = 240
        var pts: [CGPoint] = []
        pts.reserveCapacity(out)
        var j = 1
        for k in 0..<out {
            let target = Double(k) / Double(out - 1) * total
            while j < cum.count && cum[j] < target { j += 1 }
            let i = min(max(j, 1), cum.count - 1)
            let a = cum[i - 1], b = cum[i]
            let f = b > a ? (target - a) / (b - a) : 0
            let x = raw[i-1].x + (raw[i].x - raw[i-1].x) * f
            let y = raw[i-1].y + (raw[i].y - raw[i-1].y) * f
            pts.append(CGPoint(x: x, y: y))
        }
        return pts
    }

    private static func rawPoint(at t: Double) -> CGPoint {
        // Evaluate a piecewise-quadratic made of two segments, joined at t=0.5.
        if t <= 0.5 {
            let u = t / 0.5
            return quad(p0, c1, p1, u: u)
        } else {
            let u = (t - 0.5) / 0.5
            return quad(p1, c2, p2, u: u)
        }
    }

    private static func quad(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, u: Double) -> CGPoint {
        let mu = 1 - u
        let x = mu * mu * a.x + 2 * mu * u * c.x + u * u * b.x
        let y = mu * mu * a.y + 2 * mu * u * c.y + u * u * b.y
        return CGPoint(x: x, y: y)
    }

    /// Duration of one full there-and-back cycle, in seconds.
    private let period: Double = 4.5

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let phase = elapsed.truncatingRemainder(dividingBy: period) / period
            // −cos maps phase ∈ [0,1] → s ∈ [0,1,0], with smooth sine easing
            // at both reversals. Combined with arc-length samples this gives
            // truly on-curve, constant-speed motion with natural turnarounds.
            let s = 0.5 - 0.5 * cos(phase * 2 * .pi)
            let idx = Int(round(s * Double(Self.samples.count - 1)))
            let pos = Self.samples[min(max(idx, 0), Self.samples.count - 1)]

            // Halo pulses on its own 1.8s cycle so it doesn't perfectly sync.
            let haloPulse = 0.5 + 0.5 * sin(elapsed * 2 * .pi / 1.8)
            let haloExtra: CGFloat = CGFloat(haloPulse * 14)

            ZStack {
                PathShape()
                    .stroke(palette.ringTrack,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 8]))

                Circle()
                    .fill(palette.accent.opacity(0.22))
                    .frame(width: 22 + haloExtra, height: 22 + haloExtra)
                    .position(pos)

                Circle()
                    .fill(palette.accent)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(0.45))
                            .frame(width: 10, height: 10)
                            .offset(x: -3, y: -3)
                    )
                    .shadow(color: palette.accent.opacity(0.35), radius: 6, x: 0, y: 2)
                    .position(pos)
            }
            .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .drawingGroup()
    }

    struct PathShape: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: WalkingDotHero.p0)
            p.addQuadCurve(to: WalkingDotHero.p1, control: WalkingDotHero.c1)
            p.addQuadCurve(to: WalkingDotHero.p2, control: WalkingDotHero.c2)
            return p
        }
    }
}

// MARK: Step — Name
private struct StepName: View {
    @Bindable var state: OnboardingState
    let palette: Palette
    let type: Typography
    let scale: Double
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What should we\ncall you?")
                .font(type.display(36 * scale, weight: .semibold))
                .kerning(-0.8)
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .padding(.top, 20)
                .padding(.bottom, 10)

            Text("Your first name is fine.")
                .font(type.body(17 * scale, weight: .medium))
                .foregroundStyle(palette.ink2)
                .padding(.bottom, 32)

            TextField("Your first name", text: $state.name)
                .font(type.display(28 * scale, weight: .semibold))
                .foregroundStyle(palette.ink)
                .padding(.vertical, 18)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(palette.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(focused ? palette.accent : palette.ringTrack, lineWidth: 2)
                        )
                )
                .focused($focused)
                .submitLabel(.done)

            Spacer()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true }
        }
    }
}

// MARK: Step — Age
private struct StepAge: View {
    @Bindable var state: OnboardingState
    let palette: Palette
    let type: Typography
    let scale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How old\nare you?")
                .font(type.display(36 * scale, weight: .semibold))
                .kerning(-0.8)
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .padding(.top, 20)
                .padding(.bottom, 10)

            Text("We use this to suggest a daily goal that feels right for you.")
                .font(type.body(17 * scale, weight: .medium))
                .foregroundStyle(palette.ink2)
                .padding(.bottom, 28)

            VStack(spacing: 22) {
                Text("\(state.age)")
                    .font(type.display(96 * scale, weight: .semibold))
                    .kerning(-3)
                    .foregroundStyle(palette.accent)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring, value: state.age)

                Text("years young")
                    .font(type.body(17 * scale, weight: .medium))
                    .foregroundStyle(palette.ink2)

                HStack(spacing: 16) {
                    StepperButton(palette: palette, symbol: "−") {
                        state.age = max(50, state.age - 1)
                    }
                    StepperButton(palette: palette, symbol: "+") {
                        state.age = min(110, state.age + 1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(palette.card)
                    .shadow(color: .black.opacity(0.05), radius: 18, x: 0, y: 6)
            )

            Spacer()
        }
    }
}

// MARK: Step — Mobility
private struct StepMobility: View {
    @Bindable var state: OnboardingState
    let palette: Palette
    let type: Typography
    let scale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How do you\nget around?")
                .font(type.display(36 * scale, weight: .semibold))
                .kerning(-0.8)
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .padding(.top, 20)
                .padding(.bottom, 10)

            Text("We'll tailor your daily goal to match.")
                .font(type.body(17 * scale, weight: .medium))
                .foregroundStyle(palette.ink2)
                .padding(.bottom, 28)

            VStack(spacing: 10) {
                ForEach(Mobility.allCases, id: \.self) { m in
                    ChoiceRow(
                        title: m.label, sub: m.sub,
                        selected: state.mobility == m,
                        palette: palette, type: type, scale: scale
                    ) {
                        state.mobility = m
                        state.recomputeGoal()
                    }
                }
            }
            Spacer()
        }
    }
}

// MARK: Step — Activity
private struct StepActivity: View {
    @Bindable var state: OnboardingState
    let palette: Palette
    let type: Typography
    let scale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How active\nare you?")
                .font(type.display(36 * scale, weight: .semibold))
                .kerning(-0.8)
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .padding(.top, 20)
                .padding(.bottom, 10)

            Text("We'll build your goal from here.")
                .font(type.body(17 * scale, weight: .medium))
                .foregroundStyle(palette.ink2)
                .padding(.bottom, 28)

            VStack(spacing: 10) {
                ForEach(ActivityLevel.allCases, id: \.self) { a in
                    ChoiceRow(
                        title: a.label, sub: a.sub,
                        selected: state.activity == a,
                        palette: palette, type: type, scale: scale
                    ) {
                        state.activity = a
                        state.recomputeGoal()
                    }
                }
            }
            Spacer()
        }
    }
}

// MARK: Step — Gender
private struct StepGender: View {
    @Bindable var state: OnboardingState
    let palette: Palette
    let type: Typography
    let scale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Are you a man\nor a woman?")
                .font(type.display(36 * scale, weight: .semibold))
                .kerning(-0.8)
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .padding(.top, 20)
                .padding(.bottom, 10)

            Text("The daily averages differ slightly. We'll adjust for that.")
                .font(type.body(17 * scale, weight: .medium))
                .foregroundStyle(palette.ink2)
                .padding(.bottom, 28)

            VStack(spacing: 10) {
                ForEach(Gender.allCases, id: \.self) { g in
                    ChoiceRow(
                        title: g.label, sub: nil,
                        selected: state.gender == g,
                        palette: palette, type: type, scale: scale
                    ) {
                        state.gender = g
                        state.recomputeGoal()
                    }
                }
            }
            Spacer()
        }
    }
}

// MARK: Shared — Choice row used by Mobility / Activity / Gender
private struct ChoiceRow: View {
    let title: String
    let sub: String?
    let selected: Bool
    let palette: Palette
    let type: Typography
    let scale: Double
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { action() }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(type.display(20 * scale, weight: .bold))
                        .kerning(-0.3)
                        .foregroundStyle(selected ? .white : palette.ink)
                    if let sub {
                        Text(sub)
                            .font(type.body(14 * scale, weight: .medium))
                            .foregroundStyle(selected ? .white.opacity(0.9) : palette.ink2)
                    }
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(selected ? Color.white : palette.ringTrack, lineWidth: 2)
                        .frame(width: 26, height: 26)
                    if selected {
                        Circle().fill(.white).frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.accent)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(selected ? palette.accent : palette.card)
                    .shadow(color: selected ? palette.accent.opacity(0.3) : .black.opacity(0.04),
                            radius: selected ? 14 : 4, x: 0, y: selected ? 6 : 2)
            )
        }
        .buttonStyle(.pressable)
        // Combined "Title, sub" announcement plus selected state. Skips
        // the decorative checkmark glyph so VoiceOver doesn't tack on
        // "checkmark" after each row.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sub.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// Builds an AttributedString for the goal-suggestion line with the step
// count colored + bold inline. Replaces the old `Text + Text + Text`
// composition, which was deprecated in iOS 26.
private func goalPrompt(suggestedSteps: Int, palette: Palette, type: Typography, scale: Double) -> AttributedString {
    let stepsStr = "\(StepFormat.int(suggestedSteps)) steps"
    var attr = AttributedString("Based on your inputs, we suggest \(stepsStr). That's the range where the research shows the biggest benefit for someone like you.")
    if let range = attr.range(of: stepsStr) {
        attr[range].foregroundColor = palette.accent
        attr[range].font = type.body(16 * scale, weight: .bold)
    }
    return attr
}

// MARK: Step — Goal
private struct StepGoal: View {
    @Bindable var state: OnboardingState
    let palette: Palette
    let type: Typography
    let scale: Double

    private let options: [Int] = [1000, 2000, 3000, 5000, 7000, 10000]
    private let labels: [Int: String] = [
        1000: "Starter", 2000: "Easy", 3000: "Gentle", 5000: "Steady", 7000: "Active", 10000: "Strong"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your daily\nstep goal")
                .font(type.display(36 * scale, weight: .semibold))
                .kerning(-0.8)
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .padding(.top, 20)
                .padding(.bottom, 10)

            let suggested = UserProfile.suggestedGoal(
                age: state.age, mobility: state.mobility,
                activity: state.activity, gender: state.gender
            )
            Text(goalPrompt(suggestedSteps: suggested, palette: palette, type: type, scale: scale))
                .font(type.body(16 * scale, weight: .medium))
                .foregroundStyle(palette.ink2)
                .lineSpacing(3)
                .padding(.bottom, 24)

            VStack(spacing: 6) {
                Text(StepFormat.int(state.goal))
                    .font(type.display(56 * scale, weight: .semibold))
                    .kerning(-1.5)
                    .foregroundStyle(palette.accent)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.spring, value: state.goal)
                Text(labels[state.goal] ?? "Custom")
                    .font(type.body(17 * scale, weight: .semibold))
                    .foregroundStyle(palette.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(palette.card)
                    .shadow(color: .black.opacity(0.05), radius: 18, x: 0, y: 6)
            )

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(options, id: \.self) { o in
                    let selected = state.goal == o
                    Button {
                        Haptics.select()
                        state.goal = o
                    } label: {
                        VStack(spacing: 3) {
                            Text(o >= 1000 ? "\(o/1000)k" : "\(o)")
                                .font(type.display(15 * scale, weight: .bold))
                            Text(labels[o] ?? "")
                                .font(type.body(10 * scale, weight: .medium))
                                .opacity(0.85)
                        }
                        .foregroundStyle(selected ? .white : palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(selected ? palette.accent : palette.card)
                                .shadow(color: selected ? palette.accent.opacity(0.4) : .black.opacity(0.04),
                                        radius: selected ? 10 : 2, x: 0, y: selected ? 4 : 1)
                        )
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.top, 16)

            Spacer()
        }
        .onAppear { state.recomputeGoal() }
    }
}

// MARK: Step — Contact
private struct StepContact: View {
    @Bindable var state: OnboardingState
    let palette: Palette
    let type: Typography
    let scale: Double
    @State private var showPicker = false
    @State private var showRolePicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Who would you call\nif you needed help?")
                    .font(type.display(36 * scale, weight: .semibold))
                    .kerning(-0.8)
                    .foregroundStyle(palette.ink)
                    .lineSpacing(2)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                Text("One trusted person for emergencies. We'll never share their info.")
                    .font(type.body(17 * scale, weight: .medium))
                    .foregroundStyle(palette.ink2)
                    .padding(.bottom, 20)

                Button {
                    Haptics.tap()
                    showPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(palette.accent)
                        Text("Pick from Contacts")
                            .font(type.display(17 * scale, weight: .semibold))
                            .foregroundStyle(palette.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.ink2)
                    }
                    .padding(.vertical, 16).padding(.horizontal, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(palette.card)
                            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
                    )
                }
                .buttonStyle(.pressable)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Pick from Contacts")
                .accessibilityHint("Opens your iPhone's contact picker.")
                .accessibilityAddTraits(.isButton)
                .padding(.bottom, 14)

                TextField("Their name", text: $state.contactName)
                    .textContentType(.name)
                    .font(type.display(22 * scale, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .padding(.vertical, 16).padding(.horizontal, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(palette.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(palette.ringTrack, lineWidth: 2)
                            )
                    )
                    .padding(.bottom, 12)

                TextField("Phone number", text: $state.contactPhone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .font(type.display(22 * scale, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .padding(.vertical, 16).padding(.horizontal, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(palette.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(palette.ringTrack, lineWidth: 2)
                            )
                    )
                    .padding(.bottom, 20)

                Button {
                    Haptics.tap()
                    showRolePicker = true
                } label: {
                    let roleTint = RelationMeta.tint(for: state.contactRole, palette: palette)
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(state.contactRole.isEmpty ? palette.soft : roleTint.opacity(0.15))
                            Image(systemName: RelationMeta.icon(for: state.contactRole))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(state.contactRole.isEmpty ? palette.accent : roleTint)
                        }
                        .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.contactRole.isEmpty ? "Their relation to you" : state.contactRole)
                                .font(type.display(20 * scale, weight: .semibold))
                                .foregroundStyle(palette.ink)
                            if state.contactRole.isEmpty {
                                Text("Tap to choose")
                                    .font(type.body(13 * scale, weight: .medium))
                                    .foregroundStyle(palette.ink)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.ink2)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        state.contactRole.isEmpty
                            ? "Their relation to you, not yet chosen"
                            : "Their relation to you, \(state.contactRole)"
                    )
                    .accessibilityHint("Opens a list of relations to choose from.")
                    .accessibilityAddTraits(.isButton)
                    .padding(.vertical, 14).padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(palette.card)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(palette.ringTrack, lineWidth: 2)
                            )
                    )
                }
                .buttonStyle(.pressable)
            }
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showPicker) {
            ContactPicker(
                onPick: { name, phone in
                    state.contactName = name
                    state.contactPhone = phone
                    showPicker = false
                },
                onCancel: { showPicker = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showRolePicker) {
            RelationPickerSheet(
                palette: palette, type: type, scale: scale,
                roles: RelationMeta.allRoles, selected: state.contactRole
            ) { r in
                state.contactRole = r
                showRolePicker = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: Relation icons + picker sheet

enum RelationMeta {
    /// Canonical ordered list of relations. Kept in one place so the
    /// onboarding picker and the settings edit sheet stay in sync —
    /// adding a new relation means updating this list only.
    static let allRoles: [String] = [
        "Daughter", "Son", "Granddaughter", "Grandson",
        "Partner", "Friend", "Neighbor", "Caregiver"
    ]

    /// Simple, reliable SF Symbols that render cleanly at 20pt.
    static func icon(for role: String) -> String {
        switch role {
        case "Daughter", "Son":            return "person.fill"
        case "Granddaughter", "Grandson":  return "figure.child"
        case "Partner":                    return "heart.fill"
        case "Friend":                     return "hand.wave.fill"
        case "Neighbor":                   return "house.fill"
        case "Caregiver":                  return "cross.case.fill"
        default:                           return "person.crop.circle"
        }
    }

    /// Subject pronoun inferred from the relation. Daughters/granddaughters
    /// are "she", sons/grandsons are "he". Partner / Friend / Neighbor /
    /// Caregiver don't imply a gender, so we stay with singular-they rather
    /// than guess. Used in copy like "so [he / she / they] can find you".
    static func subjectPronoun(for role: String) -> String {
        switch role {
        case "Daughter", "Granddaughter":  return "she"
        case "Son", "Grandson":            return "he"
        default:                           return "they"
        }
    }

    /// Each relation gets a distinct, palette-independent tint so the picker
    /// reads as a set of individuals at a glance. Colors stay within the
    /// earthy/muted range of the app's three palettes so nothing screams.
    static func tint(for role: String, palette: Palette) -> Color {
        switch role {
        case "Daughter":       return Color(hex: 0xB56478)  // dusty rose
        case "Son":            return Color(hex: 0x4A6A8A)  // slate navy
        case "Granddaughter":  return Color(hex: 0xD88A7B)  // soft coral
        case "Grandson":       return Color(hex: 0x7A9A5C)  // olive green
        case "Partner":        return Color(hex: 0xC0392B)  // heart red
        case "Friend":         return Color(hex: 0xC8A24E)  // warm mustard
        case "Neighbor":       return Color(hex: 0xC5622C)  // terracotta
        case "Caregiver":      return Color(hex: 0x3E7F7A)  // medical teal
        default:               return palette.ink2
        }
    }
}

/// Shared role-picker sheet used by both the onboarding Contact step
/// and the settings Emergency-contact edit sheet. Centralising the
/// picker means any visual tweak shows up in both places automatically.
struct RelationPickerSheet: View {
    let palette: Palette
    let type: Typography
    let scale: Double
    let roles: [String]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Their relation")
                    .font(type.display(28 * scale, weight: .semibold))
                    .kerning(-0.5)
                    .foregroundStyle(palette.ink)
                Text("How do you know them?")
                    .font(type.body(15 * scale, weight: .medium))
                    .foregroundStyle(palette.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 22)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(roles, id: \.self) { r in
                        RelationRow(
                            role: r, selected: selected == r,
                            palette: palette, type: type, scale: scale
                        ) {
                            Haptics.select()
                            onSelect(r)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(palette.bg)
    }
}

struct RelationRow: View {
    let role: String
    let selected: Bool
    let palette: Palette
    let type: Typography
    let scale: Double
    let action: () -> Void

    var body: some View {
        let tint = RelationMeta.tint(for: role, palette: palette)
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(tint.opacity(0.15))
                    Image(systemName: RelationMeta.icon(for: role))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 42, height: 42)

                Text(role)
                    .font(type.display(19 * scale, weight: .semibold))
                    .kerning(-0.2)
                    .foregroundStyle(palette.ink)

                Spacer()

                ZStack {
                    Circle()
                        .stroke(selected ? palette.accent : palette.ringTrack, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if selected {
                        Circle().fill(palette.accent).frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? palette.soft : palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(selected ? palette.accent.opacity(0.35) : .clear, lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(selected ? 0.05 : 0.03),
                            radius: selected ? 6 : 4, x: 0, y: selected ? 2 : 1)
            )
        }
        .buttonStyle(.pressable)
        // Reuse the role text as the VoiceOver label so we don't
        // double-announce "Spouse, button" plus the decorative
        // checkmark glyph. `.isSelected` surfaces the selection
        // state explicitly.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(role)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: Step — Location (share with emergency contact during SOS)

/// Primes the user for the iOS When-In-Use location dialog. Placed directly
/// after the Contact step so the ask lands in context: "I just told Amble
/// who to call in an emergency, now it's asking if it may also share my
/// location with that person." Keeping this off the SOS screen itself is
/// critical — we never want iOS's permission sheet racing a tel:// prompt
/// during an actual emergency.
private struct StepLocation: View {
    let palette: Palette
    let type: Typography
    let scale: Double
    let location: LocationManager
    /// Trusted contact's first name, for copy. Empty-string if somehow not set.
    let contactFirstName: String
    /// Relation role ("Daughter", "Son", "Friend", …) picked on the previous
    /// step. Used to infer a gendered pronoun for the subtitle when the role
    /// makes the gender unambiguous; otherwise we fall back to singular-they.
    let contactRole: String

    private var granted: Bool { location.isAuthorized }
    private var determined: Bool { location.isDetermined }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Share your location\nin an emergency")
                .font(type.display(36 * scale, weight: .semibold))
                .kerning(-0.8)
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .padding(.top, 20)
                .padding(.bottom, 14)

            Text(subtitle)
                .font(type.body(17 * scale, weight: .medium))
                .foregroundStyle(palette.ink2)
                .lineSpacing(4)
                .padding(.bottom, 28)

            HStack(spacing: 14) {
                IconBadge(symbol: "location.fill", tint: palette.accent, palette: palette)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Location")
                        .font(type.display(17 * scale, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text("Only shared when you press SOS")
                        .font(type.body(14 * scale, weight: .medium))
                        .foregroundStyle(palette.ink2)
                }
                Spacer()
                if granted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.positive)
                        .font(.system(size: 22, weight: .semibold))
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.card))

            Spacer()
            // "Maybe later" skip option removed per App Review feedback
            // (Apple Submission 98bfe2fa, Apr 28 2026, Guideline
            // 5.1.1(iv)). After the priming explainer the user must
            // always proceed to the iOS system permission dialog —
            // they can deny it there. Recovery affordances exist
            // post-onboarding (the "Allow step tracking" home card,
            // the location-denied row in Settings) for users who
            // declined and later changed their mind.
        }
    }

    private var subtitle: String {
        if contactFirstName.isEmpty {
            return "When you press SOS, Amble will include your location in the message to your emergency contact so they can find you quickly. It's never shared otherwise."
        }
        let pronoun = RelationMeta.subjectPronoun(for: contactRole)
        return "When you press SOS, Amble will include your location in the message to \(contactFirstName) so \(pronoun) can find you quickly. It's never shared otherwise."
    }
}

// MARK: Step — Health (share steps)

/// Primes the user for the HealthKit + Motion dialogs that come right after
/// they tap the primary button. Keeping this on its own step means the iOS
/// prompts appear with context ("oh, right, I asked for this") rather than
/// jumping in during an unrelated question like name entry.
private struct StepHealth: View {
    let palette: Palette
    let type: Typography
    let scale: Double
    let health: HealthStore

    /// Re-read on each appearance so the checkmarks reflect the user's
    /// choice after they return from the iOS permission dialogs.
    @State private var motionGranted: Bool = false

    private var healthGranted: Bool {
        health.authorizationDetermined && health.authorized
    }

    private var allGranted: Bool {
        healthGranted && motionGranted
    }

    private func refreshMotionStatus() {
        motionGranted = CMPedometer.authorizationStatus() == .authorized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Share your\nsteps with Amble")
                .font(type.display(36 * scale, weight: .semibold))
                .kerning(-0.8)
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .padding(.top, 20)
                .padding(.bottom, 14)

            Text("Amble reads your step count from Apple Health. This information stays on your phone. We never send it anywhere.")
                .font(type.body(17 * scale, weight: .medium))
                .foregroundStyle(palette.ink2)
                .lineSpacing(4)
                .padding(.bottom, 28)

            HStack(spacing: 14) {
                IconBadge(symbol: "heart.text.square", tint: palette.accent, palette: palette)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Health")
                        .font(type.display(17 * scale, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text("Your daily step count")
                        .font(type.body(14 * scale, weight: .medium))
                        .foregroundStyle(palette.ink2)
                }
                Spacer()
                if healthGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.positive)
                        .font(.system(size: 22, weight: .semibold))
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.card))
            .padding(.bottom, 10)

            HStack(spacing: 14) {
                IconBadge(symbol: "figure.walk.motion", tint: palette.accent2, palette: palette)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Motion")
                        .font(type.display(17 * scale, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text("So Amble can walk with you")
                        .font(type.body(14 * scale, weight: .medium))
                        .foregroundStyle(palette.ink2)
                }
                Spacer()
                if motionGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.positive)
                        .font(.system(size: 22, weight: .semibold))
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.card))

            Spacer()
            // "Maybe later" skip option removed per App Review
            // feedback. See StepLocation comment for context.
        }
        .onAppear { refreshMotionStatus() }
        // Re-check when HealthKit auth state flips — the two dialogs appear
        // in sequence, so Motion's result lands right after HealthKit's.
        .onChange(of: health.authorizationDetermined) { _, _ in refreshMotionStatus() }
    }
}

// MARK: Step — Notify (daily reminder)

private struct StepNotify: View {
    let palette: Palette
    let type: Typography
    let scale: Double
    let notifications: NotificationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("A gentle\nreminder?")
                .font(type.display(36 * scale, weight: .semibold))
                .kerning(-0.8)
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
                .padding(.top, 20)
                .padding(.bottom, 14)

            Text("One soft notification a day when it's a lovely time for a walk. That's all. We won't bother you otherwise.")
                .font(type.body(17 * scale, weight: .medium))
                .foregroundStyle(palette.ink2)
                .lineSpacing(4)
                .padding(.bottom, 28)

            HStack(spacing: 14) {
                IconBadge(symbol: "bell.fill", tint: palette.accent2, palette: palette)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily walking reminder")
                        .font(type.display(17 * scale, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text("You can change the time in the app settings.")
                        .font(type.body(14 * scale, weight: .medium))
                        .foregroundStyle(palette.ink2)
                }
                Spacer()
                if notifications.authorized {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.positive)
                        .font(.system(size: 22, weight: .semibold))
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.card))

            Spacer()
            // "Maybe later" skip option removed per App Review
            // feedback. See StepLocation comment for context.
        }
    }
}

// MARK: Shared permission-step bits

private struct IconBadge: View {
    let symbol: String
    let tint: Color
    let palette: Palette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.15))
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 44, height: 44)
    }
}


// MARK: Step — Done
// Renders the closing sentence with "Amble" in the display (Fraunces)
// italic face while the rest stays in the body font.
private func doneMessage(goal: Int, type: Typography, scale: Double) -> AttributedString {
    var attr = AttributedString("Your daily goal is \(StepFormat.int(goal)) steps. We hope you enjoy your walks with Amble.")
    if let range = attr.range(of: "Amble") {
        attr[range].font = type.display(19 * scale, weight: .semibold).italic()
    }
    return attr
}

private struct StepDone: View {
    @Bindable var state: OnboardingState
    let palette: Palette
    let type: Typography
    let scale: Double
    @State private var appear = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            // Renders the bare Fraunces "A" glyph directly on the
            // screen. We use a dedicated `OnboardingIcon` asset
            // (sage "A" on cream, no surrounding container) rather
            // than the real AppIcon — the AppIcon is sage-on-cream-
            // inverted (cream "A" on sage) so it survives iOS 26's
            // home-screen Liquid Glass treatment, which would clash
            // visually with the cream onboarding background here.
            Image("OnboardingIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 170, height: 170)
                // App icon pops in with a scale spring — a small
                // celebratory beat after the container's slide-in
                // transition settles.
                .scaleEffect(appear ? 1 : 0.5)
                .animation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.15), value: appear)

            Text("All set, \(state.name.isEmpty ? "friend" : state.name).")
                .font(type.display(40 * scale, weight: .semibold))
                .multilineTextAlignment(.center)
                .kerning(-0.8)
                .foregroundStyle(palette.ink)

            Text(doneMessage(goal: state.goal, type: type, scale: scale))
                .font(type.body(19 * scale, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.ink2)
                .lineSpacing(4)
            Spacer()
        }
        .onAppear {
            appear = true
            Haptics.success()
        }
    }
}


// MARK: Step — Paywall (the ADDITIONAL screen at the end)
private struct StepPaywall: View {
    let palette: Palette
    let type: Typography
    let scale: Double
    let store: StoreManager
    let onFinish: () -> Void

    @State private var appear = false
    /// Surfaces only non-success Restore outcomes. A successful
    /// restore here unlocks the app via `store.hasAccess`, which
    /// the parent `OnboardingFlow` watches to advance off this
    /// step — no alert needed because the visible navigation IS
    /// the feedback.
    @State private var restoreOutcome: RestoreOutcome?

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 14) {
                Text("Try _Amble_ free\nfor 7 days.")
                    .font(type.display(40 * scale, weight: .semibold))
                    .kerning(-0.9)
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                Text("Pick the plan that suits you. Cancel any time.")
                    .font(type.body(18 * scale, weight: .medium))
                    .foregroundStyle(palette.ink2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 6)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 14)
            .animation(.easeOut(duration: 0.55), value: appear)

            Spacer(minLength: 0)

            // Plan chooser. Yearly card carries the trial promise
            // because the App Store Connect product has the 7-day
            // intro offer attached; monthly does not (Apple gates
            // the trial to one redemption per subscription group,
            // so doubling it on monthly would just split the same
            // single offer between products and confuse users).
            VStack(spacing: 12) {
                yearlyButton
                monthlyButton
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 14)
            .animation(.easeOut(duration: 0.55).delay(0.1), value: appear)

            PaywallLegal(palette: palette, type: type, scale: scale,
                         store: store,
                         onRestore: handleRestore)
                .padding(.top, 18)
                .padding(.bottom, 12)
                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.2), value: appear)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            appear = true
            // Edge case: a returning user who reaches this step
            // already has access (e.g. they reinstalled and a
            // background Restore silently succeeded, or they're
            // a Family Sharing dependent already covered). Skip
            // the paywall straight to the home screen rather than
            // making them tap something redundant.
            if store.hasAccess {
                onFinish()
            }
        }
        .alert(
            restoreOutcome?.alertTitle ?? "",
            isPresented: Binding(
                get: { restoreOutcome != nil },
                set: { if !$0 { restoreOutcome = nil } }
            ),
            presenting: restoreOutcome
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { outcome in
            Text(outcome.alertMessage)
        }
    }

    // MARK: - Buttons

    /// Primary CTA. The trial promise lives here, where it's most
    /// motivating — the user is one tap from starting walks.
    private var yearlyButton: some View {
        Button {
            Haptics.medium()
            handlePurchase(.annual)
        } label: {
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Start 7-day free trial")
                        .font(type.display(20 * scale, weight: .bold))
                        .kerning(-0.2)
                    if let saving = store.yearlyDiscountLabel {
                        Text(saving)
                            .font(type.body(13 * scale, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Color.white.opacity(0.18))
                            )
                    }
                }
                Text("Then \(store.annualPrice) a year · \(store.annualMonthlyEquivalent) a month")
                    .font(type.body(14 * scale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(palette.accent)
            )
            .shadow(color: palette.accent.opacity(0.4), radius: 16, x: 0, y: 6)
        }
        .buttonStyle(.pressable)
        .disabled(store.purchasing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Start 7-day free trial. Then \(store.annualPrice) a year, about \(store.annualMonthlyEquivalent) a month.")
        .accessibilityHint("Subscribes you yearly with a 7-day free trial.")
        .accessibilityAddTraits(.isButton)
    }

    /// Secondary CTA. No trial — straight to monthly billing.
    /// Visually quieter than the yearly so the recommended path
    /// reads first.
    private var monthlyButton: some View {
        Button {
            Haptics.medium()
            handlePurchase(.monthly)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Subscribe monthly")
                    .font(type.display(18 * scale, weight: .semibold))
                    .kerning(-0.2)
                Spacer()
                Text("\(store.monthlyPrice) a month")
                    .font(type.body(15 * scale, weight: .medium))
            }
            .foregroundStyle(palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.pressable)
        .disabled(store.purchasing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Subscribe monthly, \(store.monthlyPrice) a month")
        .accessibilityHint("Subscribes you monthly. No free trial.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Handlers

    private func handlePurchase(_ plan: StoreManager.PurchasePlan) {
        Task {
            let outcome = await store.purchase(plan)
            switch outcome {
            case .granted:
                onFinish()
            case .cancelled:
                // User dismissed the StoreKit sheet — stay on the
                // paywall, they can tap again or pick the other
                // plan. Critically we do NOT fall through to the
                // DEBUG escape hatch here: a cancel is "not now,"
                // not a configuration failure.
                break
            case .failed:
                #if DEBUG
                // Dev escape hatch: StoreKit testing can silently no-op
                // in the simulator if the scheme's StoreKit config
                // isn't loaded (e.g. when launched via `simctl launch`
                // instead of ⌘R, or if there's no signed-in test
                // account), and on a real device this can fire if the
                // RevenueCat dashboard isn't fully wired up yet. Let
                // the dev proceed so they can test the rest of the
                // app — never reachable in a Release build.
                print("[Amble] Purchase failed; granting DEBUG access to continue onboarding.")
                store.isDebugUnlocked = true
                onFinish()
                #endif
            }
        }
    }

    private func handleRestore() {
        Task {
            let outcome = await store.restore()
            if outcome != .restored {
                restoreOutcome = outcome
            }
            // On `.restored`, hasAccess flipped true; the parent
            // OnboardingFlow doesn't auto-advance off this step,
            // so we explicitly finish here.
            if outcome == .restored {
                onFinish()
            }
        }
    }
}

/// Legal footer required by Apple Guideline 3.1.2 for auto-renewing
/// subscriptions: renewal disclosure for every plan offered, Terms,
/// Privacy, and Restore. With two plans (yearly + monthly) the
/// disclosure has to enumerate both — Apple specifically requires
/// each subscription's price + period to be disclosed adjacent to
/// the buy button.
struct PaywallLegal: View {
    let palette: Palette
    let type: Typography
    let scale: Double
    /// Read directly so we can render live prices for both the
    /// yearly and monthly products. Falls back to the hard-coded
    /// defaults in StoreManager if RevenueCat hasn't returned the
    /// prices yet.
    let store: StoreManager
    /// `true` only on the onboarding paywall, where the user is
    /// almost certainly trial-eligible and the yearly button
    /// promises a 7-day free trial. Adds the "payment after trial"
    /// preamble required by App Review when a free trial is
    /// advertised. The trial-end PaywallView passes `false`.
    var mentionsTrial: Bool = true
    let onRestore: () -> Void

    // Terms URL points to Apple's Standard EULA — accepted by App
    // Review for any auto-renewing subscription that doesn't need
    // app-specific provisions. Override here if we ever add a custom
    // EULA in App Store Connect.
    // Privacy URL hosts our own policy (Apple does not provide a
    // default for privacy). Update both the App Store Connect
    // "Privacy Policy URL" field and this constant in lockstep if
    // the page ever moves.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://antoniobaltic.xyz/amble-privacy.html")!

    private var disclosure: String {
        let yearly = store.annualPrice
        let monthly = store.monthlyPrice
        let core = "Yearly auto-renews at \(yearly) a year. Monthly auto-renews at \(monthly) a month. Cancel anytime in your phone settings."
        if mentionsTrial {
            return "Payment charged to your Apple Account at the end of the free trial. \(core)"
        }
        return core
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(disclosure)
                .font(type.body(11 * scale, weight: .medium))
                .foregroundStyle(palette.ink2.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 20)

            HStack(spacing: 20) {
                Button {
                    Haptics.tap()
                    onRestore()
                } label: {
                    Text("Restore")
                }
                .buttonStyle(.pressable)

                Link("Terms", destination: Self.termsURL)
                Link("Privacy", destination: Self.privacyURL)
            }
            .font(type.body(13 * scale, weight: .semibold))
            .foregroundStyle(palette.ink2)
        }
    }
}
