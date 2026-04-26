import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case home, week, reflect, more
    var id: String { rawValue }
    var label: String {
        switch self {
        case .home: "Today"
        case .week: "Week"
        case .reflect: "Reflect"
        case .more: "Settings"
        }
    }
    var systemIcon: String {
        switch self {
        case .home: "leaf.fill"
        case .week: "calendar"
        case .reflect: "book.closed.fill"
        case .more: "gearshape.fill"
        }
    }
}

struct TabBar: View {
    @Binding var current: MainTab
    let palette: Palette
    let type: Typography
    let scale: Double

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                let active = current == tab
                Button {
                    Haptics.select()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        current = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemIcon)
                            .font(.system(size: 24, weight: active ? .semibold : .regular))
                        Text(tab.label)
                            .font(type.body(12 * scale, weight: active ? .semibold : .medium))
                            .kerning(0.1)
                    }
                    .foregroundStyle(active ? palette.accent : palette.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                // VoiceOver reads "Today, tab, selected" / "Today,
                // tab" — the visible label is fine, but `.isSelected`
                // surfaces the active state explicitly so users know
                // which tab they're on without having to navigate
                // away and back.
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint(active ? "" : "Switches to the \(tab.label) tab.")
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 24, x: 0, y: 8)
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }
}
