import Foundation
import UserNotifications
import Observation

@Observable
@MainActor
final class NotificationManager {
    private(set) var authorized: Bool = false
    /// True when iOS has a recorded decision from the user and that decision
    /// is denial. In this state `requestAuthorization` returns false without
    /// showing a dialog, so the UI should route the user to system Settings.
    private(set) var isDenied: Bool = false
    private let dailyId = "amble.daily.reminder"

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorized = (settings.authorizationStatus == .authorized
                       || settings.authorizationStatus == .provisional
                       || settings.authorizationStatus == .ephemeral)
        isDenied = settings.authorizationStatus == .denied
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            authorized = granted
            if granted { scheduleDailyReminder() }
            await refreshStatus()
            return granted
        } catch {
            authorized = false
            await refreshStatus()
            return false
        }
    }

    func scheduleDailyReminder(hour: Int = 10, minute: Int = 0) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyId])

        let content = UNMutableNotificationContent()
        // Title and body adapt to the hour the user chose for the
        // reminder — so a 6 PM reminder no longer greets them with
        // "Good morning". The buckets mirror HomeView.greeting so the
        // app speaks with one voice across notifications and the home
        // screen.
        content.title = Self.greetingTitle(forHour: hour)
        content.body = Self.greetingBody(forHour: hour)
        content.sound = .default

        var date = DateComponents()
        date.hour = hour
        date.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: dailyId, content: content, trigger: trigger)
        center.add(request)
    }

    /// Greeting title chosen from the reminder's scheduled hour.
    /// Buckets:
    ///   • 22:00 – 04:59 → "Still up?"
    ///   • 05:00 – 11:59 → "Good morning"
    ///   • 12:00 – 17:59 → "Good afternoon"
    ///   • 18:00 – 21:59 → "Good evening"
    private static func greetingTitle(forHour h: Int) -> String {
        if h < 5 || h >= 22 { return "Still up?" }
        if h < 12           { return "Good morning" }
        if h < 18           { return "Good afternoon" }
        return "Good evening"
    }

    /// Body paired with the same time-of-day bucket. Daytime variants
    /// share the soft closer "Amble is ready when you are" so the
    /// notification's tone stays consistent; the late-night variant
    /// closes with "Amble is here either way" — a gentle nudge that
    /// says *rest is also a fine choice* and avoids being preachy
    /// about walking at 11 PM.
    private static func greetingBody(forHour h: Int) -> String {
        if h < 5 || h >= 22 {
            return "A turn around the block, then good rest. Amble is here either way."
        }
        if h < 12 {
            return "A short walk would feel lovely. Amble is ready when you are."
        }
        if h < 18 {
            return "An afternoon stroll often clears the head. Amble is ready when you are."
        }
        return "An evening walk has its own quiet pleasure. Amble is ready when you are."
    }

    func cancelDailyReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [dailyId])
    }

}
