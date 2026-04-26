import SwiftUI

/// A contemplative tab — one curated poem or passage per day, rotated by
/// a date-seeded index into the `Reflections` pool. Generous margins,
/// Fraunces display face, small attribution. Feels like opening a book.
struct ReflectionsView: View {
    let palette: Palette
    let type: Typography
    let scale: Double

    /// How many days back the user can step. Zero = today only.
    /// Seven days of browsable history is plenty; more would invite
    /// scrolling through an archive, which isn't the ritual we want.
    private static let maxHistoryDays = 6

    @State private var offsetDays: Int = 0
    @State private var appear: Bool = false

    private var currentDate: Date {
        Calendar.current.date(byAdding: .day, value: -offsetDays, to: Date()) ?? Date()
    }

    private var currentPiece: Reflection? {
        Reflections.forDate(currentDate)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            palette.bg.ignoresSafeArea()

            // Header + the piece. The VStack's .padding(.bottom, 200)
            // ends the piece-area at the action bar's top edge, so the
            // piece centers in the strip between the header and the
            // action bar — not between the header and the tab bar.
            // Math: action bar sits 140pt from screen bottom and is
            // 52pt tall → top edge at 192pt. 200pt leaves an 8pt gap
            // above the action bar so the piece's last line never
            // butts up against it.
            VStack(spacing: 0) {
                header
                    .padding(.top, 56)
                    .padding(.horizontal, 20)

                // Fixed-size piece area. Deliberately NOT a ScrollView —
                // pieces are curated and length-capped (max 293 chars),
                // and we'd rather scale type down via
                // `.minimumScaleFactor` than offer a scroll gesture that
                // conflicts with the horizontal swipe-to-flip.
                GeometryReader { proxy in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        content
                            .padding(.horizontal, 32)
                        Spacer(minLength: 0)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .id(offsetDays)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)),
                        removal: .opacity
                    ))
                }
                // Horizontal swipe-to-flip days. Right-swipe = older
                // (Earlier), left-swipe = newer (Later) — same spatial
                // intuition as Photos. The ratio + min-distance guards
                // keep vertical drags (e.g. on long prose) from
                // accidentally changing days.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            let h = value.translation.width
                            let v = value.translation.height
                            guard abs(h) > abs(v) * 1.5, abs(h) > 60 else { return }
                            let delta: Int = h < 0 ? -1 : +1
                            let next = offsetDays + delta
                            guard next >= 0, next <= Self.maxHistoryDays else { return }
                            Haptics.tap()
                            withAnimation(.easeInOut(duration: 0.3)) {
                                offsetDays = next
                            }
                        }
                )
            }
            .padding(.bottom, 200)

            // Three-pill action bar, overlaid at the bottom so it
            // doesn't compete with the piece for vertical space. Sits
            // above the tab bar via .padding(.bottom, 140) — same
            // clearance ScreenShell uses elsewhere.
            actionBar
                .padding(.horizontal, 24)
                .padding(.bottom, 140)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appear = true }
        }
    }

    // MARK: - Header

    /// The title flexes with the browse offset so the screen never lies
    /// about whose day it's showing. At offset 0 it's "Today's Thought";
    /// at 1 it's "Yesterday's Thought"; further back it's the weekday
    /// possessive ("Monday's Thought"). Cross-fades via
    /// `contentTransition` when the offset changes inside a
    /// `withAnimation` block.
    private var header: some View {
        HStack(spacing: 12) {
            Text(headerTitle)
                .font(type.display(34 * scale, weight: .bold))
                .foregroundStyle(palette.ink)
                .kerning(-0.6)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    private var headerTitle: String {
        switch offsetDays {
        case 0:  return "Today's Thought"
        case 1:  return "Yesterday's Thought"
        default: return "\(AmbleDates.weekday(currentDate))'s Thought"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let piece = currentPiece {
            // For verse, each authored line is meant to stand on its own
            // visual line — line breaks are part of the poem's craft.
            // We pass the authored line count to `lineLimit` so that if
            // a line is slightly too wide for a given screen (e.g. the
            // em dash falls off "I'll tell you how the Sun rose —" on
            // an iPhone 16 but fits on a 17 Pro), SwiftUI shrinks the
            // entire piece uniformly via `minimumScaleFactor` until
            // every authored line fits on one visual line. Prose has
            // no such constraint — it wraps freely.
            let authoredLines = piece.text.components(separatedBy: "\n").count
            VStack(spacing: 32) {
                Text(piece.text)
                    .font(type.display(bodySize(for: piece) * scale, weight: .regular))
                    .foregroundStyle(palette.ink)
                    .multilineTextAlignment(piece.isVerse ? .center : .leading)
                    .lineSpacing(8)
                    .lineLimit(piece.isVerse ? authoredLines : nil)
                    // Verse gets a more aggressive floor (0.55) than
                    // prose (0.75) because verse's line-fit constraint
                    // is stricter — we'd rather shrink the whole poem
                    // than break a poet's line.
                    .minimumScaleFactor(piece.isVerse ? 0.55 : 0.75)

                attribution(piece)
            }
            .frame(maxWidth: .infinity)
            .opacity(appear ? 1 : 0)
            .animation(.easeOut(duration: 0.5), value: appear)
        } else {
            Text("No reflection today.")
                .font(type.body(17 * scale, weight: .medium))
                .foregroundStyle(palette.ink2)
        }
    }

    /// Short pieces get a bigger size; longer passages step down so they
    /// don't crowd the screen. Prose is rendered a touch smaller than
    /// verse to preserve a poem-on-a-page feeling. Combined with
    /// `minimumScaleFactor` in the Text, this handles the full length
    /// range (42–293 chars) across every iPhone size cleanly.
    private func bodySize(for piece: Reflection) -> CGFloat {
        let length = piece.text.count
        if !piece.isVerse {
            return length > 240 ? 19 : 21
        }
        switch length {
        case ..<80:   return 28
        case ..<160:  return 24
        case ..<260:  return 21
        default:      return 19
        }
    }

    private func attribution(_ piece: Reflection) -> some View {
        let year = piece.yearLabel
        let line = year.isEmpty ? piece.author : "\(piece.author), \(year)"
        return Text("— \(line)")
            .font(type.body(15 * scale, weight: .medium))
            .italic()
            .foregroundStyle(palette.ink2)
            .multilineTextAlignment(.center)
    }

    // MARK: - Action bar

    /// Three matched capsule pills at the bottom of the screen —
    /// Earlier (icon only), Share (icon + "Share"), Later (icon only).
    /// All share the same height, fill, shadow, and vertical position
    /// so they read as a designed trio rather than three separate
    /// controls. Share always sits at the horizontal centre, so users
    /// know exactly where to find it regardless of which piece is
    /// showing.
    private var actionBar: some View {
        HStack(spacing: 0) {
            arrowPill(
                icon: "chevron.left",
                enabled: offsetDays < Self.maxHistoryDays,
                action: { step(+1) }
            )
            .accessibilityLabel("Earlier")

            Spacer()

            sharePill

            Spacer()

            arrowPill(
                icon: "chevron.right",
                enabled: offsetDays > 0,
                action: { step(-1) }
            )
            .accessibilityLabel("Later")
        }
    }

    /// Icon-only arrow pill. Fixed 56×52 so both arrows are identical
    /// rectangles visually even though their icons differ. White
    /// `palette.card` fill rather than `palette.soft` so the pills
    /// read clearly against the cream background — `soft` was too
    /// close to `bg` in luminance. Disabled state drops the shadow
    /// and fades the whole pill to 0.35 so it reads as "end of range"
    /// without disappearing.
    private func arrowPill(icon: String,
                           enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.ink)
                .frame(width: 56, height: 52)
                .background(
                    Capsule(style: .continuous)
                        .fill(palette.card)
                        .shadow(color: .black.opacity(enabled ? 0.10 : 0),
                                radius: 10, x: 0, y: 4)
                )
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.35)
    }

    /// Share pill. Same 52pt height as the arrow pills, but width is
    /// content-driven (icon + "Share" label). Same `palette.card`
    /// white fill + shadow as the arrows so the trio reads as a
    /// matched set with clear contrast against the cream background.
    /// Uses SwiftUI's native `ShareLink` so we inherit iOS's current
    /// share sheet for free. The share payload is the current piece's
    /// formatted share text.
    @ViewBuilder
    private var sharePill: some View {
        if let piece = currentPiece {
            ShareLink(item: piece.shareText) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Share")
                        .font(type.body(16 * scale, weight: .semibold))
                }
                .foregroundStyle(palette.ink)
                .frame(height: 52)
                .padding(.horizontal, 22)
                .background(
                    Capsule(style: .continuous)
                        .fill(palette.card)
                        .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
                )
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Share this thought")
        } else {
            // No piece = nothing to share. Render a placeholder pill
            // of identical dimensions so the trio's spacing doesn't
            // collapse on the empty-state screen.
            Capsule(style: .continuous)
                .fill(palette.card.opacity(0.5))
                .frame(width: 120, height: 52)
        }
    }

    // MARK: - Navigation

    private func step(_ delta: Int) {
        let next = offsetDays + delta
        guard next >= 0, next <= Self.maxHistoryDays else { return }
        withAnimation(.easeInOut(duration: 0.3)) { offsetDays = next }
    }
}
