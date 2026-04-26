import SwiftUI

struct GoalView: View {
    let palette: Palette
    let type: Typography
    let scale: Double
    @Binding var goal: Int
    let onBack: () -> Void

    @State private var val: Int = 5000
    // Six chips, matching the onboarding goal step 1:1. Users
    // recovering from illness or easing in benefit from the 1k
    // "Starter" option being a one-tap choice rather than only
    // reachable via fine-tune.
    private let options: [Int] = [1000, 2000, 3000, 5000, 7000, 10000]
    private let labels: [Int: String] = [
        1000: "Starter", 2000: "Easy", 3000: "Gentle",
        5000: "Steady", 7000: "Active", 10000: "Strong"
    ]

    private var description: String {
        switch val {
        case ...1500:     return "A gentle starting point. Kind to the body, easy to keep up."
        case 1501...2500: return "A short daily walk. Just enough to feel the day move."
        case 2501...4000: return "A pleasant walk around the neighbourhood. A small habit, well kept."
        case 4001...6000: return "A daily walk outside. Your body settles into the rhythm."
        case 6001...8500: return "Keeps the body and mind sharp. A solid daily habit."
        default:          return "A real day on your feet. Be gentle with yourself this evening."
        }
    }

    var body: some View {
        ScreenShell(title: "Daily Goal", palette: palette, type: type, scale: scale, onBack: onBack) {
            VStack(alignment: .leading, spacing: 16) {
                Card(palette: palette) {
                    VStack(spacing: 6) {
                        Text("Your daily step goal")
                            .font(type.body(17 * scale, weight: .medium))
                            .foregroundStyle(palette.ink2)
                        Text(StepFormat.int(val))
                            .font(type.display(72 * scale, weight: .semibold))
                            .kerning(-2)
                            .foregroundStyle(palette.accent)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.spring, value: val)
                            .padding(.top, 4)
                        Text(labels[val] ?? "Custom")
                            .font(type.body(18 * scale, weight: .semibold))
                            .foregroundStyle(palette.ink)
                            .padding(.top, 2)
                        Text(description)
                            .font(type.body(15 * scale, weight: .medium))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(palette.ink2)
                            .lineSpacing(3)
                            .frame(maxWidth: 280)
                            .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity)
                }

                // Six chips spread across the width with tighter spacing
                // than before (8 → 6) so the row stays comfortable on
                // iPhone SE / mini.
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { o in
                        let selected = val == o
                        Button {
                            Haptics.select()
                            val = o
                        } label: {
                            VStack(spacing: 3) {
                                Text("\(o/1000)k")
                                    .font(type.display(15 * scale, weight: .bold))
                                Text(labels[o] ?? "")
                                    .font(type.body(10 * scale, weight: .medium))
                                    .opacity(0.85)
                            }
                            .foregroundStyle(selected ? .white : palette.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(selected ? palette.accent : palette.card)
                                    .shadow(color: selected ? palette.accent.opacity(0.4) : .black.opacity(0.04),
                                            radius: selected ? 10 : 2, x: 0, y: selected ? 4 : 1)
                            )
                        }
                        .buttonStyle(.pressable)
                        // Read each chip as e.g. "5,000 steps, A daily
                        // walk outside" plus a selected/unselected
                        // trait. The "5k" abbreviation alone would be
                        // ambiguous out of context for VoiceOver users.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(StepFormat.int(o)) steps, \(labels[o] ?? "")")
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("FINE TUNE")
                        .font(type.body(15 * scale, weight: .semibold))
                        .kerning(0.3)
                        .foregroundStyle(palette.ink2)

                    HStack(spacing: 14) {
                        StepperButton(palette: palette, symbol: "−") {
                            val = max(500, val - 500)
                        }
                        Spacer()
                        Text(StepFormat.int(val))
                            .font(type.display(24 * scale, weight: .bold))
                            .foregroundStyle(palette.ink)
                            .monospacedDigit()
                        Spacer()
                        StepperButton(palette: palette, symbol: "+") {
                            val = min(20000, val + 500)
                        }
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(palette.card)
                )

                Button {
                    goal = val
                    Haptics.success()
                    onBack()
                } label: {
                    Text("Save goal")
                        .font(type.display(20 * scale, weight: .bold))
                        .kerning(-0.2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(palette.accent)
                        )
                        .shadow(color: palette.accent.opacity(0.4), radius: 18, x: 0, y: 6)
                }
                .buttonStyle(.pressable)
                .padding(.top, 4)
            }
        }
        .onAppear { val = goal }
    }
}
