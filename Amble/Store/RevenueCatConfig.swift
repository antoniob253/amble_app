import Foundation

/// One-stop home for RevenueCat configuration. Kept separate from
/// `StoreManager` so the API key — the most-likely-to-need-rotation
/// piece — has an obvious place to live.
///
/// **Setup checklist** (do these in the RevenueCat dashboard, not
/// code):
///   1. Create a RevenueCat project, attach Amble's App Store Connect
///      app to it (you'll be asked for the App Store Connect
///      In-App Purchase shared secret).
///   2. Create an *Entitlement* with identifier `premium`. This must
///      match `StoreManager.entitlementId` exactly — typos are the
///      single most common cause of "I subscribed but the app still
///      shows the paywall."
///   3. Create a *Product* in RevenueCat that points to the App Store
///      Connect product `com.antoniobaltic.amble.yearly` (auto-renewing
///      subscription, 1 year, with a 7-day introductory free trial).
///   4. Attach that product to the `premium` entitlement.
///   5. Create an *Offering* (e.g. `default`), mark it Current, and
///      add a Package using the `Annual` template — `StoreManager`
///      asks RC for `current.annual`, falling back to the first
///      available package, so the package's identifier itself doesn't
///      have to be a specific string.
///   6. Copy the iOS API key from Project Settings → API Keys (it
///      starts with `appl_`) and paste it into `apiKey` below.
///
/// Until you do step 6, the app still runs — `StoreManager` sees the
/// placeholder, skips `Purchases.configure(...)`, and `Purchases.isConfigured`
/// stays false so all RevenueCat calls no-op gracefully. In DEBUG the
/// onboarding paywall's escape hatch unlocks the rest of the app.
enum RevenueCatConfig {
    /// iOS public API key from RevenueCat dashboard
    /// (Project Settings → API Keys → "Public app-specific API keys"
    /// → Apple App Store, NOT the secret API key).
    ///
    /// Replace the placeholder when you set up RevenueCat. Detection
    /// is intentionally string-based so a forgotten key shows up loudly
    /// at first launch instead of silently configuring with junk.
    static let apiKey: String = "appl_HSNFmRknSgyuERGaDbcweWXpGli"

    /// `true` only when `apiKey` has been populated with a real value.
    /// `AmbleApp.init()` reads this to decide whether to configure the
    /// SDK at all.
    static var isConfigured: Bool {
        !apiKey.contains("YOUR_REVENUECAT_API_KEY")
    }
}
