import ActivityKit
import Flutter
import Foundation

/// The iPhone half of the run's live readout: the app's Dart side says what a
/// run's figures are, and this starts, updates and ends the Live Activity that
/// shows them on the lock screen.
///
/// The Dart side is `PlatformLiveReadout` and the drawing is in the
/// `RunLiveActivity` extension. The channel name is written in all three
/// places it is used.
///
/// Live Activities are iOS 16.2 and later here (the app itself runs on 15).
/// On anything older every call answers and does nothing, and the same where
/// the runner has switched Live Activities off for the app: a run is recorded
/// either way.
enum LiveRunChannel {
  static let name = "com.mgkcodes.fitness.run/live"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "prepare":
        // Nothing to ask for: a Live Activity needs no permission prompt.
        result(true)
      case "show":
        if #available(iOS 16.2, *) {
          LiveRun.show(call.arguments as? [String: Any] ?? [:])
        }
        result(true)
      case "end":
        if #available(iOS 16.2, *) {
          LiveRun.end()
        }
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

@available(iOS 16.2, *)
enum LiveRun {
  /// The one activity this process started, if it has.
  private static var activity: Activity<RunActivityAttributes>?

  private static func state(from args: [String: Any]) -> RunActivityAttributes.ContentState {
    let elapsedSeconds = (args["elapsedSeconds"] as? NSNumber)?.doubleValue ?? 0
    return RunActivityAttributes.ContentState(
      distance: args["distance"] as? String ?? "",
      pace: args["pace"] as? String ?? "",
      // The lock screen counts up from this by itself.
      startedAt: Date().addingTimeInterval(-elapsedSeconds),
      elapsed: args["elapsed"] as? String ?? "",
      paused: (args["paused"] as? NSNumber)?.boolValue ?? false
    )
  }

  static func show(_ args: [String: Any]) {
    let content = ActivityContent(state: state(from: args), staleDate: nil)

    if let current = activity {
      Task { await current.update(content) }
      return
    }

    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

    // One left on the lock screen by a run the app was killed in the middle
    // of. Listed before the new one is asked for, so the new one is not in it.
    let leftOver = Activity<RunActivityAttributes>.activities
    Task {
      for old in leftOver {
        await old.end(nil, dismissalPolicy: .immediate)
      }
    }

    do {
      activity = try Activity<RunActivityAttributes>.request(
        attributes: RunActivityAttributes(),
        content: content,
        pushType: nil
      )
    } catch {
      // Refused: too many activities, or asked for from the background.
      // The run is recorded all the same.
      activity = nil
    }
  }

  static func end() {
    let current = activity
    activity = nil
    Task {
      if let current = current {
        await current.end(nil, dismissalPolicy: .immediate)
      }
      for other in Activity<RunActivityAttributes>.activities {
        await other.end(nil, dismissalPolicy: .immediate)
      }
    }
  }
}
