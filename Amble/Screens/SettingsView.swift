import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(NotificationManager.self) private var notifications
    @Environment(HealthStore.self) private var health
    @Environment(LocationManager.self) private var location
    // Pulled in directly (rather than via an `onRestore` closure
    // from RootView) so we can capture the outcome and surface a
    // confirmation alert. RootView still owns the other store-
    // adjacent closures (`onStartPurchase`, `onManageSubscription`)
    // because those involve presenting other views, not just calling
    // a method.
    @Environment(StoreManager.self) private var store

    let palette: Palette
    let type: Typography
    let scale: Double
    let goal: Int
    @Binding var contact: EmergencyContact
    @Binding var notificationsEnabled: Bool
    @Binding var reminderHour: Int
    let hasActiveSubscription: Bool
    let isInTrial: Bool
    let trialDaysRemaining: Int
    let expirationDate: Date?
    let priceDisplay: String
    let onOpenGoal: () -> Void
    let onRestart: () -> Void
    let onStartPurchase: () -> Void
    let onManageSubscription: () -> Void

    @State private var editingContact = false
    @State private var showingTimePicker = false
    @State private var showingNotificationSettingsAlert = false
    @State private var showingStartOverAlert = false
    /// Drives the post-Restore-tap alert. Unlike on the paywall, we
    /// surface ALL outcomes here — the user is past the access gate,
    /// so nothing visually changes from the row alone, and silent-
    /// success would read as "did my tap register?"
    @State private var restoreOutcome: RestoreOutcome?

    var body: some View {
        // Top-level tab screen — the tab bar owns navigation back, so
        // ScreenShell renders without a chevron. The Settings title
        // uses the same 34pt display-bold treatment as `This Week`
        // and `Today's Thought` for a cohesive tab-bar story.
        ScreenShell(title: "Settings", palette: palette, type: type, scale: scale) {
            VStack(alignment: .leading, spacing: 18) {
                // Status callouts — rendered above the setting groups
                // because they either celebrate (active subscription)
                // or flag a problem that blocks app features (Health
                // permission missing). Location-denied has moved into
                // the Emergency group below, since it's semantically
                // part of emergency setup.
                subscriptionCard

                // Show the Health callout whenever steps aren't
                // flowing — covers both "skipped onboarding" and
                // "denied" states. Previously it only showed for
                // `authorizationDetermined`, so users who tapped
                // "Maybe later" never saw a recovery path here.
                if !health.authorized {
                    healthDeniedRow
                }

                walkingGroup
                emergencyGroup
                subscriptionGroup
                aboutGroup
            }
        }
        .sheet(isPresented: $editingContact) {
            EditEmergencyContactSheet(
                palette: palette, type: type, scale: scale,
                contact: contact,
                onSave: { new in contact = new; Haptics.success(); editingContact = false },
                onCancel: { editingContact = false }
            )
            // Half-height by default so the compact two-card layout
            // sits naturally without empty space at the bottom; iOS
            // auto-promotes to `.large` when the keyboard appears so
            // the Phone / Name field stays visible above the keys.
            // No drag indicator — Cancel / Save in the header is the
            // explicit dismiss affordance, and matching the Reminder
            // time sheet keeps the two settings sheets visually
            // consistent.
            .presentationDetents([.medium, .large])
        }
        .alert("Reminders are off", isPresented: $showingNotificationSettingsAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) { }
        } message: {
            Text("To turn on your daily walking reminder, enable notifications for Amble in the Settings app.")
        }
        .alert("Start over?", isPresented: $showingStartOverAlert) {
            Button("Start over", role: .destructive) {
                Haptics.warning()
                onRestart()
            }
            Button("Keep everything", role: .cancel) { }
        } message: {
            Text("This clears your name, goal, contact, and walking history, and takes you back to the setup screens. This can't be undone.")
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
        .sheet(isPresented: $showingTimePicker) {
            ReminderTimeSheet(
                palette: palette, type: type, scale: scale,
                hour: reminderHour,
                onSave: { h in
                    reminderHour = h
                    notifications.scheduleDailyReminder(hour: h)
                    Haptics.success()
                    showingTimePicker = false
                },
                onCancel: { showingTimePicker = false }
            )
            .presentationDetents([.height(340)])
        }
    }

    // MARK: - Groups

    /// Everything about walks goes here: the daily goal, the reminder
    /// toggle, and (when the reminder is on) the time picker. Three
    /// items sharing one roof feels less lonely than the previous
    /// single-item Walking / Reminders split.
    private var walkingGroup: some View {
        SettingGroup(label: "Walking", palette: palette, type: type, scale: scale) {
            SettingRow(icon: "figure.walk", tint: palette.accent,
                       title: "Daily goal",
                       detail: "\(StepFormat.int(goal)) steps",
                       palette: palette, type: type, scale: scale,
                       action: onOpenGoal)

            Divider().background(Color.black.opacity(0.06)).padding(.leading, 58)

            ToggleRow(
                icon: "bell.fill", tint: palette.accent2,
                title: "Daily walking reminder",
                isOn: Binding(
                    get: { notificationsEnabled && notifications.authorized },
                    set: { new in
                        Haptics.select()
                        Task {
                            if new {
                                // A second requestAuthorization call
                                // returns false silently if iOS already
                                // recorded a denial — route to Settings
                                // instead so the user can actually
                                // turn it back on.
                                if notifications.isDenied {
                                    showingNotificationSettingsAlert = true
                                    return
                                }
                                let granted = await notifications.requestAuthorization()
                                notificationsEnabled = granted
                                if granted {
                                    notifications.scheduleDailyReminder(hour: reminderHour)
                                } else if notifications.isDenied {
                                    showingNotificationSettingsAlert = true
                                }
                            } else {
                                notificationsEnabled = false
                                notifications.cancelDailyReminder()
                            }
                        }
                    }
                ),
                palette: palette, type: type, scale: scale
            )
            if notificationsEnabled && notifications.authorized {
                Divider().background(Color.black.opacity(0.06)).padding(.leading, 58)
                SettingRow(icon: "clock.fill", tint: palette.accent,
                           title: "Reminder time",
                           detail: reminderTimeLabel,
                           palette: palette, type: type, scale: scale,
                           action: { showingTimePicker = true })
            }

            // Motion (CMPedometer) recovery row — surfaces explicitly
            // so users who skipped during onboarding can see and
            // enable it from here, separately from Apple Health. Only
            // shown when motion isn't authorized; once granted, the
            // row disappears.
            if !health.motionAuthorized {
                Divider().background(Color.black.opacity(0.06)).padding(.leading, 58)
                SettingRow(
                    icon: "figure.walk.motion",
                    tint: palette.accent2,
                    title: health.motionDetermined
                           ? "Motion access is off"
                           : "Allow live step updates",
                    detail: "Off",
                    palette: palette, type: type, scale: scale,
                    action: handleMotionPermissionTap
                )
            }
        }
    }

    /// Tap handler for the Motion permission row. CMPedometer's
    /// auth state is reliable: notDetermined → fire iOS prompt;
    /// denied / restricted → route to iOS Settings (only path back
    /// once denied).
    private func handleMotionPermissionTap() {
        Task {
            let outcome = await health.attemptGrantMotion()
            if outcome == .settingsNeeded {
                openIOSSettings()
            }
        }
    }

    /// Emergency setup — contact + location sharing. Location lives
    /// inline here so it's obvious the two work together (location is
    /// only used during an SOS to share your place with the contact).
    /// The location row appears whenever the permission isn't granted
    /// — covers both "skipped onboarding" (notDetermined) and
    /// "denied" states. Tap action adapts: if we've never asked, we
    /// surface the iOS prompt directly; if we've asked and been
    /// denied, we route to iOS Settings (the only path back to grant
    /// after denial).
    private var emergencyGroup: some View {
        SettingGroup(label: "Emergency", palette: palette, type: type, scale: scale) {
            SettingRow(icon: "exclamationmark.circle.fill", tint: palette.danger,
                       title: "Emergency contact",
                       detail: contact.isValid ? contact.name : "Not set",
                       palette: palette, type: type, scale: scale,
                       action: { editingContact = true })

            if !location.isAuthorized {
                Divider().background(Color.black.opacity(0.06)).padding(.leading, 58)
                SettingRow(icon: "location.slash.fill", tint: palette.danger,
                           title: "Location sharing",
                           detail: "Off",
                           palette: palette, type: type, scale: scale,
                           action: handleLocationPermissionTap)
            }
        }
    }

    /// Tapping "Location sharing — Off". If we've never asked the
    /// user (`!isDetermined`, i.e. they skipped during onboarding),
    /// trigger the iOS prompt now. Otherwise we've been denied and
    /// the system won't re-prompt — route to iOS Settings.
    private func handleLocationPermissionTap() {
        if location.isDetermined {
            openIOSSettings()
        } else {
            Task { await location.requestAuthorization() }
        }
    }

    /// Billing actions kept together so the user can find them without
    /// hunting. Under an active subscription: Manage + Restore. Under
    /// no subscription: Subscribe + Restore.
    private var subscriptionGroup: some View {
        SettingGroup(label: "Subscription", palette: palette, type: type, scale: scale) {
            if hasActiveSubscription {
                SettingRow(icon: "creditcard.fill", tint: palette.accent,
                           title: "Manage subscription", detail: nil,
                           palette: palette, type: type, scale: scale,
                           action: onManageSubscription)
            } else {
                SettingRow(icon: "sparkles", tint: palette.accent,
                           title: "Subscribe",
                           detail: priceDisplay + "/yr",
                           palette: palette, type: type, scale: scale,
                           action: onStartPurchase)
            }
            Divider().background(Color.black.opacity(0.06)).padding(.leading, 58)
            SettingRow(icon: "arrow.clockwise", tint: palette.accent,
                       title: "Restore purchase", detail: nil,
                       palette: palette, type: type, scale: scale,
                       action: {
                           Task {
                               // Surface every outcome, including
                               // success — the row triggers no other
                               // visible change in Settings, so a
                               // silent tap reads as broken.
                               restoreOutcome = await store.restore()
                           }
                       })
        }
    }

    /// App information, the proactive "Rate Amble" link, and the
    /// destructive "Start over" action. Start over lives here
    /// (rather than in a scarier standalone position) because it's
    /// not something users reach for often — it should be available
    /// but not emphasised. The confirmation alert catches accidental
    /// taps.
    private var aboutGroup: some View {
        SettingGroup(label: "About", palette: palette, type: type, scale: scale) {
            SettingRow(icon: "info.circle.fill", tint: .blue,
                       title: "Version", detail: "1.0.0",
                       palette: palette, type: type, scale: scale,
                       chevron: false, action: nil)
            Divider().background(Color.black.opacity(0.06)).padding(.leading, 58)
            // Self-service path to leave a review. Bypasses the
            // in-app SKStoreReview prompt and is NOT subject to
            // Apple's 3-per-365-day cap, so it stays useful for
            // proactive reviewers and for users whose in-app
            // prompts have been globally disabled in iOS Settings.
            SettingRow(icon: "star.fill", tint: palette.accent,
                       title: "Rate Amble", detail: nil,
                       palette: palette, type: type, scale: scale,
                       action: {
                           UIApplication.shared.open(AppStoreMeta.writeReviewURL)
                       })
            Divider().background(Color.black.opacity(0.06)).padding(.leading, 58)
            SettingRow(icon: "arrow.counterclockwise", tint: palette.accent2,
                       title: "Start over", detail: nil,
                       palette: palette, type: type, scale: scale,
                       action: { showingStartOverAlert = true })
        }
    }

    // MARK: - Helpers

    /// Generic iOS Settings deep-link — used for permissions that
    /// actually appear under `Settings → Amble` (Location, Camera,
    /// etc.). NOT the right destination for HealthKit, see
    /// `openHealthSettings` below.
    private func openIOSSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Apple's HealthKit read-access toggles live in the Apple Health
    /// app (Profile → Apps → Amble), NOT in `Settings → Amble`. The
    /// generic settings page doesn't even show a Health row — Apple
    /// hides it for privacy. Pointing a stuck user there leaves them
    /// looking for a toggle that isn't visible anywhere on that
    /// screen. Opening the Health app drops them one nav step from
    /// the right place.
    ///
    /// Falls back to generic settings only if the Health app URL
    /// scheme isn't supported (very old iOS, or device without
    /// Health installed for some reason).
    private func openHealthSettings() {
        if let healthURL = URL(string: "x-apple-health://"),
           UIApplication.shared.canOpenURL(healthURL) {
            UIApplication.shared.open(healthURL)
        } else {
            openIOSSettings()
        }
    }

    private var reminderTimeLabel: String {
        var comps = DateComponents()
        comps.hour = reminderHour
        let date = Calendar.current.date(from: comps) ?? Date()
        return AmbleDates.formatter(format: "h:00 a").string(from: date)
    }

    // MARK: - Status callouts

    @ViewBuilder
    private var subscriptionCard: some View {
        if hasActiveSubscription {
            HStack(spacing: 14) {
                Image(systemName: isInTrial ? "hourglass" : "checkmark.seal.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isInTrial ? "Free trial active" : "Amble — Yearly")
                        .font(type.display(19 * scale, weight: .bold))
                        .foregroundStyle(palette.ink)
                    Text(detailLine)
                        .font(type.body(14 * scale, weight: .medium))
                        .foregroundStyle(palette.ink2)
                }
                Spacer()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(palette.soft)
            )
        }
    }

    private var detailLine: String {
        if isInTrial {
            return trialDaysRemaining == 0
                ? "Ends later today"
                : "\(trialDaysRemaining) day\(trialDaysRemaining == 1 ? "" : "s") remaining"
        }
        if let end = expirationDate {
            return "Renews on \(AmbleDates.formatter(dateStyle: .long).string(from: end))"
        }
        return "Active"
    }

    /// Health permission callout. Adapts to whether we've asked
    /// before:
    ///
    /// - **notDetermined** (user skipped onboarding): friendly copy
    ///   ("Allow step tracking"), tap surfaces the iOS prompt
    ///   directly + primes Motion + starts live updates in one go.
    ///   Trailing chevron is the right-arrow (in-app action).
    ///
    /// - **determined but unauthorized** (user denied): explains
    ///   the situation ("Health access is off"), tap routes to iOS
    ///   Settings — the only place a denied HealthKit permission
    ///   can be flipped back on. Trailing icon is the
    ///   open-in-other-app arrow.
    private var healthDeniedRow: some View {
        Button {
            Haptics.tap()
            // `attemptGrant` always tries the iOS prompt first (silent
            // no-op if iOS won't re-prompt). If after that we *still*
            // can't read step data and Apple says it won't ask again,
            // the user genuinely needs to flip a toggle in the Apple
            // Health app — not generic iOS Settings, which doesn't
            // show HealthKit access for our app. `openHealthSettings`
            // routes there directly.
            Task {
                let outcome = await health.attemptGrant()
                if outcome == .settingsNeeded {
                    openHealthSettings()
                }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(palette.danger)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12).fill(palette.danger.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(health.authorizationDetermined
                         ? "Health access is off"
                         : "Allow step tracking")
                        .font(type.display(16 * scale, weight: .bold))
                        .foregroundStyle(palette.ink)
                    // Two distinct copy paths: pre-prompt vs
                    // post-denial. Post-denial directs to the Apple
                    // Health app explicitly because the toggle isn't
                    // in `Settings → Amble` — Apple keeps HealthKit
                    // access under the Health app's own profile.
                    Text(health.authorizationDetermined
                         ? "Open Apple Health → your profile → Apps → Amble to turn it on."
                         : "Tap to share your daily steps with Amble.")
                        .font(type.body(13 * scale, weight: .medium))
                        .foregroundStyle(palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: health.authorizationDetermined
                      ? "arrow.up.right.square"
                      : "chevron.right")
                    .font(.system(size: health.authorizationDetermined ? 17 : 14, weight: .semibold))
                    .foregroundStyle(palette.ink2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24).fill(palette.card))
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Setting group / row primitives

struct SettingGroup<Content: View>: View {
    let label: String
    let palette: Palette
    let type: Typography
    let scale: Double
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(type.body(14 * scale, weight: .semibold))
                .kerning(0.3)
                .foregroundStyle(palette.ink2)
                .padding(.horizontal, 20)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(palette.card))
        }
    }
}

struct SettingRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String?
    let palette: Palette
    let type: Typography
    let scale: Double
    var chevron: Bool = true
    let action: (() -> Void)?

    var body: some View {
        Button {
            guard action != nil else { return }
            Haptics.tap()
            action?()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tint.opacity(0.15))
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 38, height: 38)

                Text(title)
                    .font(type.body(18 * scale, weight: .medium))
                    .foregroundStyle(palette.ink)
                Spacer()
                if let detail {
                    Text(detail)
                        .font(type.body(16 * scale, weight: .medium))
                        .foregroundStyle(palette.ink2)
                }
                if chevron && action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.ink2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        // Intentionally not `.disabled(action == nil)` — disabling
        // greys out the icon and text via SwiftUI's standard disabled
        // styling, which makes informational rows (e.g. Version) look
        // broken. The guard above already no-ops the tap.
        //
        // Accessibility: collapse the icon, title, optional detail,
        // and chevron into one VoiceOver line — "Daily goal, 7,000
        // steps" rather than three separate announcements with the
        // chevron read as "More". Informational rows (no action) get
        // the `.isStaticText` trait instead of `.isButton` so
        // VoiceOver doesn't suggest a double-tap that does nothing.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(action != nil ? .isButton : .isStaticText)
    }
}

struct ToggleRow: View {
    let icon: String
    let tint: Color
    let title: String
    @Binding var isOn: Bool
    let palette: Palette
    let type: Typography
    let scale: Double

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tint.opacity(0.15))
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 38, height: 38)
            .accessibilityHidden(true)

            // Hide the standalone Text — the Toggle below adopts it
            // as its label via `.accessibilityLabel(title)` so
            // VoiceOver reads "Daily walking reminder, switch button,
            // on" rather than the title twice.
            Text(title)
                .font(type.body(18 * scale, weight: .medium))
                .foregroundStyle(palette.ink)
                .accessibilityHidden(true)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(palette.accent)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Edit emergency contact sheet

/// Compact modal sheet for editing the emergency contact. Two
/// grouped cards on a cream background, settings-style — the
/// previous version stacked four heavy bordered boxes that pushed
/// content to the top of an oversized `.large` sheet. The new layout
/// is denser (smaller body fonts, internal dividers, no chunky
/// borders) and sized to fit content, so the modal feels like a
/// natural Settings sub-screen rather than a half-empty form.
struct EditEmergencyContactSheet: View {
    let palette: Palette
    let type: Typography
    let scale: Double
    let contact: EmergencyContact
    let onSave: (EmergencyContact) -> Void
    let onCancel: () -> Void

    @State private var draft: EmergencyContact
    @State private var showRolePicker = false

    init(palette: Palette, type: Typography, scale: Double, contact: EmergencyContact,
         onSave: @escaping (EmergencyContact) -> Void, onCancel: @escaping () -> Void) {
        self.palette = palette; self.type = type; self.scale = scale
        self.contact = contact; self.onSave = onSave; self.onCancel = onCancel
        self._draft = State(initialValue: contact)
    }

    private var canSave: Bool {
        draft.isValid && !draft.role.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 22)

            // Spacer pair vertically centers the input cards in the
            // sheet's body area. Without the leading spacer the cards
            // hugged the header and the sheet looked top-heavy with
            // empty whitespace at the bottom.
            Spacer(minLength: 0)

            VStack(spacing: 14) {
                contactCard
                relationCard
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .background(palette.bg.ignoresSafeArea())
        .sheet(isPresented: $showRolePicker) {
            RelationPickerSheet(
                palette: palette, type: type, scale: scale,
                roles: RelationMeta.allRoles, selected: draft.role
            ) { r in
                draft.role = r
                showRolePicker = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    /// Cancel / title / Save — native iOS edit-sheet header.
    /// Save is accent-coloured and bold; disabled state surfaces
    /// via reduced opacity so it reads as "not yet" not "broken."
    private var header: some View {
        HStack {
            Button("Cancel") { Haptics.tap(); onCancel() }
                .font(type.body(17 * scale, weight: .medium))
                .foregroundStyle(palette.danger)

            Spacer()

            Text("Emergency contact")
                .font(type.display(20 * scale, weight: .semibold))
                .foregroundStyle(palette.ink)

            Spacer()

            Button("Save") {
                Haptics.success()
                onSave(draft)
            }
            .font(type.body(17 * scale, weight: .bold))
            .foregroundStyle(palette.accent)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.35)
        }
    }

    // MARK: - Contact card

    /// Three rows in one card with thin internal dividers — visually
    /// reads as "this is one block of contact info" rather than three
    /// independent fields. Mirrors the SettingGroup pattern used
    /// elsewhere in Settings, so the sheet feels native to the app.
    private var contactCard: some View {
        VStack(spacing: 0) {
            pickFromContactsRow
            rowDivider
            nameField
            rowDivider
            phoneField
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(palette.card)
                .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 3)
        )
    }

    /// Hairline divider between rows in the contact card. Slightly
    /// inset on the leading edge so it visually nests inside the
    /// card's padding rather than running edge-to-edge.
    private var rowDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 18)
    }

    private var pickFromContactsRow: some View {
        Button {
            Haptics.tap()
            // UIKit-direct presentation. Using a SwiftUI `.sheet` for
            // `CNContactPickerViewController` from inside another sheet
            // (this edit modal) cascaded the picker's auto-dismiss up
            // to the parent — closing the edit sheet entirely on every
            // pick. `ContactPickerPresenter.present` runs outside
            // SwiftUI's sheet hierarchy, so dismissing the picker
            // affects only the picker.
            ContactPickerPresenter.present { name, phone in
                draft.name = name
                draft.phone = phone
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 24)
                Text("Pick from Contacts")
                    .font(type.body(17 * scale, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink2)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var nameField: some View {
        TextField("Their name", text: $draft.name)
            .textContentType(.name)
            .font(type.body(17 * scale, weight: .medium))
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
    }

    private var phoneField: some View {
        TextField("Phone number", text: $draft.phone)
            .textContentType(.telephoneNumber)
            .keyboardType(.phonePad)
            .font(type.body(17 * scale, weight: .medium))
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
    }

    // MARK: - Relation card

    /// Single-row card showing the chosen relation with its tinted
    /// icon badge. Tapping opens the shared `RelationPickerSheet`.
    /// Empty state shows a soft-grey badge and prompt copy in `ink2`.
    private var relationCard: some View {
        Button {
            Haptics.tap()
            showRolePicker = true
        } label: {
            let roleTint = RelationMeta.tint(for: draft.role, palette: palette)
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(draft.role.isEmpty ? palette.soft : roleTint.opacity(0.15))
                    Image(systemName: RelationMeta.icon(for: draft.role))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(draft.role.isEmpty ? palette.accent : roleTint)
                }
                .frame(width: 38, height: 38)

                Text(draft.role.isEmpty ? "Choose a relation" : draft.role)
                    .font(type.body(17 * scale, weight: .semibold))
                    .foregroundStyle(draft.role.isEmpty ? palette.ink2 : palette.ink)

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(palette.card)
                    .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 3)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reminder time sheet

struct ReminderTimeSheet: View {
    let palette: Palette
    let type: Typography
    let scale: Double
    let hour: Int
    let onSave: (Int) -> Void
    let onCancel: () -> Void

    @State private var selection: Date

    init(palette: Palette, type: Typography, scale: Double,
         hour: Int, onSave: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.palette = palette; self.type = type; self.scale = scale
        self.hour = hour; self.onSave = onSave; self.onCancel = onCancel
        var comps = DateComponents()
        comps.hour = hour
        self._selection = State(initialValue: Calendar.current.date(from: comps) ?? Date())
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button("Cancel") { Haptics.tap(); onCancel() }
                    .font(type.body(17 * scale, weight: .medium))
                    .foregroundStyle(palette.danger)

                Spacer()

                Text("Reminder time")
                    .font(type.display(20 * scale, weight: .semibold))
                    .foregroundStyle(palette.ink)

                Spacer()

                Button("Save") {
                    let h = Calendar.current.component(.hour, from: selection)
                    onSave(h)
                }
                .font(type.body(17 * scale, weight: .bold))
                .foregroundStyle(palette.accent)
            }
            .padding(.top, 4)

            // Spacer pair vertically centers the wheel picker between
            // the header row and the bottom of the sheet — without
            // these the picker pinned to the top and the sheet looked
            // bottom-heavy with empty whitespace.
            Spacer()

            DatePicker("", selection: $selection, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()

            Spacer()
        }
        .padding(24)
        .background(palette.bg.ignoresSafeArea())
    }
}
