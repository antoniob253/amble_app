import SwiftUI
import RevenueCat

@main
struct AmbleApp: App {
    @State private var theme = Theme()
    @State private var profile = UserProfile()
    @State private var health = HealthStore()
    @State private var store = StoreManager()
    @State private var location = LocationManager()
    @State private var notifications = NotificationManager()
    @State private var walks = WalksStore()
    @State private var walk = WalkTracker()

    init() {
        // RevenueCat SDK configuration. Must run before any
        // `Purchases.shared` access — `StoreManager.init()` is empty
        // by design so it doesn't trip this requirement before we
        // get here. The `@State` initializers above run as part of
        // the implicit memberwise init that fires before this body,
        // but none of them touch `Purchases.shared` (verified in
        // their respective files).
        //
        // We gate on `RevenueCatConfig.isConfigured` so a fresh
        // checkout — before the developer has populated the API key —
        // doesn't crash. In that mode `Purchases.isConfigured` stays
        // false and `StoreManager` no-ops gracefully; the DEBUG
        // escape hatch in onboarding lets dev reach the rest of the
        // app while the dashboard is being set up.
        if RevenueCatConfig.isConfigured {
            #if DEBUG
            Purchases.logLevel = .debug
            #else
            Purchases.logLevel = .info
            #endif
            Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)

            // Apple Search Ads (Apple Ads) attribution. The
            // RevenueCat SDK does not enable this by default — we
            // have to opt in explicitly by calling this method
            // after `Purchases.configure(...)`. Once enabled, the
            // SDK fetches Apple's privacy-preserving AdServices
            // attribution token at first launch and forwards it to
            // RevenueCat's backend, which attributes downstream
            // subscription events (trial starts, paid conversions,
            // renewals, churn) to the Apple Ads campaign and
            // keyword that drove the install.
            //
            // This is the metric that matters for measuring ASA
            // ROI — Apple's own ads dashboard only reports
            // installs / CPI; cost-per-paying-subscriber lives in
            // RevenueCat's charts once this attribution is wired
            // up. Token collection takes up to 7 days to fully
            // propagate after a user installs.
            //
            // Privacy note: AdServices is Apple's own framework,
            // not a third-party tracker. It does NOT require an
            // ATT (App Tracking Transparency) prompt and does NOT
            // count as "tracking" under Apple's privacy
            // definitions. Our PrivacyInfo.xcprivacy and App Store
            // Connect privacy questionnaire don't need updating
            // for this addition.
            Purchases.shared.attribution.enableAdServicesAttributionTokenCollection()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(theme)
                .environment(profile)
                .environment(health)
                .environment(store)
                .environment(location)
                .environment(notifications)
                .environment(walks)
                .environment(walk)
                // Amble is a light-only app. The whole visual language
                // (cream backgrounds, warm Fraunces on paper) is built
                // for one appearance — `.ultraThinMaterial` on the tab
                // bar, system alerts, pickers, and context menus would
                // otherwise flip when iOS switches to dark mode in the
                // evening, producing a muddy / dark palette that
                // doesn't fit the app's tone.
                .preferredColorScheme(.light)
                .task {
                    await store.load()
                    await notifications.refreshStatus()
                    // Clean up any Live Activities left over from a previous
                    // run (e.g. the app was killed mid-walk).
                    await WalkTracker.clearStaleActivities()
                }
        }
    }
}

struct ContentView: View {
    @Environment(UserProfile.self) private var profile
    @Environment(Theme.self) private var theme

    var body: some View {
        ZStack {
            theme.palette.bg.ignoresSafeArea()
            if profile.onboarded {
                RootView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: profile.onboarded)
    }
}
