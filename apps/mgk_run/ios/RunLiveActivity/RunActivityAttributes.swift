import ActivityKit
import Foundation

/// What a run's Live Activity is told: the three figures, and whether the
/// runner has paused.
///
/// **In both targets.** The app starts and updates the activity and the
/// `RunLiveActivity` extension draws it, and ActivityKit carries this between
/// them. It is the whole of what they share: no App Group and no shared
/// store.
///
/// The distance and the pace arrive as text, already in the runner's own
/// unit. The app has that logic and the extension should not grow a copy.
@available(iOS 16.1, *)
struct RunActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    /// "5.02 km".
    var distance: String

    /// "5:31 /km", or dashes while there is no honest pace to give.
    var pace: String

    /// When the run's clock read zero: now, less the time on the clock. The
    /// lock screen counts up from here by itself, every second, so the time
    /// moves between the app's updates and while the app is asleep.
    var startedAt: Date

    /// The time on the clock as text, for when it is standing still.
    var elapsed: String

    /// Whether the runner has paused.
    var paused: Bool
  }
}
