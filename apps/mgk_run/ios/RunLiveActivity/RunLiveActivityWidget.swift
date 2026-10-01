import ActivityKit
import SwiftUI
import WidgetKit

/// A run in progress, on the lock screen and in the Dynamic Island.
///
/// Distance, time and pace: the three figures a runner looks at, readable
/// without unlocking a phone that is in an armband. The app sends the
/// distance and the pace every few seconds; the time is counted here.
///
/// Greyscale on the app's own ground, like everything else it draws.
struct RunLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RunActivityAttributes.self) { context in
      RunLockScreenView(state: context.state)
        .activityBackgroundTint(Color(red: 0.10, green: 0.10, blue: 0.10))
        .activitySystemActionForegroundColor(Color.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          RunFigure(label: "DISTANCE", alignment: .leading) {
            Text(context.state.distance)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          RunFigure(label: "PACE", alignment: .trailing) {
            Text(context.state.pace)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          RunClock(state: context.state)
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundColor(Color.white)
            .frame(maxWidth: .infinity, alignment: .center)
        }
      } compactLeading: {
        Text(context.state.distance)
          .font(.caption2.weight(.semibold))
          .monospacedDigit()
          .foregroundColor(Color.white)
      } compactTrailing: {
        // A counting clock takes every point it is offered, and the island
        // has none to spare: held to the width of "0:00:00".
        RunClock(state: context.state)
          .font(.caption2.weight(.semibold))
          .foregroundColor(Color.white)
          .multilineTextAlignment(.trailing)
          .frame(width: 52)
      } minimal: {
        Image(systemName: "figure.run")
          .foregroundColor(Color.white)
      }
      .keylineTint(Color.white)
    }
  }
}

/// The lock screen: the app's name, then the three figures in a row.
struct RunLockScreenView: View {
  let state: RunActivityAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 6) {
        // Two chevrons, as on the app's icon.
        Image(systemName: "chevron.right.2")
          .font(.caption.weight(.heavy))
        Text(state.paused ? "RUN · PAUSED" : "RUN")
          .font(.caption.weight(.heavy))
          .tracking(2)
        Spacer(minLength: 0)
      }
      .foregroundColor(Color.white.opacity(0.7))

      // Three equal columns, so the counting clock in the middle cannot push
      // the other two about as its width changes.
      HStack(alignment: .top, spacing: 8) {
        RunFigure(label: "DISTANCE", alignment: .leading) {
          Text(state.distance)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        RunFigure(label: "TIME", alignment: .leading) {
          RunClock(state: state)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        RunFigure(label: "PACE", alignment: .leading) {
          Text(state.pace)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(16)
  }
}

/// A small label over a figure.
struct RunFigure<Value: View>: View {
  let label: String
  let alignment: HorizontalAlignment
  @ViewBuilder let value: () -> Value

  var body: some View {
    VStack(alignment: alignment, spacing: 2) {
      Text(label)
        .font(.caption2.weight(.semibold))
        .tracking(1.2)
        .foregroundColor(Color.white.opacity(0.6))
      value()
        .font(.title3.weight(.bold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .foregroundColor(Color.white)
    }
  }
}

/// The run's clock: counting while the run is, standing still while it is
/// paused.
struct RunClock: View {
  let state: RunActivityAttributes.ContentState

  var body: some View {
    if state.paused {
      Text(state.elapsed)
        .monospacedDigit()
    } else {
      Text(state.startedAt, style: .timer)
        .monospacedDigit()
    }
  }
}
