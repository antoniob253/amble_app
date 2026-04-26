import SwiftUI

enum AppRoute: Hashable {
    case goal
    case walk(WalkSession)
    case call(CallContact)
    case sos
}

struct RootView: View {
    @Environment(Theme.self) private var theme
    @Environment(UserProfile.self) private var profile
    @Environment(HealthStore.self) private var health
    @Environment(StoreManager.self) private var store
    @Environment(NotificationManager.self) private var notifications
    @Environment(WalksStore.self) private var walks
    @Environment(WalkTracker.self) private var walkTracker
    @Environment(\.scenePhase) private var scenePhase
    // SwiftUI's review-request action — wraps StoreKit's
    // `SKStoreReviewController.requestReview` and respects Apple's
    // 3-per-365-day cap automatically. We pass it into
    // `ReviewPrompter` rather than calling it ourselves so the
    // gating logic stays testable without a SwiftUI dependency.
    @Environment(\.requestReview) private var requestReview

    @State private var tab: MainTab = .home
    @State private var route: [AppRoute] = []
    @State private var showPaywall = false
    @State private var showActiveWalk = false
    @State private var walkCallContact: CallContact?
    @State private var showWalkSOS = false
    @State private var lastCelebratedDayKey: String = ""

    var body: some View {
        let palette = theme.palette
        let type = theme.type
        let scale = theme.textScale

        ZStack(alignment: .bottom) {
            palette.bg.ignoresSafeArea()

            NavigationStack(path: $route) {
                tabContent(palette: palette, type: type, scale: scale)
                    .navigationDestination(for: AppRoute.self) { destination in
                        destinationView(for: destination, palette: palette, type: type, scale: scale)
                            .navigationBarBackButtonHidden(true)
                            .toolbar(.hidden, for: .navigationBar)
                    }
            }

            TabBar(current: $tab, palette: palette, type: type, scale: scale)
                .opacity(route.isEmpty ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: route.isEmpty)
        }
        .task {
            // Don't auto-prompt for permissions on first appearance.
            // Onboarding is the *only* place we ask; if the user said
            // "Maybe later" there, we respect that and surface
            // recovery affordances in Settings + the home screen's
            // Health card. `refresh()` is safe to call regardless of
            // auth state — it returns 0 data silently if HealthKit
            // is restricted or denied. `startLiveUpdates()` itself
            // bails early when Motion isn't yet authorized (see
            // HealthStore), so it's safe here too.
            await health.refresh()
            health.startLiveUpdates()
            await notifications.refreshStatus()
        }
        .onAppear { updatePaywall() }
        .onChange(of: store.hasActiveSubscription) { _, _ in updatePaywall() }
        // Re-evaluate when the store finishes its first load. Without
        // this, paying users see a paywall flash on cold launch:
        // `onAppear` fires before RevenueCat has returned an
        // entitlement, `hasAccess` is briefly false, and the paywall
        // pops up before `hasActiveSubscription` flips back. Gating
        // `updatePaywall()` on `loaded` (in the helper below) plus
        // re-running it here when load completes eliminates the flash.
        .onChange(of: store.loaded) { _, _ in updatePaywall() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    await health.refresh()
                    health.startLiveUpdates()
                    // Resync an in-progress walk's steps in case the app
                    // was backgrounded (e.g. during a phone call) and
                    // missed live pedometer callbacks.
                    if walkTracker.isActive {
                        await walkTracker.refresh()
                    }
                    await store.refreshEntitlements()
                    await notifications.refreshStatus()
                    updatePaywall()
                }
            case .background:
                health.stopLiveUpdates()
            default:
                break
            }
        }
        .onChange(of: health.stepsToday) { _, new in
            checkGoalCelebration(newSteps: new)
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(palette: palette, type: type, scale: scale, store: store,
                        dismissable: store.hasActiveSubscription) {
                showPaywall = false
            }
        }
        .fullScreenCover(isPresented: $showActiveWalk) {
            ActiveWalkView(
                palette: palette, type: type, scale: scale,
                userName: profile.name,
                contactFirstName: firstName(of: profile.contact.name),
                hasContact: !profile.contact.phone.isEmpty,
                tracker: walkTracker,
                onMinimize: { showActiveWalk = false },
                onEnd: {
                    Task {
                        let session = await walkTracker.stop()
                        showActiveWalk = false
                        // Drop accidental taps — a real walk has at least a
                        // few steps and more than half a minute.
                        if let session, session.steps >= 10, session.durationSeconds >= 30 {
                            walks.add(session)
                            Haptics.success()
                            // A completed walk is a delight moment too —
                            // try a review prompt now that the walk has
                            // landed in the store. The active-walk
                            // cover has just dismissed (showActiveWalk
                            // = false above), so `inCriticalFlow` is
                            // false and the gate can fire if the rest
                            // of the engagement criteria pass.
                            tryPromptForReview()
                        }
                    }
                },
                onCall: {
                    walkCallContact = CallContact(
                        name: profile.contact.name.isEmpty ? "Contact" : profile.contact.name,
                        relation: profile.contact.role.isEmpty ? "Emergency" : profile.contact.role,
                        phone: profile.contact.phone
                    )
                },
                onSOS: { showWalkSOS = true }
            )
            // Nested covers so the user can call / trigger SOS without
            // leaving the walk. Dismissing them drops back into
            // ActiveWalkView — the walk keeps running throughout.
            .fullScreenCover(item: $walkCallContact) { contact in
                CallView(palette: palette, type: type, scale: scale,
                         contact: contact,
                         onBack: { walkCallContact = nil })
            }
            .fullScreenCover(isPresented: $showWalkSOS) {
                SOSView(palette: palette, type: type, scale: scale,
                        contact: profile.contact,
                        onBack: { showWalkSOS = false })
            }
        }
    }

    @ViewBuilder
    private func tabContent(palette: Palette, type: Typography, scale: Double) -> some View {
        switch tab {
        case .home:
            HomeView(
                palette: palette, type: type, scale: scale,
                steps: health.stepsToday, goal: profile.dailyGoal,
                userName: profile.name,
                contactName: profile.contact.name,
                contactRole: profile.contact.role,
                todaysWalks: walks.today,
                // Show the home Health card whenever steps aren't
                // flowing — covers both "user said Maybe later in
                // onboarding" and "user denied" states. The card is
                // the user's path back to enabling step tracking
                // without having to dig into Settings to figure out
                // why their step count is stuck at 0.
                healthAuthorized: health.authorized,
                walkActive: walkTracker.isActive,
                walkStartDate: walkTracker.startDate,
                walkSteps: walkTracker.steps,
                onCall: {
                    let m = CallContact(
                        name: profile.contact.name.isEmpty ? "Contact" : profile.contact.name,
                        relation: profile.contact.role.isEmpty ? "Emergency" : profile.contact.role,
                        phone: profile.contact.phone
                    )
                    route.append(.call(m))
                },
                onSOS: { route.append(.sos) },
                onOpenWalk: { route.append(.walk($0)) },
                onOpenGoal: { route.append(.goal) },
                onStartOrResumeWalk: {
                    if !walkTracker.isActive {
                        walkTracker.start()
                    }
                    showActiveWalk = true
                },
                onRequestHealth: {
                    // `attemptGrant` always tries the iOS prompt
                    // (silent no-op if Apple won't re-show it), then
                    // checks whether step data is actually flowing.
                    // If after that we still can't see data and Apple
                    // won't re-prompt, the user genuinely needs to
                    // flip the toggle in the Apple Health app — NOT
                    // generic iOS Settings, which doesn't expose
                    // HealthKit access for our app at all (privacy).
                    Task {
                        let outcome = await health.attemptGrant()
                        if outcome == .settingsNeeded {
                            // Try the Health app deep-link first; the
                            // user lands one nav away from the right
                            // toggle (Profile → Apps → Amble). Fall
                            // back to generic Settings if for some
                            // reason the URL scheme isn't supported.
                            if let healthURL = URL(string: "x-apple-health://"),
                               UIApplication.shared.canOpenURL(healthURL) {
                                _ = await UIApplication.shared.open(healthURL)
                            } else if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                _ = await UIApplication.shared.open(settingsURL)
                            }
                        }
                    }
                }
            )
        case .week:
            WeekView(
                palette: palette, type: type, scale: scale,
                goal: profile.dailyGoal,
                stepsByDay: health.stepsByDay,
                recentWalks: walks.thisWeek,
                onOpenWalk: { route.append(.walk($0)) }
            )
        case .reflect:
            ReflectionsView(palette: palette, type: type, scale: scale)
        case .more:
            @Bindable var profile = profile
            SettingsView(
                palette: palette, type: type, scale: scale,
                goal: profile.dailyGoal,
                contact: $profile.contact,
                notificationsEnabled: $profile.notificationsEnabled,
                reminderHour: $profile.reminderHour,
                hasActiveSubscription: store.hasActiveSubscription,
                isInTrial: store.isInTrial,
                trialDaysRemaining: store.trialDaysRemaining,
                expirationDate: store.expirationDate,
                priceDisplay: store.priceDisplay,
                onOpenGoal: { route.append(.goal) },
                onRestart: { profile.reset() },
                onStartPurchase: { showPaywall = true },
                onManageSubscription: {
                    if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
            )
        }
    }

    @ViewBuilder
    private func destinationView(for destination: AppRoute, palette: Palette, type: Typography, scale: Double) -> some View {
        switch destination {
        case .goal:
            @Bindable var profile = profile
            GoalView(palette: palette, type: type, scale: scale,
                     goal: $profile.dailyGoal, onBack: { route.removeLast() })
        case .walk(let w):
            WalkView(palette: palette, type: type, scale: scale, walk: w,
                     onBack: { route.removeLast() })
        case .call(let m):
            CallView(palette: palette, type: type, scale: scale,
                     contact: m, onBack: { route.removeLast() })
        case .sos:
            SOSView(palette: palette, type: type, scale: scale,
                    contact: profile.contact, onBack: { route.removeLast() })
        }
    }

    /// Decides whether to show the post-trial / lapsed-subscription
    /// paywall. Gated on `store.loaded` so a paying user doesn't see a
    /// flash of the paywall during the brief window between cold
    /// launch and the first RevenueCat customer-info response.
    private func updatePaywall() {
        guard store.loaded else { return }
        showPaywall = !store.hasAccess
    }

    private func firstName(of fullName: String) -> String {
        fullName.components(separatedBy: .whitespacesAndNewlines)
            .first(where: { !$0.isEmpty }) ?? ""
    }

    /// Fires the in-app celebration when the user crosses their daily
    /// goal, deduped to once per day so the haptic doesn't repeat on
    /// subsequent step updates after the threshold. We deliberately
    /// don't push a notification here — the "Daily walking reminder"
    /// permission was granted for one specific notification and we
    /// don't piggyback other pings on top of it. The home screen's
    /// own celebration UI (ring fill, encouragement text, confetti)
    /// handles the visual reward when the user is in the app.
    ///
    /// The same dedup-per-day check that gates the haptic also gates
    /// `goalsHitCount` and the review-prompt attempt, so the engagement
    /// counter increments at most once per calendar day no matter how
    /// many step updates push us past the goal.
    private func checkGoalCelebration(newSteps: Int) {
        guard newSteps >= profile.dailyGoal else { return }
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: Date())
        let key = "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
        guard lastCelebratedDayKey != key else { return }
        lastCelebratedDayKey = key
        Haptics.success()
        profile.goalsHitCount += 1
        tryPromptForReview()
    }

    /// `true` whenever the user is in a flow we shouldn't interrupt
    /// with a system review prompt. Covers the obvious modals
    /// (paywall, active walk, in-walk SOS, in-walk call) AND any
    /// pushed destination — `.call` and `.sos` in particular are
    /// emergency flows where a "rate the app" alert would be wildly
    /// inappropriate. The `.goal` and `.walk(detail)` destinations
    /// aren't safety-critical, but a user pushed into a sub-screen
    /// is focused on a specific task; gating on `route.isEmpty`
    /// keeps the prompt to "user is on a top-level tab" moments,
    /// which is the natural place to ask anyway.
    private var inCriticalFlow: Bool {
        !route.isEmpty
            || showPaywall
            || showActiveWalk
            || showWalkSOS
            || walkCallContact != nil
    }

    /// Funnels both delight triggers (goal crossed, walk completed)
    /// into the prompter. The prompter handles all gating internally
    /// so this stays a one-liner — the only thing the call site has
    /// to know is "I just witnessed a delight moment."
    private func tryPromptForReview() {
        ReviewPrompter.tryRequest(
            profile: profile,
            walksCount: walks.sessions.count,
            requestReview: requestReview,
            inCriticalFlow: inCriticalFlow
        )
    }
}
