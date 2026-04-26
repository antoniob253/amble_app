import SwiftUI

struct PaywallView: View {
    let palette: Palette
    let type: Typography
    let scale: Double
    let store: StoreManager
    var dismissable: Bool = false
    var onDismiss: (() -> Void)? = nil

    @State private var appear = false
    /// Non-nil when a Restore tap returned a non-success outcome —
    /// the only cases worth alerting about on a paywall, because a
    /// `.restored` result is already visible via the paywall
    /// dismissing as `hasActiveSubscription` flips true.
    @State private var restoreOutcome: RestoreOutcome?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            palette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 14) {
                    // Headline is deliberately subscription-neutral:
                    // this paywall fires both when the trial expires
                    // *and* when a paid subscription lapses, so we
                    // can't assume "trial ended" without lying to
                    // the second group.
                    Text("Welcome back\nto _Amble_.")
                        .font(type.display(40 * scale, weight: .semibold))
                        .kerning(-0.9)
                        .foregroundStyle(palette.ink)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)

                    Text("Keep walking for \(store.priceDisplay) a year, or about \(store.monthlyEquivalent) a month. Cancel anytime.")
                        .font(type.body(18 * scale, weight: .medium))
                        .foregroundStyle(palette.ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 24)
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 14)

                Spacer()

                PaywallLegal(palette: palette, type: type, scale: scale,
                             priceDisplay: store.priceDisplay,
                             mentionsTrial: false,
                             onRestore: {
                                 Task {
                                     // Only surface non-success cases —
                                     // `.restored` dismisses the paywall
                                     // automatically via the
                                     // `hasActiveSubscription` onChange in
                                     // RootView, so an alert on top of
                                     // that would be redundant noise.
                                     let outcome = await store.restore()
                                     if outcome != .restored {
                                         restoreOutcome = outcome
                                     }
                                 }
                             })
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                Button {
                    Haptics.medium()
                    Task {
                        // `.granted` is the only outcome that means
                        // the user actually unlocked the app on this
                        // tap. `.cancelled` and `.failed` both leave
                        // them on the paywall for another try.
                        if await store.purchase() == .granted {
                            onDismiss?()
                        }
                    }
                } label: {
                    Text(store.purchasing
                         ? "Processing..."
                         : "Continue for \(store.priceDisplay) a year")
                        .font(type.display(20 * scale, weight: .bold))
                        .kerning(-0.2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(palette.accent)
                        )
                        .shadow(color: palette.accent.opacity(0.4), radius: 18, x: 0, y: 8)
                }
                .buttonStyle(.pressable)
                .disabled(store.purchasing)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }

            if dismissable {
                Button {
                    Haptics.tap()
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.ink2)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(palette.card))
                        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Close")
                .accessibilityHint("Dismisses the paywall.")
                .padding(.top, 62)
                .padding(.trailing, 20)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appear = true }
        }
        .alert(
            restoreOutcome?.alertTitle ?? "",
            isPresented: Binding(
                get: { restoreOutcome != nil },
                set: { if !$0 { restoreOutcome = nil } }
            ),
            presenting: restoreOutcome
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { outcome in
            Text(outcome.alertMessage)
        }
    }
}
