import SwiftUI

struct StepperButton: View {
    let palette: Palette
    let symbol: String
    let action: () -> Void
    var size: CGFloat = 56

    var body: some View {
        Button {
            Haptics.soft()
            action()
        } label: {
            Text(symbol)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: size, height: size)
                .background(Circle().fill(palette.soft))
        }
        .buttonStyle(.pressable)
        // The visible glyph is either "−" (math minus) or "+" — both
        // get read as "minus sign" / "plus sign" by VoiceOver, which
        // is technically correct but unhelpful out of context. Map
        // explicitly to "Decrease" / "Increase" so the action is
        // clear regardless of the surrounding label.
        .accessibilityLabel(symbol == "+" ? "Increase" : "Decrease")
    }
}

struct PrimaryButton: View {
    let title: String
    let palette: Palette
    let type: Typography
    let scale: Double
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.medium()
            action()
        } label: {
            Text(title)
                .font(type.display(21 * scale, weight: .bold))
                .kerning(-0.2)
                .foregroundStyle(enabled ? .white : palette.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(enabled ? palette.accent : palette.ringTrack)
                )
                .shadow(color: enabled ? palette.accent.opacity(0.4) : .clear, radius: 18, x: 0, y: 8)
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
    }
}
