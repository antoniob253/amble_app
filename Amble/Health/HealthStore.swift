import Foundation
import HealthKit
import CoreMotion
import Observation

/// Outcome of an explicit grant attempt — tells the calling view
/// whether the iOS prompt was shown (or could be shown), or whether
/// iOS will refuse to re-prompt and the user needs to be routed to
/// the iOS Settings app.
enum HealthGrantOutcome {
    /// The iOS HealthKit prompt was attempted (shown to the user
    /// or, if Apple's status was `.unknown`, will be on this call).
    case requested
    /// Apple has already recorded a previous response from the user
    /// for our requested types and will not re-show the prompt. The
    /// only path back to a granted permission is the iOS Settings
    /// app — the caller should open `UIApplication.openSettingsURLString`.
    case settingsNeeded
}

@Observable
@MainActor
final class HealthStore {
    private let store = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)

    /// Foreground-only live pedometer for the day's running total. Fires
    /// several times per second while the user is walking, so the hero ring
    /// counter feels live even outside of an active walk session.
    private let pedometer = CMPedometer()
    private var liveUpdatesActive = false

    /// HealthKit read-access doesn't expose a real "is granted?" API
    /// (Apple privacy quirk — `authorizationStatus(for:)` always
    /// returns `.notDetermined` for read types). So `authorized` is
    /// our best inference, set true after a `requestAuthorization`
    /// succeeds AND confirmed by data flowing on `refresh`.
    /// **Persisted** to UserDefaults so a successful grant survives
    /// app relaunches — without this, the "Health access is off"
    /// alert reappeared on every launch even after the user granted.
    private(set) var authorized: Bool {
        didSet {
            UserDefaults.standard.set(authorized, forKey: Self.authorizedKey)
        }
    }
    /// True once we know iOS has been through the HealthKit prompt for
    /// us — either because we just called `requestAuthorization`, or
    /// because `refresh()` queried Apple's persistent status. Persisted
    /// to UserDefaults so the value is correct from the very first
    /// frame after app launch (otherwise the Settings recovery row
    /// would briefly render with the wrong copy until refresh runs).
    private(set) var authorizationDetermined: Bool {
        didSet {
            UserDefaults.standard.set(authorizationDetermined, forKey: Self.determinedKey)
        }
    }
    private(set) var stepsToday: Int = 0
    private(set) var stepsByDay: [Date: Int] = [:]
    private(set) var isLoading = false

    private var stepObserver: HKObserverQuery?

    private static let authorizedKey = "amble_health_auth_authorized"
    private static let determinedKey = "amble_health_auth_determined"

    var healthKitAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var livePedometerAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    /// Whether the user has granted Motion (CMPedometer) access.
    /// Unlike HealthKit, CMPedometer reports its real status — so a
    /// `.denied` here is distinguishable from `.notDetermined`, and
    /// the Settings row can give precise copy.
    var motionAuthorized: Bool {
        CMPedometer.authorizationStatus() == .authorized
    }

    /// True once iOS has been through the Motion prompt for us
    /// (regardless of the user's answer). Drives copy in the
    /// Settings recovery row: "Allow live step updates" before
    /// determination, "Motion access is off" after a denial.
    var motionDetermined: Bool {
        CMPedometer.authorizationStatus() != .notDetermined
    }

    init() {
        self.authorized = UserDefaults.standard.bool(forKey: Self.authorizedKey)
        self.authorizationDetermined = UserDefaults.standard.bool(forKey: Self.determinedKey)
    }

    /// Heuristic: if HealthKit is returning *any* step data over the
    /// past 14 days, read access is definitely granted. Used by
    /// `refresh()` to confirm the `authorized` flag based on real
    /// data flow rather than relying on `requestAuthorization`'s
    /// silent-success behaviour (which says "true" for both grant
    /// and deny).
    private var hasAnyStepData: Bool {
        stepsToday > 0 || stepsByDay.values.contains(where: { $0 > 0 })
    }

    func requestAuthorization() async {
        guard healthKitAvailable else {
            authorizationDetermined = true
            return
        }
        let read: Set<HKObjectType> = [stepType]
        do {
            try await store.requestAuthorization(toShare: [], read: read)
            authorized = true
        } catch {
            authorized = false
        }
        authorizationDetermined = true
        await refresh()
        if authorized { startObservingSteps() }
    }

    /// Asks Apple's persistent record whether calling
    /// `requestAuthorization` would actually surface the prompt.
    /// Returns `.unnecessary` if iOS has already recorded a response
    /// (in which case we'll never see the prompt again for these
    /// types — the user must change the permission in iOS Settings).
    /// Safe to call freely; doesn't itself trigger any UI.
    func authorizationRequestStatus() async -> HKAuthorizationRequestStatus {
        guard healthKitAvailable else { return .unnecessary }
        do {
            return try await store.statusForAuthorizationRequest(toShare: [], read: [stepType])
        } catch {
            return .unknown
        }
    }

    /// Single entry point for the home card / Settings recovery row.
    ///
    /// Always fires `requestAuthorization` first, regardless of
    /// Apple's pre-call status:
    /// - If Apple says `.shouldRequest` / `.unknown`, the iOS prompt
    ///   surfaces and the user picks.
    /// - If Apple says `.unnecessary`, the call is a silent no-op
    ///   (Apple won't re-prompt) — but `refresh` still runs and
    ///   confirms whether data is actually flowing.
    ///
    /// After the request, only return `.settingsNeeded` if BOTH:
    ///   1. Apple won't re-prompt (`.unnecessary`), AND
    ///   2. We're getting zero step data over the past 14 days
    ///      (strong signal the user has access denied — for our
    ///      audience, no walking activity over two weeks is
    ///      essentially impossible if HealthKit can read).
    ///
    /// The previous version short-circuited on `.unnecessary` and
    /// routed everyone to Settings — including users who had
    /// actually granted. That meant a freshly-granted user who
    /// relaunched the app would see "Health access is off" again,
    /// and tapping it would dump them in iOS Settings (which doesn't
    /// even show a Health toggle for the app — that lives under the
    /// Apple Health app's own Apps section).
    func attemptGrant() async -> HealthGrantOutcome {
        // Capture Apple's status BEFORE the call so we know whether
        // the iOS prompt was actually shown to the user this time.
        // `.shouldRequest` → prompt surfaced; `.unnecessary` → silent
        // no-op (iOS already has a recorded answer).
        let preStatus = await authorizationRequestStatus()

        await requestAuthorization()
        await primeMotionPermission()
        startLiveUpdates()

        // If iOS just showed the prompt, trust the user's answer
        // without forcing them anywhere. Even if `hasAnyStepData`
        // is currently false (fresh iPhone, no walking history yet),
        // we believe them — data will arrive as they walk and
        // future refreshes will confirm `authorized` stays true.
        if preStatus == .shouldRequest {
            return .requested
        }

        // `.unnecessary` case: Apple won't re-prompt. Our only signal
        // for "did the user actually grant?" is whether data is
        // flowing. No step data over the past 14 days means access
        // is off — they need to flip the toggle in the Apple Health
        // app to get back in.
        if !hasAnyStepData {
            return .settingsNeeded
        }
        return .requested
    }

    /// Motion-only grant flow, used by the standalone Motion row in
    /// Settings. CMPedometer's auth state is reliably observable
    /// (unlike HealthKit's silent-deny), so we can branch precisely:
    /// `.notDetermined` → fire the iOS prompt; `.denied` /
    /// `.restricted` → route to iOS Settings; `.authorized` → just
    /// ensure live updates are running.
    func attemptGrantMotion() async -> HealthGrantOutcome {
        switch CMPedometer.authorizationStatus() {
        case .notDetermined:
            await primeMotionPermission()
            startLiveUpdates()
            return .requested
        case .denied, .restricted:
            return .settingsNeeded
        case .authorized:
            startLiveUpdates()
            return .requested
        @unknown default:
            return .requested
        }
    }

    func refresh() async {
        guard healthKitAvailable else { return }
        isLoading = true
        defer { isLoading = false }

        // Sync our session-level `authorizationDetermined` flag with
        // Apple's persistent state. Without this, on app relaunch the
        // flag would be false until something explicit set it — which
        // would let recovery rows render with the wrong copy and tap
        // into the wrong branch of the request/Settings split.
        let status = await authorizationRequestStatus()
        if status == .unnecessary {
            authorizationDetermined = true
        }

        async let today = fetchStepsToday()
        async let byDay = fetchStepsByDay()
        stepsToday = (try? await today) ?? stepsToday
        stepsByDay = (try? await byDay) ?? stepsByDay

        // Confirm `authorized` via real data flow. HealthKit's read-
        // access privacy model means we can't ask "did the user
        // grant?" directly — but if we're getting step data, they
        // definitely have. This catches the case where a previous
        // session set `authorized = true` (which we now persist) but
        // we want to re-confirm it's still working, AND the case
        // where a fresh launch reads an old "false" from defaults
        // for a user who's actually granted.
        if hasAnyStepData {
            authorized = true
        }
    }

    private func fetchStepsToday() async throws -> Int {
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum
            ) { _, result, err in
                if let err { cont.resume(throwing: err); return }
                let count = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                cont.resume(returning: Int(count))
            }
            store.execute(q)
        }
    }

    /// Fetches daily step totals for the last 14 days. The 14-day window
    /// is sized so that — in any locale — WeekView can cover both the
    /// current calendar week AND the prior one for the "last week it
    /// was …" comparison line. In a Sun-start locale the furthest back
    /// day we need is today-13 (when today is Saturday, last week's Sun
    /// sits 13 days ago); a Mon-start locale needs at most today-13 too
    /// (when today is Sunday). 14 days covers every case with a single
    /// fetch.
    private func fetchStepsByDay() async throws -> [Date: Int] {
        let cal = Calendar.current
        let end = cal.startOfDay(for: Date()).addingTimeInterval(86400)
        guard let start = cal.date(byAdding: .day, value: -13, to: cal.startOfDay(for: Date())) else { return [:] }
        let interval = DateComponents(day: 1)
        let anchor = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: stepType, quantitySamplePredicate: predicate,
                options: .cumulativeSum, anchorDate: anchor, intervalComponents: interval
            )
            q.initialResultsHandler = { _, results, err in
                if let err { cont.resume(throwing: err); return }
                var dict: [Date: Int] = [:]
                results?.enumerateStatistics(from: start, to: end) { stats, _ in
                    let c = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    dict[cal.startOfDay(for: stats.startDate)] = Int(c)
                }
                cont.resume(returning: dict)
            }
            store.execute(q)
        }
    }

    private func startObservingSteps() {
        if let existing = stepObserver { store.stop(existing) }
        let q = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, _, _ in
            Task { @MainActor in await self?.refresh() }
        }
        store.execute(q)
        stepObserver = q
        store.enableBackgroundDelivery(for: stepType, frequency: .immediate) { _, _ in }
    }

    // MARK: - Live pedometer (foreground)

    /// Explicitly triggers the CoreMotion permission prompt by issuing a
    /// short historical pedometer query. `startUpdates` is fire-and-forget
    /// and doesn't reliably surface the dialog before we move on; a
    /// `queryPedometerData` call awaits iOS's response, so we can use it
    /// during onboarding to land the prompt right where the user expects
    /// it ("Share your steps") instead of ambushing them later.
    func primeMotionPermission() async {
        guard livePedometerAvailable else { return }
        let end = Date()
        let start = end.addingTimeInterval(-60)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            pedometer.queryPedometerData(from: start, to: end) { _, _ in
                cont.resume()
            }
        }
    }

    /// Starts live step updates from CoreMotion. The handler fires many
    /// times per second while walking — far faster than HealthKit's observer
    /// query — and lets the hero ring tick in near real time.
    ///
    /// Bails early if Motion isn't authorized, so it's safe to call from
    /// places like RootView.task that fire on every app launch. Calling
    /// `pedometer.startUpdates` while Motion is `notDetermined` would
    /// surface the iOS permission prompt — which we never want to do
    /// outside onboarding. If the user enables Motion later (via the
    /// home card or a Settings recovery row), the explicit grant flow
    /// calls `startLiveUpdates` again at that point.
    func startLiveUpdates() {
        guard livePedometerAvailable, !liveUpdatesActive else { return }
        guard CMPedometer.authorizationStatus() == .authorized else { return }
        liveUpdatesActive = true
        let dayStart = Calendar.current.startOfDay(for: Date())
        pedometer.startUpdates(from: dayStart) { [weak self] data, _ in
            guard let data else { return }
            let live = data.numberOfSteps.intValue
            Task { @MainActor in
                guard let self else { return }
                // Take the higher of HealthKit (may include Watch) and live
                // pedometer so we never regress visually.
                if live > self.stepsToday {
                    self.stepsToday = live
                }
            }
        }
    }

    func stopLiveUpdates() {
        guard liveUpdatesActive else { return }
        pedometer.stopUpdates()
        liveUpdatesActive = false
    }
}
