import ActivityKit
import WidgetKit
import SwiftUI

// Note: `AmbleWalkActivityAttributes` lives in the main app target
// (Amble/Models/AmbleWalkActivityAttributes.swift). Give that file membership
// in THIS widget target in Xcode's File Inspector so the types match.

struct AmbleWalkLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AmbleWalkActivityAttributes.self) { context in
            // Lock-screen / Notification Center presentation. Cream
            // background mirrors the rest of the app, so we use the
            // standard sage ink/accent palette.
            LockScreenView(state: context.state)
                .activityBackgroundTint(AmbleColors.bg)
                .activitySystemActionForegroundColor(AmbleColors.ink)
        } dynamicIsland: { context in
            // Dynamic Island presentations. Background is ALWAYS pure
            // black (Apple does not allow customising it), so every
            // colour here uses the on-dark palette — light text and a
            // brightened sage that actually reads against black.
            DynamicIsland {
                // Top-left of the expanded layout. Just the figure.walk
                // glyph + a "Walking" label so a senior glancing down
                // immediately sees *what* is being tracked, not just
                // an abstract icon.
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AmbleColors.accentOnDark)
                        Text("Walking")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AmbleColors.inkOnDark)
                    }
                }
                // Top-right: live elapsed timer. `showsHours` defaults
                // to true so a 1h15m walk reads as "1:15:00" rather
                // than the mis-labelled "75:00" the previous setting
                // produced.
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startDate...Date.distantFuture,
                         countsDown: false)
                        .font(.system(size: 18, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(AmbleColors.inkOnDark)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                // Bottom region — the headline number. Step count is
                // the primary metric a walking app should present, so
                // it gets the largest typography in the entire Live
                // Activity. `formatted()` adds locale-correct grouping
                // separators ("5,432" not "5432") which is hugely
                // easier to read at a glance for older eyes.
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(context.state.steps.formatted())
                            .font(.system(size: 34, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(AmbleColors.inkOnDark)
                        Text("steps so far")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AmbleColors.ink2OnDark)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                // The pill state — only ~60pt wide, so we show the
                // bare minimum: the brand-aligned walking glyph.
                Image(systemName: "figure.walk")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AmbleColors.accentOnDark)
            } compactTrailing: {
                // Step count is the more glanceable metric than time
                // for a walking session. White is intentional —
                // sage on black is muddy at this size.
                Text(context.state.steps.formatted())
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AmbleColors.inkOnDark)
            } minimal: {
                // Shown when multiple Live Activities are competing
                // for the Dynamic Island. One glyph, brightened sage.
                Image(systemName: "figure.walk")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AmbleColors.accentOnDark)
            }
            // Subtle Amble-coloured glow around the island when the
            // user long-presses or the activity updates. Bright sage
            // reads against black; the original sage was too dim.
            .keylineTint(AmbleColors.accentOnDark)
        }
    }
}

private struct LockScreenView: View {
    let state: AmbleWalkActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            // Soft circular badge in the brand sage. Slightly larger
            // (52pt) than before so the icon registers from arm's
            // length on the lock screen.
            ZStack {
                Circle().fill(AmbleColors.accent.opacity(0.15))
                Image(systemName: "figure.walk")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AmbleColors.accent)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text("Walking with Amble")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AmbleColors.ink2)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // Big, locale-grouped step count — same treatment
                    // as the home screen ring counter for consistency.
                    Text(state.steps.formatted())
                        .font(.system(size: 32, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(AmbleColors.ink)
                    Text("steps")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AmbleColors.ink2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                // "Time" in mixed-case sentence style instead of the
                // previous "ELAPSED" all-caps + tracking — the latter
                // felt techy and clashed with Amble's warm tone.
                Text("Time")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AmbleColors.ink2)
                Text(timerInterval: state.startDate...Date.distantFuture,
                     countsDown: false)
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(AmbleColors.ink)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(16)
    }
}

// MARK: - Colors

/// Mirrors the sage palette's ink/accent/bg from Theme.swift, plus a
/// dedicated "on dark" variant for the always-black Dynamic Island.
/// The widget target doesn't link the app's Theme, so we re-declare
/// the handful we use.
private enum AmbleColors {
    // Sage palette — designed for cream paper backgrounds (the rest
    // of the app, plus the lock-screen Live Activity which we tint
    // cream via `activityBackgroundTint`).
    static let bg     = Color(hex: 0xF5F0E6)
    static let ink    = Color(hex: 0x1F2A24)
    static let ink2   = Color(hex: 0x5A6560)
    static let accent = Color(hex: 0x5C7A5A)

    // On-dark variants for the always-black Dynamic Island. The
    // sage palette values above were tuned for cream paper and are
    // near-invisible on pure black (contrast ratio ~1.5:1, fails
    // every WCAG threshold). These three are the colours used for
    // every glyph and label inside the island.
    //
    //   inkOnDark    → primary text. Pure white for max contrast.
    //   ink2OnDark   → secondary labels. Light cool-grey, ~9.6:1
    //                  contrast on black, still clearly readable
    //                  but visibly subordinate to the white.
    //   accentOnDark → the figure.walk glyph + keyline tint. A
    //                  brightened sage (~9.8:1 contrast on black)
    //                  that still reads as "Amble green" rather
    //                  than dropping to a generic system colour.
    static let inkOnDark    = Color.white
    static let ink2OnDark   = Color(hex: 0xB6BFB8)
    static let accentOnDark = Color(hex: 0x9FC09D)
}

private extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
