/// The controls Lift's walkthrough points at, by name (ADR-0006).
///
/// **Names, not positions.** Each is a `WalkthroughTarget` id on the widget
/// itself, so the walkthrough lights the control where it is drawn today, on
/// this phone, at this text size, and a control that is not drawn is a step
/// that is not shown. A screen that moves a control moves the hole with it;
/// a screen that removes one makes the walkthrough skip a step rather than
/// point at the place it used to be.
///
/// A file of its own so the screens that carry the marks (Track, Profile, the
/// session) need nothing of the walkthrough but its names.
library;

enum WalkthroughSpot {
  /// Track's one action: *Start a session*, or whatever the Today card offers
  /// in its place (*Resume session*, *Start push*, *Start a session anyway*).
  start,

  /// Whatever on Track opens *Your workouts*. Usually the same button as
  /// [start], since TR3 took the saved workouts off Track and put them behind
  /// it; on a planned day it is *Start something else*. Absent with a
  /// session open, where the button resumes it instead.
  workouts,

  /// The Plan tab, on the bar.
  planTab,

  /// The Profile tab, on the bar.
  profileTab,

  /// Profile's way into Settings.
  settings,

  /// The coach's C, floating over every tab. Absent with the coach switched
  /// off, or in a build with no coach.
  coach,

  /// In a session: the tick of the set that is next.
  setTick,

  /// In a session: the rest timer, while it runs.
  rest,

  /// In a session: a movement's swap control.
  swap,

  /// In a session: a movement's picture and name, where it is held to be
  /// moved (ADR-0005).
  movement,
}
