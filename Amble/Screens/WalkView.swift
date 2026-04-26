import SwiftUI

struct WalkView: View {
    let palette: Palette
    let type: Typography
    let scale: Double
    let walk: WalkSession
    let onBack: () -> Void

    private var dayOfWeek: String {
        AmbleDates.weekday(walk.start)
    }

    private var paceLabel: String {
        // Steps per minute — a gentle, legible indicator of cadence.
        // Computed from seconds (not the 1-minute-floored durationMinutes)
        // so very short walks don't under-report. The 30-second clamp
        // keeps the number sane for accidental 3-step "walks".
        let secs = max(30, walk.durationSeconds)
        let spm = Int((Double(walk.steps) * 60.0 / Double(secs)).rounded())
        return "\(spm) / min"
    }

    var body: some View {
        ScreenShell(title: walk.title, palette: palette, type: type, scale: scale, onBack: onBack) {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(dayOfWeek) · \(walk.timeLabel) – \(walk.endTimeLabel)")
                    .font(type.body(16 * scale, weight: .medium))
                    .foregroundStyle(palette.ink2)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 4)

                Card(palette: palette, insets: .init(top: 28, leading: 24, bottom: 28, trailing: 24)) {
                    VStack(alignment: .leading, spacing: 26) {
                        // Hero steps row
                        HStack(spacing: 16) {
                            ZStack {
                                Circle().fill(palette.soft)
                                Image(systemName: "figure.walk")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(palette.accent)
                            }
                            .frame(width: 68, height: 68)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(StepFormat.int(walk.steps))
                                    .font(type.display(48 * scale, weight: .semibold))
                                    .kerning(-1)
                                    .foregroundStyle(palette.ink)
                                    .monospacedDigit()
                                Text("steps")
                                    .font(type.body(15 * scale, weight: .medium))
                                    .foregroundStyle(palette.ink2)
                            }
                        }

                        // Thin rule — editorial divider between hero and stats
                        Rectangle()
                            .fill(palette.ink2.opacity(0.15))
                            .frame(height: 0.5)

                        // Two stats with a soft vertical rule between them
                        HStack(spacing: 0) {
                            StatView(label: "Duration", value: durationLabel,
                                     palette: palette, type: type, scale: scale)

                            Rectangle()
                                .fill(palette.ink2.opacity(0.15))
                                .frame(width: 0.5, height: 44)

                            StatView(label: "Pace", value: paceLabel,
                                     palette: palette, type: type, scale: scale)
                        }
                    }
                }

                // Afterglow card — leaf glyph above a centered Fraunces
                // italic line. Cream background keeps it distinct from
                // the home screen's background-less encouragement, while
                // the leaf ties into the motif from the Done screen.
                VStack(spacing: 14) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(palette.accent.opacity(0.55))

                    Text(WalkAfterglow.line(for: walk))
                        .font(type.display(18 * scale, weight: .regular).italic())
                        .foregroundStyle(palette.ink)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .padding(.horizontal, 28)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(palette.soft)
                )
            }
        }
    }

    private var durationLabel: String {
        let mins = walk.durationMinutes
        if mins < 60 { return "\(mins) min" }
        let h = mins / 60
        let m = mins % 60
        return m == 0 ? "\(h) hr" : "\(h) hr \(m)"
    }
}

private struct StatView: View {
    let label: String
    let value: String
    let palette: Palette
    let type: Typography
    let scale: Double

    var body: some View {
        VStack(spacing: 6) {
            Text(label.uppercased())
                .font(type.body(12 * scale, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(palette.ink2)
            Text(value)
                .font(type.display(26 * scale, weight: .semibold))
                .kerning(-0.4)
                .foregroundStyle(palette.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
