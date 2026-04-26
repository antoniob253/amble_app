import ActivityKit
import Foundation

/// Live Activity attributes for an in-progress walk.
///
/// IMPORTANT: this file must be added to both the app target AND the
/// AmbleWidget extension target so both can encode/decode the shared state.
struct AmbleWalkActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// When the walk began — the widget uses this with `Text(timerInterval:)`
        /// to render a live-ticking elapsed time without requiring push updates.
        var startDate: Date
        /// Steps counted since `startDate`.
        var steps: Int
    }
}
