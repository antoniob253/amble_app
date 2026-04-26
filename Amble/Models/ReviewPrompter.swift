import Foundation
import StoreKit
import SwiftUI
// `RequestReviewAction` is defined in StoreKit (not SwiftUI, despite
// being surfaced via SwiftUI's `@Environment(\.requestReview)`).
// Both imports are needed: StoreKit for the type, SwiftUI for the
// surrounding `Task { @MainActor }` machinery.

/// Decides when to ask the user to rate Amble on the App Store.
///
/// Apple's `requestReview()` is hard-capped at 3 prompts per user
/// per 365 days, regardless of how many times we call it. We design
/// to spend all three over the user's first ~6–8 weeks, each at a
/// progressively deeper engagement milestone, with mandatory spacing
/// so they don't see two prompts in the same week.
///
/// Tier schedule:
///
///   | Tier | Engagement gate                            | Min spacing |
///   |------|--------------------------------------------|-------------|
///   |  1   | (2 goals hit OR 5 walks tracked) + ≥3 days |     —       |
///   |  2   | 7 goals hit OR 15 walks tracked            |  ≥14 days   |
///   |  3   | 21 goals hit OR 30 walks tracked           |  ≥30 days   |
///
/// Beyond tier 3 we stop asking via the system prompt; users can
/// still leave a review via the "Rate Amble" deep-link row in
/// Settings, which goes straight to the App Store and isn't subject
/// to Apple's cap.
///
/// All call sites must run on the main actor (the `@MainActor`
/// annotation enforces this) because `requestReview` is a SwiftUI
/// Environment action and `UserProfile` mutates published state.
@MainActor
enum ReviewPrompter {
    /// Lowest level of engagement we'll consider asking at — anything
    /// less and the user hasn't formed a meaningful opinion yet.
    /// Mirror these in the README if we ever expose them.
    static let tier1MinDays = 3
    static let tier1MinGoals = 2
    static let tier1MinWalks = 5

    static let tier2MinGoals = 7
    static let tier2MinWalks = 15
    static let tier2MinSpacingDays = 14

    static let tier3MinGoals = 21
    static let tier3MinWalks = 30
    static let tier3MinSpacingDays = 30

    /// Maximum prompts we'll ever fire for a single install. Mirrors
    /// Apple's per-365-day cap so we never set ourselves up to be
    /// silently swallowed.
    static let maxPromptsPerInstall = 3

    /// Try to surface the system review prompt if every gate passes.
    ///
    /// - Parameters:
    ///   - profile: The user's persisted engagement counters. The
    ///     prompter mutates `reviewRequestCount` and
    ///     `lastReviewRequestDate` in place when a prompt actually
    ///     fires.
    ///   - walksCount: Total tracked walks the user has completed
    ///     (i.e. `walks.all.count`). Passed in rather than read
    ///     from a global so this helper stays testable and free of
    ///     hidden dependencies.
    ///   - requestReview: SwiftUI's `requestReview` Environment
    ///     action, captured by the call site via
    ///     `@Environment(\.requestReview)`. Encapsulating it as a
    ///     parameter lets us avoid SwiftUI imports leaking into
    ///     non-view code paths.
    ///   - inCriticalFlow: Caller's read on whether the user is in
    ///     the middle of something we shouldn't interrupt — an
    ///     active walk modal, the SOS view, the paywall, etc.
    ///     `RootView` is the only sensible computer of this; we
    ///     don't try to figure it out from the profile alone.
    ///   - delay: Seconds to wait after gates pass before actually
    ///     firing the prompt. Defaults to 2.0 seconds — long enough
    ///     for the goal-celebration confetti (which spawns pieces
    ///     with 1.6–2.4s falls) to mostly clear, so the system
    ///     prompt arrives as a coda to the celebration rather than
    ///     interrupting it mid-bounce.
    static func tryRequest(
        profile: UserProfile,
        walksCount: Int,
        requestReview: RequestReviewAction,
        inCriticalFlow: Bool,
        delay: TimeInterval = 2.0
    ) {
        // Hard caps first — these short-circuit everything else.
        guard profile.reviewRequestCount < maxPromptsPerInstall else { return }
        guard !inCriticalFlow else { return }
        guard profile.onboarded else { return }
        guard let firstLaunch = profile.firstLaunchDate else { return }

        let now = Date()
        let daysSinceInstall = days(from: firstLaunch, to: now)
        let daysSinceLastAsk: Int? = profile.lastReviewRequestDate.map {
            days(from: $0, to: now)
        }

        // Per-tier engagement gate. Each tier looks at the count of
        // *prompts already fired*, not the count of any other state,
        // so the gates compose cleanly: ask once → tier moves up.
        let passed: Bool
        switch profile.reviewRequestCount {
        case 0:
            passed = daysSinceInstall >= tier1MinDays
                && (profile.goalsHitCount >= tier1MinGoals
                    || walksCount >= tier1MinWalks)
        case 1:
            passed = (daysSinceLastAsk ?? 0) >= tier2MinSpacingDays
                && (profile.goalsHitCount >= tier2MinGoals
                    || walksCount >= tier2MinWalks)
        case 2:
            passed = (daysSinceLastAsk ?? 0) >= tier3MinSpacingDays
                && (profile.goalsHitCount >= tier3MinGoals
                    || walksCount >= tier3MinWalks)
        default:
            passed = false
        }
        guard passed else { return }

        // Capture the tier we're about to fire BEFORE the async hop,
        // and increment the counters synchronously. If we waited to
        // increment until inside the delayed Task we'd race against
        // a second goal-celebration firing in the same window.
        profile.reviewRequestCount += 1
        profile.lastReviewRequestDate = now

        // Schedule the actual prompt after a short delay so the
        // celebration UI plays first. Capturing `requestReview` (a
        // value type) is safe across the suspension.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            requestReview()
        }
    }

    /// Calendar-day distance, ignoring time-of-day. Two timestamps in
    /// the same calendar day return 0. Used so "≥3 days since
    /// install" doesn't accidentally require 72 wall-clock hours —
    /// a user who installs at 11pm Monday and qualifies on Thursday
    /// morning should pass the gate, not be made to wait until
    /// Thursday night.
    private static func days(from start: Date, to end: Date) -> Int {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: end)
        return cal.dateComponents([.day], from: startDay, to: endDay).day ?? 0
    }
}

/// App Store metadata — single source of truth for the numeric ID
/// that powers the deep-link "Rate Amble" row in Settings. Apple
/// assigns this when an app first ships; ours is 6763747103.
enum AppStoreMeta {
    static let appID = "6763747103"

    /// Deep-link straight into the App Store's "Write a review"
    /// composer for Amble. Bypasses the in-app prompt entirely and
    /// is NOT subject to Apple's 3-per-365-day cap, so the Settings
    /// row stays useful for proactive reviewers and for users whose
    /// in-app prompts have been globally disabled in iOS Settings.
    static var writeReviewURL: URL {
        URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review")!
    }
}
