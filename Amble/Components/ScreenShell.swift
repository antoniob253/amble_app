import SwiftUI

struct ScreenShell<Content: View>: View {
    let title: String
    /// Optional date / context line rendered under the title in `ink2`.
    /// Used e.g. by the Week screen to ground the user in "22 – 28 April"
    /// so an early-week sparse chart doesn't feel like a broken screen.
    var subtitle: String? = nil
    let palette: Palette
    let type: Typography
    let scale: Double
    var onBack: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        if let onBack {
                            Button {
                                Haptics.tap()
                                onBack()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(palette.ink)
                                    .frame(width: 48, height: 48)
                                    .background(Circle().fill(palette.card))
                                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(.pressable)
                            .accessibilityLabel("Back")
                            .accessibilityHint("Returns to the previous screen.")
                        }
                        Text(title)
                            .font(type.display(34 * scale, weight: .bold))
                            .foregroundStyle(palette.ink)
                            .kerning(-0.6)
                        Spacer(minLength: 0)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(type.body(15 * scale, weight: .medium))
                            .foregroundStyle(palette.ink2)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)

                content()
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .background(palette.bg)
    }
}

struct Card<Content: View>: View {
    let palette: Palette
    var cornerRadius: CGFloat = 28
    var insets: EdgeInsets = .init(top: 24, leading: 22, bottom: 24, trailing: 22)
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(insets)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.card)
                    .shadow(color: .black.opacity(0.04), radius: 24, x: 0, y: 8)
            )
    }
}

struct SectionHeader: View {
    let text: String
    let palette: Palette
    let type: Typography
    let scale: Double
    var body: some View {
        Text(text.uppercased())
            .font(type.body(14 * scale, weight: .semibold))
            .kerning(0.4)
            .foregroundStyle(palette.ink2)
            .padding(.horizontal, 10)
    }
}
