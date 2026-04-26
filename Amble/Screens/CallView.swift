import SwiftUI
import UIKit

struct CallView: View {
    let palette: Palette
    let type: Typography
    let scale: Double
    let contact: CallContact
    let onBack: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var pulse = false
    @State private var dialed = false
    @State private var leftForCall = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 80)

            // Decorative avatar (the giant initial in a coloured
            // circle, plus the pulsing rings during a dial). The
            // contact's name and relation are spoken right after by
            // VoiceOver, so reading the initial out loud here would
            // just be redundant noise. Hide the whole stack.
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(contact.color, lineWidth: 2)
                        .frame(width: 180, height: 180)
                        .scaleEffect(pulse ? 1.8 : 1)
                        .opacity(pulse ? 0 : 0.6)
                        .animation(
                            .easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(i) * 0.8),
                            value: pulse
                        )
                }
                Circle()
                    .fill(contact.color)
                    .frame(width: 180, height: 180)
                    .shadow(color: contact.color.opacity(0.5), radius: 30, x: 0, y: 12)
                Text(contact.initial)
                    .font(type.display(80 * scale, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(contact.name)
                    .font(type.display(42 * scale, weight: .semibold))
                    .kerning(-0.8)
                    .foregroundStyle(palette.ink)
                Text(contact.relation)
                    .font(type.body(20 * scale, weight: .medium))
                    .foregroundStyle(palette.ink2)
                if !contact.phone.isEmpty {
                    Text(contact.phone)
                        .font(type.body(17 * scale, weight: .medium))
                        .foregroundStyle(palette.ink2)
                        .padding(.top, 6)
                }
            }
            .padding(.top, 40)

            Spacer()

            Button {
                Haptics.success()
                pulse = true
                dialed = true
                if let url = PhoneFormatter.telURL(contact.phone) {
                    UIApplication.shared.open(url) { _ in }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 22, weight: .semibold))
                    Text(callButtonLabel)
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
            .disabled(contact.phone.isEmpty || dialed)
            .opacity(contact.phone.isEmpty ? 0.45 : 1)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
        .background(palette.bg.ignoresSafeArea())
        .overlay(alignment: .topLeading) {
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
            .accessibilityHint("Closes this screen without calling.")
            .padding(.top, 62)
            .padding(.leading, 20)
        }
        .onChange(of: scenePhase) { _, phase in
            // When the system dial UI takes over, the app goes inactive/background.
            // When the user returns (call ended, or they switched back), pop
            // this pre-call screen so they land back on home — with their
            // walk banner, if one's running — instead of staring at a
            // "Calling…" button for a call that's already done.
            switch phase {
            case .inactive, .background:
                if dialed { leftForCall = true }
            case .active:
                if leftForCall { onBack() }
            @unknown default:
                break
            }
        }
    }

    private var callButtonLabel: String {
        if dialed { return "Calling…" }
        let first = contact.name.components(separatedBy: " ").first ?? ""
        return first.isEmpty ? "Call" : "Call \(first)"
    }
}
