import SwiftUI
import Lottie

struct ActiveWalkView: View {
    let palette: Palette
    let type: Typography
    let scale: Double
    let userName: String
    let contactFirstName: String
    let hasContact: Bool
    let tracker: WalkTracker
    let onMinimize: () -> Void
    let onEnd: () -> Void
    let onCall: () -> Void
    let onSOS: () -> Void

    @State private var breathe = false
    @State private var ending = false

    var body: some View {
        ZStack {
            palette.bg.ignoresSafeArea()

            // Soft top glow so the active-walk state feels distinct from the
            // rest of the app without going dark or clinical.
            RadialGradient(
                colors: [palette.accent.opacity(0.14), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 340
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, 62)
                    .padding(.horizontal, 20)

                Spacer(minLength: 0)

                walkingIcon
                    .padding(.bottom, 20)

                elapsedCard
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)

                stepsCard
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                safetyRow
                    .padding(.horizontal, 24)

                Spacer(minLength: 0)

                endButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .onAppear { breathe = true }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            // Invisible 44pt block on the left to balance the minimize
            // button on the right, so the leaf+text column sits perfectly
            // centered on the screen.
            Color.clear.frame(width: 44, height: 44)

            Spacer(minLength: 0)

            // Re-renders every 30s so the line can cross into a new
            // phase. WalkEncouragement is stable per-phase so it
            // doesn't flicker while the walk ticks forward within
            // the same bucket.
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(encouragementText)
                    .font(type.display(19 * scale, weight: .regular).italic())
                    .foregroundStyle(palette.ink2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    // Shallow breath (0.82 → 1.0) on the same 2.4s
                    // cycle as the walking icon below. Reads as alive
                    // without looking like the text is fading out.
                    .opacity(breathe ? 1.0 : 0.82)
                    .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: breathe)
            }
            .padding(.top, 12)

            Spacer(minLength: 0)

            Button {
                Haptics.tap()
                onMinimize()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(palette.card))
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Minimize")
            .accessibilityHint("Returns to the home screen. Your walk keeps tracking.")
        }
    }

    private var walkingIcon: some View {
        ZStack {
            Circle()
                .fill(palette.accent.opacity(0.12))
                .frame(width: 100, height: 100)
                .scaleEffect(breathe ? 1.08 : 1)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: breathe)

            // Hand-authored walk cycle from Amble/Lottie/walker.json.
            // Loops seamlessly at 30fps with sine-ease limb rotation.
            LottieView(animation: .named("walker"))
                .playing(loopMode: .loop)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
        }
        // Pure decoration; the elapsed/steps cards convey the
        // active-walk state to VoiceOver users.
        .accessibilityHidden(true)
    }

    private var elapsedCard: some View {
        VStack(spacing: 4) {
            Text("ELAPSED")
                .font(type.body(13 * scale, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(palette.ink2)

            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(elapsedString(at: ctx.date))
                    .font(type.display(64 * scale, weight: .semibold))
                    .kerning(-1.5)
                    .foregroundStyle(palette.ink)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(palette.card)
                .shadow(color: .black.opacity(0.04), radius: 20, x: 0, y: 6)
        )
        // Single read for the whole card. We deliberately compute
        // the label from the tracker rather than the per-second
        // TimelineView so VoiceOver doesn't get tempted to re-
        // announce on every tick when focused on the element.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elapsed time: \(spokenElapsed(seconds: tracker.elapsedSeconds))")
    }

    private var stepsCard: some View {
        VStack(spacing: 4) {
            Text("STEPS ON THIS WALK")
                .font(type.body(13 * scale, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(palette.ink2)

            Text(StepFormat.int(tracker.steps))
                .font(type.display(64 * scale, weight: .semibold))
                .kerning(-1.5)
                .foregroundStyle(palette.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.spring(response: 0.55, dampingFraction: 0.8), value: tracker.steps)
        }
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(palette.card)
                .shadow(color: .black.opacity(0.04), radius: 20, x: 0, y: 6)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(StepFormat.int(tracker.steps)) steps on this walk")
    }

    /// "1 hour, 15 minutes, 23 seconds" — VoiceOver-friendly
    /// alternative to the visible "1:15:23". Pure colon-separated
    /// strings get read awkwardly ("one fifteen twenty-three").
    private func spokenElapsed(seconds total: Int) -> String {
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) hour\(h == 1 ? "" : "s")") }
        if m > 0 { parts.append("\(m) minute\(m == 1 ? "" : "s")") }
        if h == 0 { parts.append("\(s) second\(s == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }

    /// Compact Call + Get Help row so the two safety actions are always one
    /// tap away during a walk — not buried behind a minimize + navigate
    /// detour. Mirrors home's Call / SOS intent but in a quieter pill-row
    /// form so it doesn't compete with the elapsed/steps cards above or the
    /// "I'm home" CTA below.
    private var safetyRow: some View {
        HStack(spacing: 12) {
            if hasContact {
                SafetyPill(
                    icon: "phone.fill",
                    label: contactFirstName.isEmpty ? "Call" : "Call \(contactFirstName)",
                    tint: palette.accent2,
                    emphasis: false,
                    palette: palette, type: type, scale: scale,
                    action: onCall
                )
            }
            SafetyPill(
                icon: "exclamationmark.circle.fill",
                label: "Get Help",
                tint: palette.danger,
                emphasis: true,
                palette: palette, type: type, scale: scale,
                action: onSOS
            )
        }
    }

    private var endButton: some View {
        Button {
            guard !ending else { return }
            ending = true
            Haptics.medium()
            onEnd()
        } label: {
            HStack(spacing: 10) {
                if !ending {
                    Image(systemName: "house.fill")
                        .font(.system(size: 20, weight: .semibold))
                }
                Text(ending ? "Ending…" : "I'm home")
                    .font(type.display(21 * scale, weight: .bold))
                    .kerning(-0.2)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(palette.positive)
            )
            .shadow(color: palette.positive.opacity(0.4), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(.pressable)
        .disabled(ending)
        // The visible "I'm home" / "Ending…" copy is enough for the
        // VoiceOver label; the hint adds the consequence so users
        // know this isn't just a navigation tap.
        .accessibilityHint("Ends and saves your walk.")
    }

    // MARK: - Copy / formatting

    private var encouragementText: String {
        WalkEncouragement.line(elapsedSeconds: tracker.elapsedSeconds)
    }

    private func elapsedString(at date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(tracker.startDate ?? date)))
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct SafetyPill: View {
    let icon: String
    let label: String
    let tint: Color
    /// True = filled treatment for the emergency action (like home's SOS
    /// card). False = quieter tinted-icon-on-card for Call.
    let emphasis: Bool
    let palette: Palette
    let type: Typography
    let scale: Double
    let action: () -> Void

    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(emphasis ? .white : tint)
                Text(label)
                    .font(type.display(17 * scale, weight: .semibold))
                    .kerning(-0.2)
                    .foregroundStyle(emphasis ? .white : palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(emphasis ? tint : palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(emphasis ? Color.clear : Color.black.opacity(0.06),
                                    lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(emphasis ? 0.1 : 0.03),
                            radius: emphasis ? 10 : 6, x: 0, y: emphasis ? 4 : 2)
            )
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint(emphasis
                           ? "Opens the emergency SOS screen."
                           : "Starts a phone call.")
        .accessibilityAddTraits(.isButton)
    }
}
