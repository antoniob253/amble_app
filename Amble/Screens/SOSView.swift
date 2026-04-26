import SwiftUI
import UIKit
import CoreLocation

/// Region → emergency dispatch number. 112 works across all of the EU,
/// most of Africa, parts of Asia, and is GSM-standard, so it's our
/// wide-fallback when we don't have a dedicated mapping.
enum EmergencyServices {
    static func numberForCurrentRegion() -> String {
        let region = Locale.current.region?.identifier ?? ""
        switch region {
        case "US", "CA", "MX", "AR", "CO":   return "911"
        case "GB", "IE":                      return "999"
        case "AU":                            return "000"
        case "NZ":                            return "111"
        case "JP":                            return "119"  // fire/ambulance (police = 110)
        case "KR":                            return "119"  // fire/ambulance
        case "BR":                            return "192"  // SAMU (medical)
        default:                              return "112"
        }
    }
}

/// Two-phase state for the SOS flow.
///
/// We deliberately *don't* try to distinguish "call succeeded" from
/// "call cancelled" — on iOS 18 `open(tel://)` resolves as soon as the
/// system shows its confirmation, and on iOS 26 `willResignActive` fires
/// on the sheet's presentation too. Neither is a reliable signal for
/// user intent, so we stopped pretending it was. After the hold, we
/// fire the tel:// handoff and show an honest action center — no
/// success theatre, no false claims about what iOS did next.
enum SOSPhase {
    /// Idle. User can press and hold.
    case prompt
    /// Hold completed. iOS has been handed the tel:// URL and will
    /// present its own confirmation; we show a compact action center
    /// with Call / Text buttons the user can lean on whether the first
    /// call went through or not.
    case actions
}

struct SOSView: View {
    @Environment(LocationManager.self) private var location

    let palette: Palette
    let type: Typography
    let scale: Double
    let contact: EmergencyContact
    let onBack: () -> Void

    @State private var holding = false
    @State private var progress: Double = 0
    @State private var phase: SOSPhase = .prompt
    /// Used purely to prefill the SMS body with a Maps link. Never rendered
    /// on screen — seniors can't read lat/lon to a dispatcher anyway, and
    /// dispatch already gets caller location via carrier E911.
    @State private var resolvedLocation: CLLocation?
    @State private var holdStart: Date?
    private let holdDuration: TimeInterval = 3.0
    @State private var timer: Timer?
    @State private var hapticTimer: Timer?

    private var emergencyNumber: String { EmergencyServices.numberForCurrentRegion() }

    private var contactFirstName: String {
        contact.name.components(separatedBy: " ").first ?? ""
    }

    /// Whether we can actually include a location in the SMS prefill. Gates
    /// copy so we don't promise "with your location" if the user declined
    /// location sharing during onboarding.
    private var canShareLocation: Bool {
        location.isAuthorized
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Warm cream background — matches the rest of the app so
            // opening SOS doesn't feel like entering a different room.
            // Urgency lives in the red button, not in the walls.
            palette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 96)
                switch phase {
                case .prompt:  promptContent
                case .actions: actionsContent
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 40)

            Button { Haptics.tap(); onBack() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(palette.card))
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Close")
            .accessibilityHint("Closes the SOS screen.")
            .padding(.top, 62)
            .padding(.leading, 20)
        }
    }

    // MARK: - Prompt

    private var promptContent: some View {
        VStack(spacing: 0) {
            Text("Need help?")
                .font(type.display(36 * scale, weight: .semibold))
                .kerning(-0.5)
                .foregroundStyle(palette.ink)
                .padding(.bottom, 12)

            Text("Hold for 3 seconds to call \(emergencyNumber), your local emergency services.")
                .font(type.body(17 * scale, weight: .medium))
                .foregroundStyle(palette.ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 36)

            Spacer(minLength: 0)

            sosButton
                .padding(.vertical, 8)

            Spacer(minLength: 0)

            Text(holding
                 ? "Hold… \(Int(ceil((1 - progress) * holdDuration))) s · release to cancel"
                 : "Press and hold")
                .font(type.body(16 * scale, weight: .semibold))
                .foregroundStyle(palette.ink2)
                .padding(.top, 18)

            if !contact.phone.isEmpty {
                Text(promptContactSubtitle)
                    .font(type.body(14 * scale, weight: .medium))
                    .foregroundStyle(palette.ink2.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 44)
                    .padding(.top, 10)
            }
        }
    }

    private var sosButton: some View {
        ZStack {
            // Red fill + soft warm halo, sized up to 240pt. This is the
            // only red thing on screen, so it owns the urgency signal.
            Circle()
                .fill(palette.danger)
                .shadow(color: palette.danger.opacity(0.35), radius: 28, x: 0, y: 10)
                .scaleEffect(holding ? 1.04 : 1)
                .animation(.easeOut(duration: 0.2), value: holding)

            // Progress track + fill (white over red for strong contrast).
            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 7)
                .padding(4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(4)

            VStack(spacing: 6) {
                Text("SOS")
                    .font(type.display(52 * scale, weight: .heavy))
                    .kerning(2)
                    .foregroundStyle(.white)
                Text("Calls \(emergencyNumber)")
                    .font(type.body(13 * scale, weight: .semibold))
                    .kerning(0.4)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: 240, height: 240)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in start() }
                .onEnded { _ in stop() }
        )
        // Accessibility for the press-and-hold SOS button. The
        // 3-second hold protects sighted users from accidental
        // calls, but VoiceOver users already activate elements
        // deliberately (focus + double-tap), so for them we expose
        // a single default action that fires the call immediately
        // — making the hold a redundant barrier for an audience
        // that's already cleared the "did you mean to do this?"
        // bar via VoiceOver's own interaction model.
        //
        // We .combine children so VoiceOver reads the whole
        // composed button as one element ("SOS, calls 112,
        // button") instead of announcing the visual progress
        // ring, the text, and the subtitle separately.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("S O S, call emergency services")
        .accessibilityHint("Calls \(emergencyNumber). Double-tap to start the call now, or press and hold for three seconds.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            Haptics.success()
            Task { await fireAlert() }
        }
    }

    // MARK: - Actions (post-hold)

    /// Rendered the instant the 3-second hold completes. Framed as an
    /// action center, not a success screen: we can't reliably know
    /// whether the tel:// handoff was confirmed or cancelled, so we
    /// don't claim anything about it. The buttons are the whole point —
    /// they work in every case (confirmed, cancelled, fat-fingered,
    /// came-back-after-a-call). Call 112 re-fires the tel:// URL, Text
    /// alerts the contact.
    private var actionsContent: some View {
        VStack(spacing: 0) {
            // Quiet red phone badge. Deliberately subdued (100pt soft
            // tinted fill, not a 140pt saturated disc) so it reads as
            // "you're in the emergency flow" without the celebratory
            // "done!" energy a green checkmark carried.
            ZStack {
                Circle()
                    .fill(palette.danger.opacity(0.14))
                    .frame(width: 100, height: 100)
                Image(systemName: "phone.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(palette.danger)
            }
            .transition(.scale.combined(with: .opacity))
            .padding(.bottom, 22)

            Text("Getting help")
                .font(type.display(36 * scale, weight: .semibold))
                .kerning(-0.5)
                .foregroundStyle(palette.ink)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            Text(actionsSubtitle)
                .font(type.body(17 * scale, weight: .medium))
                .foregroundStyle(palette.ink2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 36)

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    Haptics.medium()
                    if let url = URL(string: "tel:\(emergencyNumber)") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Call \(emergencyNumber)")
                            .font(type.display(19 * scale, weight: .bold))
                            .kerning(-0.2)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(palette.danger)
                    )
                    .shadow(color: palette.danger.opacity(0.35), radius: 16, x: 0, y: 6)
                }
                .buttonStyle(.pressable)

                if !contact.phone.isEmpty {
                    Button {
                        Haptics.medium()
                        let loc = resolvedLocation
                        let body: String
                        if let loc {
                            body = "I need help. I just called \(emergencyNumber). My location: \(LocationManager.mapsLink(for: loc))"
                        } else {
                            body = "I need help. I just called \(emergencyNumber)."
                        }
                        if let url = PhoneFormatter.smsURL(contact.phone, body: body) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "message.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text(textButtonLabel)
                                .font(type.display(19 * scale, weight: .bold))
                                .kerning(-0.2)
                        }
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(palette.card)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                                )
                        )
                        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
        }
    }

    // MARK: - Copy

    /// Pre-hold teaser. We promise a location share only if we actually
    /// have permission to send one — otherwise we just promise a text.
    private var promptContactSubtitle: String {
        if canShareLocation {
            return "We'll also help you text \(contactFirstName) with your location."
        }
        return "We'll also help you text \(contactFirstName)."
    }

    /// Subtitle under the "Getting help" headline. Frames both buttons
    /// as equally first-class options, without claiming the first call
    /// attempt went through.
    private var actionsSubtitle: String {
        if contact.phone.isEmpty {
            return "Call \(emergencyNumber) using the button below."
        }
        if canShareLocation {
            return "Call \(emergencyNumber) or text \(contactFirstName) your location."
        }
        return "Call \(emergencyNumber) or text \(contactFirstName)."
    }

    /// Secondary CTA on the actions screen.
    private var textButtonLabel: String {
        if contactFirstName.isEmpty {
            return "Text your contact"
        }
        if canShareLocation {
            return "Text \(contactFirstName) your location"
        }
        return "Text \(contactFirstName)"
    }

    // MARK: - Hold logic

    private func start() {
        // Only start a fresh hold from the idle prompt state. Once we're
        // in calling or sent, the user needs to go back/dismiss instead.
        guard !holding, phase == .prompt else { return }
        holding = true
        holdStart = Date()
        Haptics.rigid()
        timer = Timer.scheduledTimer(withTimeInterval: 1/60, repeats: true) { _ in
            Task { @MainActor in
                guard let start = holdStart else { return }
                let p = min(1, Date().timeIntervalSince(start) / holdDuration)
                progress = p
                if p >= 1 {
                    timer?.invalidate()
                    hapticTimer?.invalidate()
                    Haptics.success()
                    // Hand off to fireAlert — it flips into the action
                    // center and fires the tel:// URL. No polling or
                    // confirmation-detection from there on.
                    await fireAlert()
                }
            }
        }
        // Pulse haptic during the hold
        hapticTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
            Haptics.soft()
        }
    }

    private func stop() {
        timer?.invalidate()
        hapticTimer?.invalidate()
        // Only reset the ring if we're still in the prompt phase. Once
        // fireAlert has moved us to .actions, releasing the button is a
        // no-op — the action center owns the rest of the session.
        if phase == .prompt {
            holding = false
            withAnimation(.easeOut(duration: 0.3)) { progress = 0 }
        }
    }

    private func fireAlert() async {
        // Flip to the action center immediately. Whatever happens with
        // iOS's tel:// confirmation from here — Call, Cancel, taking
        // forever to decide — the same screen is correct: two clear
        // buttons the user can use to call or text. No success claim
        // means nothing to take back if the call didn't actually happen.
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            phase = .actions
            holding = false
            progress = 1
        }

        // Kick off location resolution for the SMS prefill. Safe no-op
        // if the user declined location during onboarding.
        async let loc = location.requestLocation()

        // Hand off to iOS. We ignore the return value deliberately —
        // on iOS 18+ `open()` resolves the moment the system accepts
        // the URL (not when the user taps Call), so it's not a usable
        // signal for "call confirmed". We stopped trying to track that
        // and let iOS own the confirmation UX.
        if let url = URL(string: "tel:\(emergencyNumber)") {
            _ = await UIApplication.shared.open(url)
        }

        resolvedLocation = await loc
    }
}
