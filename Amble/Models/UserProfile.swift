import Foundation
import Observation

enum Mobility: String, CaseIterable, Codable {
    case none, cane, walker
    var label: String {
        switch self {
        case .none: "On my own"
        case .cane: "With a cane"
        case .walker: "With a walker"
        }
    }
    var sub: String {
        switch self {
        case .none: "I walk unassisted"
        case .cane: "For steadiness"
        case .walker: "Rolling or standard"
        }
    }
    var multiplier: Double {
        switch self {
        case .none: 1.0
        case .cane: 0.75
        case .walker: 0.55
        }
    }
}

enum ActivityLevel: String, CaseIterable, Codable {
    case mostlyHome, someWalks, dailyWalks

    var label: String {
        switch self {
        case .mostlyHome: "Mostly at home"
        case .someWalks:  "A few walks a week"
        case .dailyWalks: "I walk most days"
        }
    }
    var sub: String {
        switch self {
        case .mostlyHome: "Short trips around the house"
        case .someWalks:  "Occasional outings and errands"
        case .dailyWalks: "A regular part of your day"
        }
    }
    var multiplier: Double {
        switch self {
        case .mostlyHome: 0.6
        case .someWalks:  0.9
        case .dailyWalks: 1.15
        }
    }
}

enum Gender: String, CaseIterable, Codable {
    case man, woman, notSaid

    var label: String {
        switch self {
        case .man: "Man"
        case .woman: "Woman"
        case .notSaid: "Prefer not to say"
        }
    }
    /// Small baseline offset — men average ~500 more steps/day than women at
    /// the same activity level (several pedometer studies). We apply ±200 as
    /// a gentle nudge, not a large correction.
    var adjustment: Int {
        switch self {
        case .man: 200
        case .woman: -200
        case .notSaid: 0
        }
    }
}

struct EmergencyContact: Codable, Equatable, Hashable {
    var name: String
    var role: String
    var phone: String

    init(name: String = "", role: String = "", phone: String = "") {
        self.name = name
        self.role = role
        self.phone = phone
    }

    enum CodingKeys: String, CodingKey { case name, role, phone }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.role = (try? c.decode(String.self, forKey: .role)) ?? ""
        self.phone = (try? c.decode(String.self, forKey: .phone)) ?? ""
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && !phone.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

@Observable
@MainActor
final class UserProfile {
    var name: String {
        didSet { UserDefaults.standard.set(name, forKey: "amble_name") }
    }
    var age: Int {
        didSet { UserDefaults.standard.set(age, forKey: "amble_age") }
    }
    var mobility: Mobility {
        didSet { UserDefaults.standard.set(mobility.rawValue, forKey: "amble_mobility") }
    }
    var activity: ActivityLevel {
        didSet { UserDefaults.standard.set(activity.rawValue, forKey: "amble_activity") }
    }
    var gender: Gender {
        didSet { UserDefaults.standard.set(gender.rawValue, forKey: "amble_gender") }
    }
    var dailyGoal: Int {
        didSet { UserDefaults.standard.set(dailyGoal, forKey: "amble_goal") }
    }
    var contact: EmergencyContact {
        didSet {
            if let data = try? JSONEncoder().encode(contact) {
                UserDefaults.standard.set(data, forKey: "amble_contact")
            }
        }
    }
    var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "amble_notifications") }
    }
    var reminderHour: Int {
        didSet { UserDefaults.standard.set(reminderHour, forKey: "amble_reminder_hour") }
    }
    var onboarded: Bool {
        didSet { UserDefaults.standard.set(onboarded, forKey: "amble_onboarded") }
    }

    // MARK: - Engagement state (drives the App Store review prompt)

    /// First time the app was launched and a profile was instantiated.
    /// Used by `ReviewPrompter` to gate the first review prompt to a
    /// minimum number of days, so we never ask before the user has
    /// formed any opinion. Resets on "Start over" because the new
    /// session is, from the user's point of view, a fresh start.
    var firstLaunchDate: Date? {
        didSet {
            if let date = firstLaunchDate {
                UserDefaults.standard.set(date, forKey: "amble_first_launch")
            } else {
                UserDefaults.standard.removeObject(forKey: "amble_first_launch")
            }
        }
    }

    /// Cumulative count of distinct days the user has crossed their
    /// daily step goal. Incremented at most once per calendar day in
    /// `RootView.checkGoalCelebration`. Drives the engagement gate of
    /// `ReviewPrompter`. Resets on "Start over."
    var goalsHitCount: Int {
        didSet { UserDefaults.standard.set(goalsHitCount, forKey: "amble_goals_hit_count") }
    }

    /// How many times we've called `requestReview()` for this install.
    /// Apple's hard cap is 3 per user per 365 days; we mirror that as
    /// the absolute ceiling here. Deliberately NOT reset on "Start
    /// over" — otherwise a user could clear-and-restart to get
    /// re-prompted, which is exactly the manipulation Apple's cap
    /// is designed to prevent.
    var reviewRequestCount: Int {
        didSet { UserDefaults.standard.set(reviewRequestCount, forKey: "amble_review_request_count") }
    }

    /// Timestamp of the most recent `requestReview()` call. Used by
    /// `ReviewPrompter` to enforce minimum spacing between asks
    /// (14 days between #1 and #2, 30 days between #2 and #3).
    /// Like `reviewRequestCount`, deliberately NOT reset on
    /// "Start over."
    var lastReviewRequestDate: Date? {
        didSet {
            if let date = lastReviewRequestDate {
                UserDefaults.standard.set(date, forKey: "amble_last_review_request")
            } else {
                UserDefaults.standard.removeObject(forKey: "amble_last_review_request")
            }
        }
    }

    init() {
        let d = UserDefaults.standard
        self.name = d.string(forKey: "amble_name") ?? ""
        let a = d.integer(forKey: "amble_age")
        self.age = a == 0 ? 70 : a
        self.mobility = Mobility(rawValue: d.string(forKey: "amble_mobility") ?? "") ?? .none
        self.activity = ActivityLevel(rawValue: d.string(forKey: "amble_activity") ?? "") ?? .someWalks
        self.gender = Gender(rawValue: d.string(forKey: "amble_gender") ?? "") ?? .notSaid
        let g = d.integer(forKey: "amble_goal")
        self.dailyGoal = g == 0 ? 5000 : g
        if let data = d.data(forKey: "amble_contact"),
           let c = try? JSONDecoder().decode(EmergencyContact.self, from: data) {
            self.contact = c
        } else {
            self.contact = EmergencyContact()
        }
        self.notificationsEnabled = d.bool(forKey: "amble_notifications")
        let h = d.integer(forKey: "amble_reminder_hour")
        self.reminderHour = h == 0 ? 10 : h
        self.onboarded = d.bool(forKey: "amble_onboarded")

        // Engagement state. `firstLaunchDate` is stamped here on the
        // very first init so existing-user upgrades (who installed
        // before review prompts existed) get a sensible "today" as
        // their baseline rather than an immediate eligibility for
        // prompt 1. The downside — they'd have to wait 3 days from
        // the upgrade — is acceptable; we'd rather under-ask
        // existing users than spam them on the first launch of a
        // new build.
        self.goalsHitCount = d.integer(forKey: "amble_goals_hit_count")
        self.reviewRequestCount = d.integer(forKey: "amble_review_request_count")
        self.lastReviewRequestDate = d.object(forKey: "amble_last_review_request") as? Date
        if let stored = d.object(forKey: "amble_first_launch") as? Date {
            self.firstLaunchDate = stored
        } else {
            // Stamp + persist immediately. Swift's `didSet` does not
            // fire during `init`, so we write to UserDefaults
            // directly here — without this, the date would be lost
            // on app termination and re-stamped on every cold launch.
            let now = Date()
            self.firstLaunchDate = now
            d.set(now, forKey: "amble_first_launch")
        }
    }

    /// Research-backed daily step goal.
    /// - Age base from Paluch et al. 2022 (Lancet Public Health): mortality
    ///   benefit plateau for older adults sits around 6k–8k/day.
    /// - Mobility multipliers from Webber & Porter 2009 (cane/walker users).
    /// - Activity multiplier anchors the target to current baseline, so the
    ///   goal is a realistic progression rather than a generic number.
    /// - Gender adjustment ±200 reflects small baseline difference in
    ///   average daily steps; skipped when user prefers not to say.
    static func suggestedGoal(
        age: Int,
        mobility: Mobility,
        activity: ActivityLevel,
        gender: Gender
    ) -> Int {
        let ageBase: Double
        if age < 65 { ageBase = 8000 }
        else if age < 75 { ageBase = 7000 }
        else if age < 85 { ageBase = 5500 }
        else { ageBase = 4000 }

        let raw = ageBase * activity.multiplier * mobility.multiplier
                + Double(gender.adjustment)
        let clamped = max(1000, min(10000, raw))

        let options: [Int] = [1000, 2000, 3000, 5000, 7000, 10000]
        return options.min(by: { abs(Double($0) - clamped) < abs(Double($1) - clamped) }) ?? 5000
    }

    func reset() {
        let d = UserDefaults.standard
        // Profile + engagement keys that mirror "the user's journey"
        // and should genuinely start fresh on Start over. NOTE: the
        // `amble_review_*` keys are intentionally absent from this
        // list — see comment below.
        ["amble_name", "amble_age", "amble_mobility", "amble_activity",
         "amble_gender", "amble_goal", "amble_contact",
         "amble_notifications", "amble_reminder_hour",
         "amble_onboarded", "amble_trial_start", "amble_family",
         "amble_first_launch", "amble_goals_hit_count"]
            .forEach { d.removeObject(forKey: $0) }
        name = ""; age = 70; mobility = .none
        activity = .someWalks; gender = .notSaid
        dailyGoal = 5000
        contact = EmergencyContact()
        notificationsEnabled = false
        reminderHour = 10
        onboarded = false
        goalsHitCount = 0
        // Re-stamp first-launch as today; the existing init-time
        // stamping logic only fires for fresh installs, so we
        // recreate that effect here for the post-reset state.
        let now = Date()
        firstLaunchDate = now
        d.set(now, forKey: "amble_first_launch")

        // Deliberately preserved across reset:
        //   amble_review_request_count
        //   amble_last_review_request
        // Apple's review API caps prompts at 3 per user per 365 days.
        // Resetting our local counter on Start over would let a user
        // game that cap by clearing-and-restarting — exactly the
        // manipulation Apple's cap exists to block. We respect it
        // by treating those two keys as install-scoped, not
        // profile-scoped.
    }
}

enum StepFormat {
    static func int(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
