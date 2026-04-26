import Foundation
import Observation
import RevenueCat

/// Result of a purchase attempt. The onboarding paywall and the
/// trial-ended paywall both branch on this so they can distinguish
/// between "user cancelled the StoreKit sheet" (just stay on the
/// paywall) and "the SDK actually failed" (in DEBUG, fall back to
/// the dev escape hatch).
enum PurchaseOutcome {
    /// Apple confirmed the purchase and RevenueCat granted the
    /// `premium` entitlement. `hasAccess` is now true.
    case granted
    /// User dismissed the StoreKit sheet. Not an error — most users
    /// who tap into the paywall do this at least once before
    /// committing.
    case cancelled
    /// The SDK threw, the offering wasn't available, or the
    /// purchase succeeded but the entitlement didn't materialise.
    /// Treated as a transient / configuration problem; in DEBUG the
    /// onboarding paywall offers a way past it so the rest of the
    /// app stays testable.
    case failed
}

/// Result of a restore attempt. Drives the post-tap alert so the
/// user always sees feedback for an action they explicitly invoked
/// (silent failure on a Restore tap reads as "is this thing
/// broken?").
enum RestoreOutcome: Identifiable {
    /// `hasActiveSubscription` is true after the restore — either
    /// because we just recovered a previous purchase, or because the
    /// user already had access and tapped Restore out of habit.
    /// Either way the right message is "you're good."
    case restored
    /// The restore succeeded but Apple returned no active
    /// subscriptions tied to this Apple Account. Common when the
    /// user signed in with the wrong Apple ID, or just curious-
    /// tapped Restore on a fresh install.
    case nothingToRestore
    /// SDK / network error. Distinct from `nothingToRestore` because
    /// the right user action is to retry, not to switch Apple IDs.
    case failed

    /// Stable identity for `.alert(_:isPresented:presenting:...)`.
    /// SwiftUI uses this to know when the presented value has changed.
    var id: Self { self }

    var alertTitle: String {
        switch self {
        case .restored:         return "You're all set"
        case .nothingToRestore: return "Nothing to restore"
        case .failed:           return "Restore didn't work"
        }
    }

    var alertMessage: String {
        switch self {
        case .restored:
            return "Your Amble subscription is active."
        case .nothingToRestore:
            return "We couldn't find an Amble subscription on this Apple Account. If you bought it with a different Apple ID, sign in with that one and try again."
        case .failed:
            return "Something went wrong. Please check your connection and try again."
        }
    }
}

/// Wraps RevenueCat for the rest of the app. Public API is intentionally
/// stable across the StoreKit 2 → RevenueCat migration so call sites
/// (PaywallView, OnboardingView, SettingsView, RootView) didn't have to
/// change. RevenueCat is used here for two reasons:
///
///   1. Cross-device entitlement sync without us running our own server.
///   2. Easier paywall A/B testing and trial-conversion analytics from
///      the RevenueCat dashboard rather than reading Apple's reports.
///
/// RevenueCat 5.x uses StoreKit 2 internally and respects the local
/// `Amble.storekit` configuration file in DEBUG builds, so simulator
/// testing keeps working — provided RevenueCat is also configured in
/// the dashboard with a matching offering / entitlement.
///
/// Configuration responsibilities are split:
///   - `Purchases.configure(...)` happens once in `AmbleApp.init()`,
///     before any view (or this manager) reaches `Purchases.shared`.
///   - This manager assumes RevenueCat is already configured by the
///     time `load()` runs, but guards every call with
///     `Purchases.isConfigured` so a missing API key during early
///     development doesn't crash the app — the DEBUG escape hatch
///     (`isDebugUnlocked`) keeps the rest of the app reachable.
@Observable
@MainActor
final class StoreManager {
    /// RevenueCat entitlement identifier. Must match the entitlement
    /// configured in the RevenueCat dashboard. Convention: "premium".
    static let entitlementId = "premium"

    /// The annual package surfaced to the user. Pulled from the
    /// "current" offering in the RevenueCat dashboard at load time.
    /// We don't enforce a specific package identifier here so the
    /// dashboard can rename / re-tier the offering without a code
    /// change — we just ask for whichever package RC marks as
    /// `.annual`, falling back to the first package if the offering
    /// doesn't expose an annual slot.
    private(set) var package: Package?

    /// `true` while a purchase is in flight. Drives the button label
    /// ("Processing...") and disables tap-through.
    private(set) var purchasing: Bool = false

    /// User has an active (non-expired, non-revoked) entitlement.
    private(set) var hasActiveSubscription: Bool = false
    /// The active entitlement is currently inside the introductory
    /// free-trial period. RevenueCat reports this as
    /// `entitlement.periodType == .trial`.
    private(set) var isInTrial: Bool = false
    /// When the current paid period or trial ends.
    private(set) var expirationDate: Date?

    /// `true` after the first `load()` call has finished — used by
    /// RootView to suppress the paywall flash that would otherwise
    /// happen on cold launch (paywall fires before RevenueCat has
    /// returned an entitlement, even for paid users).
    private(set) var loaded: Bool = false

    // Listener task for RevenueCat's `customerInfoStream` — keeps
    // entitlement state live across server-pushed updates (e.g.
    // refunds, cross-device subscription changes, expirations).
    @ObservationIgnored private var infoStreamTask: Task<Void, Never>?

    #if DEBUG
    /// Dev escape hatch for simulator testing without a configured
    /// RevenueCat dashboard. Flipped on by the onboarding paywall when
    /// `purchase()` returns no entitlement so the rest of the app is
    /// reachable. NEVER flip this from production code — only the
    /// onboarding paywall, behind `#if DEBUG`.
    var isDebugUnlocked: Bool = false
    #endif

    /// Primary access gate. `true` whenever the user has a valid
    /// entitlement (trial or paid). `false` triggers the paywall in
    /// RootView.
    var hasAccess: Bool {
        #if DEBUG
        if isDebugUnlocked { return true }
        #endif
        return hasActiveSubscription
    }

    /// Days left in the trial, ceiling-rounded so a fresh trial reads
    /// "7 days remaining" for the entire first 24 hours, "6 days
    /// remaining" for the next 24 hours, and so on. Returns 0 only
    /// when there's strictly less than a full day left, which the
    /// Settings card translates into "Ends later today."
    ///
    /// `Calendar.dateComponents([.day], ...)` was the previous
    /// implementation but it FLOORS the result — that flipped the
    /// label from "7 days" to "6 days" within an hour of starting
    /// the trial, which felt like a bug to users.
    var trialDaysRemaining: Int {
        guard isInTrial, let end = expirationDate else { return 0 }
        let secondsRemaining = end.timeIntervalSinceNow
        // Strictly less than 24h left — let the UI flip to
        // "Ends later today." Also catches the moment after
        // expiration before the customerInfo stream refresh.
        guard secondsRemaining >= 86_400 else { return 0 }
        return Int((secondsRemaining / 86_400).rounded(.up))
    }

    /// Localised price string for the annual package, with a sane
    /// fallback used before the RevenueCat product fetch returns (and
    /// in unconfigured / failure modes). Fallback matches our App
    /// Store Connect base price ($24.99/year) so users on a slow
    /// connection see the correct number even before products load.
    var priceDisplay: String {
        package?.storeProduct.localizedPriceString ?? "$24.99"
    }

    /// "$2.08 a month" style price for marketing copy (annual / 12).
    /// Reuses the StoreProduct's own price formatter end-to-end so
    /// every locale-specific quirk (currency code position, decimal
    /// separator, grouping) matches the storefront the user sees in
    /// the StoreKit sheet. Fallback ($2.08) is $24.99 / 12 to match
    /// the priceDisplay fallback.
    var monthlyEquivalent: String {
        guard let product = package?.storeProduct else { return "$2.08" }
        let monthly = NSDecimalNumber(decimal: product.price / 12)
        guard let formatter = product.priceFormatter,
              let formatted = formatter.string(from: monthly)
        else { return "$2.08" }
        return formatted
    }

    init() {
        // Intentionally empty. `Purchases.shared` is unsafe to touch
        // before `Purchases.configure(...)` has run, and configure
        // happens in `AmbleApp.init()` AFTER `@State` initializers
        // (which include this one). All RC calls are deferred to
        // `load()`, which runs from the AmbleApp `.task` modifier.
    }

    deinit { infoStreamTask?.cancel() }

    /// Called once at app launch from `AmbleApp.task`. Fetches the
    /// current offering, refreshes entitlements, and starts the live
    /// customer-info stream. Safe to call multiple times — the
    /// stream listener self-guards via `infoStreamTask == nil`.
    func load() async {
        guard Purchases.isConfigured else {
            // No API key configured yet. Mark as loaded so the paywall
            // gate stops waiting (the DEBUG escape hatch can take it
            // from here in development).
            loaded = true
            return
        }

        startCustomerInfoStream()

        // Offerings (products) — needed for prices and the purchase
        // call. `fetchOffering` is best-effort and called again on
        // demand from `purchase()` if it failed here, so a flaky
        // first launch self-heals as soon as the user taps the
        // purchase button.
        await fetchOffering()

        // Entitlement state — drives `hasAccess` and the trial UI.
        await refreshEntitlements()

        loaded = true
    }

    /// Drives the paywall purchase button. Returns a `PurchaseOutcome`
    /// the caller can branch on so cancellation isn't conflated with
    /// real failures. Never throws — RC errors are folded into
    /// `.failed`.
    ///
    /// Re-entry safe: if a purchase is already in flight we drop the
    /// extra call instead of letting two StoreKit sheets race.
    /// Self-healing: if `package` is nil because the initial
    /// `load()` couldn't reach RevenueCat (e.g. cold-launch on a
    /// flaky network), we retry the offering fetch here on demand
    /// before declaring failure — without this retry, a single
    /// dropped network packet could permanently strand the user on
    /// the onboarding paywall until they killed the app.
    func purchase() async -> PurchaseOutcome {
        guard !purchasing else { return .failed }
        guard Purchases.isConfigured else { return .failed }

        if package == nil {
            await fetchOffering()
        }
        guard let package else { return .failed }

        purchasing = true
        defer { purchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            applyCustomerInfo(result.customerInfo)

            if result.userCancelled {
                Haptics.warning()
                return .cancelled
            }

            // Belt-and-braces — confirm the entitlement actually
            // landed before reporting `.granted`. If StoreKit
            // accepted the payment but the entitlement is missing
            // (very rare RC dashboard mis-config) we treat it as
            // failure so the caller doesn't transition the UI.
            if hasActiveSubscription {
                Haptics.success()
                return .granted
            }
            return .failed
        } catch {
            return .failed
        }
    }

    /// Used by the paywall's "Restore" footer link and the Settings
    /// "Restore purchase" row. Triggers an Apple-Account-scoped
    /// restore via RevenueCat, which in turn hits Apple's servers
    /// for any prior subscriptions.
    ///
    /// Returns a `RestoreOutcome` so callers can give explicit
    /// feedback. Re-entry-guarded against the `purchasing` flag so a
    /// Restore tap can't race with an in-flight Purchase tap; that
    /// race condition surfaces as `.failed` to the caller.
    func restore() async -> RestoreOutcome {
        guard !purchasing, Purchases.isConfigured else { return .failed }
        do {
            let info = try await Purchases.shared.restorePurchases()
            applyCustomerInfo(info)
            // The outcome is judged purely by whether the user has
            // access AFTER the call. Catches both "we recovered a
            // prior purchase" and "they were already subscribed and
            // tapped Restore anyway" — both deserve the reassuring
            // "you're all set" message.
            return hasActiveSubscription ? .restored : .nothingToRestore
        } catch {
            return .failed
        }
    }

    /// Pulls the latest customer info from RevenueCat and applies it
    /// to the published entitlement state. Called on app foreground
    /// (RootView scenePhase) and after a purchase.
    func refreshEntitlements() async {
        guard Purchases.isConfigured else { return }
        do {
            let info = try await Purchases.shared.customerInfo()
            applyCustomerInfo(info)
        } catch {
            // Best effort — leave existing state in place rather than
            // wiping `hasActiveSubscription` to false on a transient
            // network failure (which would briefly punt the user to
            // the paywall).
        }
    }

    // MARK: - Internals

    /// Pulls the current offering from RevenueCat and binds the
    /// annual package. Best-effort — if the network is unavailable
    /// or the RC dashboard hasn't been configured yet we leave
    /// `package` at its previous value (nil on first launch).
    /// Called from `load()` and again on-demand from `purchase()`.
    private func fetchOffering() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            if let current = offerings.current {
                // Prefer the canonical `.annual` slot — the RC
                // dashboard exposes one; if Amble's offering doesn't
                // mark a package as annual, take the first available
                // package as a graceful fallback.
                package = current.annual ?? current.availablePackages.first
            }
        } catch {
            // Leave `package` as-is. Caller handles the nil case.
        }
    }

    /// Starts the long-lived customer-info listener. RevenueCat
    /// pushes updates here when entitlement state changes server-
    /// side (refunds, family-sharing changes, renewals on another
    /// device). Idempotent — safe to call from `load()` repeatedly.
    ///
    /// The Task inherits StoreManager's `@MainActor` isolation, so
    /// `applyCustomerInfo` runs on the main actor without an
    /// explicit hop.
    private func startCustomerInfoStream() {
        guard infoStreamTask == nil else { return }
        infoStreamTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                self?.applyCustomerInfo(info)
            }
        }
    }

    /// Maps RevenueCat's `CustomerInfo` to our local entitlement
    /// state. The `entitlementId` ("premium") must match the
    /// entitlement configured in the RC dashboard — typo here is
    /// the most common reason a real subscription doesn't unlock
    /// the app.
    private func applyCustomerInfo(_ info: CustomerInfo) {
        let entitlement = info.entitlements[Self.entitlementId]
        hasActiveSubscription = entitlement?.isActive ?? false
        isInTrial = entitlement?.periodType == .trial
        expirationDate = entitlement?.expirationDate
    }
}
