import Foundation
import CoreMotion
import ActivityKit
import Observation

/// Owns the in-progress walk: CMPedometer subscription + Live Activity
/// lifecycle. Separate from `HealthStore` (which tracks the day's total) so a
/// walk session's step count is a clean "since start" delta, not a delta of a
/// delta.
@Observable
@MainActor
final class WalkTracker {
    private let pedometer = CMPedometer()

    private(set) var isActive: Bool = false
    private(set) var startDate: Date?
    /// Steps counted since the walk started, driven by CMPedometer updates.
    private(set) var steps: Int = 0

    private var activity: Activity<AmbleWalkActivityAttributes>?

    /// Seconds since start. Not an `@Observable` property — views should read
    /// this inside a `TimelineView(.periodic)` rather than relying on change
    /// notifications, so the tracker doesn't need its own per-second timer.
    var elapsedSeconds: Int {
        guard let s = startDate else { return 0 }
        return max(0, Int(Date().timeIntervalSince(s)))
    }

    // MARK: - Lifecycle

    func start() {
        guard !isActive else { return }
        guard CMPedometer.isStepCountingAvailable() else { return }

        isActive = true
        let now = Date()
        startDate = now
        steps = 0

        pedometer.startUpdates(from: now) { [weak self] data, _ in
            guard let data else { return }
            let n = data.numberOfSteps.intValue
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.steps = n
                self.updateLiveActivity()
            }
        }

        startLiveActivity()
        Haptics.success()
    }

    /// Ends the active walk and returns the completed session. Callers are
    /// responsible for deciding whether to persist it (e.g. drop accidental
    /// <10-step sessions).
    @discardableResult
    func stop() async -> WalkSession? {
        guard isActive, let start = startDate else { return nil }
        isActive = false
        pedometer.stopUpdates()

        let end = Date()
        let finalSteps = await queryFinalSteps(from: start, to: end) ?? steps
        let session = WalkSession(start: start, end: end, steps: finalSteps)

        await endLiveActivity(finalSteps: finalSteps)
        startDate = nil
        steps = 0

        return session
    }

    /// Resyncs step count from the pedometer's authoritative record. Call
    /// when the app returns to the foreground — CMPedometer's live handler
    /// doesn't fire while the app is backgrounded (e.g. during a phone
    /// call), but the underlying step data IS still being collected and can
    /// be queried. Without this, the walk UI and Live Activity would show a
    /// stale count after the user comes back from a call.
    func refresh() async {
        guard isActive, let start = startDate else { return }
        if let current = await queryFinalSteps(from: start, to: Date()) {
            steps = current
            updateLiveActivity()
        }
    }

    /// Ends any Live Activities left over from a previous launch (e.g. after
    /// the app was killed mid-walk). Call once on app launch.
    static func clearStaleActivities() async {
        for activity in Activity<AmbleWalkActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: - Helpers

    private func queryFinalSteps(from start: Date, to end: Date) async -> Int? {
        await withCheckedContinuation { cont in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                cont.resume(returning: data?.numberOfSteps.intValue)
            }
        }
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let start = startDate else { return }
        let attrs = AmbleWalkActivityAttributes()
        let state = AmbleWalkActivityAttributes.ContentState(startDate: start, steps: 0)
        do {
            activity = try Activity.request(
                attributes: attrs,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            activity = nil
        }
    }

    private func updateLiveActivity() {
        guard let a = activity, let start = startDate else { return }
        let state = AmbleWalkActivityAttributes.ContentState(startDate: start, steps: steps)
        Task {
            await a.update(.init(state: state, staleDate: nil))
        }
    }

    private func endLiveActivity(finalSteps: Int) async {
        guard let a = activity, let start = startDate else {
            activity = nil
            return
        }
        let state = AmbleWalkActivityAttributes.ContentState(startDate: start, steps: finalSteps)
        await a.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
        activity = nil
    }
}
