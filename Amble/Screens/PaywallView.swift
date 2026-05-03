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

                    Text("Choose the plan that suits you. Cancel any time.")
                        .font(type.body(18 * scale, weight: .medium))
                        .foregroundStyle(palette.ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 24)
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 14)

                Spacer()

                // Plan chooser. Two stacked tap-to-buy cards. Yearly
                // is emphasized (filled sage button, "best value"
                // tag) because it's the higher-LTV path AND the only
                // one that carries the 7-day free trial. Monthly is
                // a quieter secondary option for users who balk at
                // the annual commit.
                VStack(spacing: 12) {
                    yearlyButton
                    monthlyButton
                }
                .padding(.horizontal, 24)

                PaywallLegal(palette: palette, type: type, scale: scale,
                             store: store,
                             // Trial-end paywall — the user has
                             // probably already burned their intro
                             // offer (Apple gates trials to one per
                             // subscription group per Apple Account),
                             // so the disclosure copy here doesn't
                             // mention the trial. The yearly button
                             // also doesn't promise the trial; if the
                             // user is somehow still trial-eligible,
                             // Apple's StoreKit sheet will surface
                             // the offer at confirmation time.
                             mentionsTrial: false,
                             onRestore: handleRestore)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
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

    // MARK: - Buttons

    /// Primary CTA. Filled sage card, two lines of price copy, an
    /// optional "best value" badge if RevenueCat returned both
    /// products and the math actually works out to a saving (we hide
    /// the badge in failure modes so we never claim a saving we
    /// can't compute).
    private var yearlyButton: some View {
        Button {
            Haptics.medium()
            Task {
                if await store.purchase(.annual) == .granted {
                    onDismiss?()
                }
            }
        } label: {
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Yearly")
                        .font(type.display(20 * scale, weight: .bold))
                        .kerning(-0.2)
                    if let saving = store.yearlyDiscountLabel {
                        Text(saving)
                            .font(type.body(13 * scale, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Color.white.opacity(0.18))
                            )
                    }
                }
                Text("\(store.annualPrice) a year · \(store.annualMonthlyEquivalent) a month")
                    .font(type.body(14 * scale, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(palette.accent)
            )
            .shadow(color: palette.accent.opacity(0.4), radius: 16, x: 0, y: 6)
        }
        .buttonStyle(.pressable)
        .disabled(store.purchasing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Yearly subscription, \(store.annualPrice) a year, about \(store.annualMonthlyEquivalent) a month")
        .accessibilityHint("Subscribes you to Amble yearly.")
        .accessibilityAddTraits(.isButton)
    }

    /// Secondary CTA. Card-coloured outline button, lighter visual
    /// weight than the yearly. Same press behaviour, no trial
    /// promise (monthly product has no intro offer in App Store
    /// Connect).
    private var monthlyButton: some View {
        Button {
            Haptics.medium()
            Task {
                if await store.purchase(.monthly) == .granted {
                    onDismiss?()
                }
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Monthly")
                    .font(type.display(18 * scale, weight: .semibold))
                    .kerning(-0.2)
                Spacer()
                Text("\(store.monthlyPrice) a month")
                    .font(type.body(15 * scale, weight: .medium))
            }
            .foregroundStyle(palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(palette.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.pressable)
        .disabled(store.purchasing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Monthly subscription, \(store.monthlyPrice) a month")
        .accessibilityHint("Subscribes you to Amble monthly.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Restore

    private func handleRestore() {
        Task {
            // Only surface non-success cases — `.restored` dismisses
            // the paywall automatically via the
            // `hasActiveSubscription` onChange in RootView, so an
            // alert on top of that would be redundant noise.
            let outcome = await store.restore()
            if outcome != .restored {
                restoreOutcome = outcome
            }
        }
    }
}
