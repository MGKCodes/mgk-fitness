/// What the coach says in the tour over the app, after the intro (ADR-0050).
///
/// ## A tour over the real app
///
/// Lift's owner asked for "a walkthrough in the UI ... a full run through
/// where it takes you through the app" (29 October 2026), and Lift got one.
/// Run's owner asked for the same the next day. Each step lights one real
/// control under a dimmed screen, with the coach's line beside it, and the
/// tabs change as it goes. The shared pieces are in `mgk_ui`
/// (`walkthrough.dart`); this file is only what Run says, and where.
///
/// **Every line is here**, so they can be changed in one place after they
/// have been read on a phone.
///
/// ## Why a script and not the model
///
/// The coach cannot run before there is an account, and nothing here needs
/// it: these are statements about controls the runner can see. **No network
/// anywhere in the tour.**
///
/// ## The rules the lines keep
///
/// - **No practice run.** The tour ends by lighting the start button and
///   saying what it does. Starting a run turns on GPS and the run's figures
///   on the lock screen, and ends with a run in the log, and none of that is
///   something a tour should set off by accident (ADR-0050). The veil
///   takes every tap, so the lit button cannot be pressed through it either.
/// - **The price is said once, plainly, where the C is**, as Lift's is: no
///   figure, since prices are the store's. Plan says its own half where Plan
///   is lit.
/// - **The runs are said to be on the phone**, to somebody signed out, and
///   signing in is offered as what it buys, a backup. Somebody signed in,
///   replaying it from Settings, is told the true thing for them instead.
/// - **No em dashes.** The coach's server tells the model never to use one,
///   and a scripted line that breaks that voice is a seam the runner can see.
///   `walkthrough_test.dart` holds this.
library;

/// The card's two buttons on every step but the last.
const String kTourNext = 'Next';
const String kTourSkip = 'Skip';

/// The last step's one button, which ends the tour on Home. Not "Start": the
/// lit button behind it is the one that starts a run, and this one must not
/// sound like it.
const String kTourDone = 'Done';

/// Settings' row that plays the tour again.
const String kShowMeAround = 'Show me around';

/// The controls the tour lights, by name.
///
/// **Names, not positions.** Each is a `WalkthroughTarget` id on the widget
/// itself, so the hole is cut where the control is drawn today, on this phone,
/// at this text size; and a control that is not drawn is a step that is not
/// shown.
enum TourSpot {
  /// Home's Today card: today's session, or the day with no plan.
  today,

  /// Home's week card, under it.
  week,

  /// The Plan tab, on the bar.
  planTab,

  /// The Profile tab, on the bar.
  profileTab,

  /// Profile's way into Settings, the gear at the top.
  settings,

  /// The coach's C, floating over every tab. Absent in a build with no coach.
  coach,

  /// The button on the Today card that starts a run, whatever it says today
  /// (*Record a run*, *Start*, *Start the race*).
  start,
}

/// The tab a step is shown on.
enum TourPlace { home, plan, profile }

/// The tour, in order.
///
/// **Each step names a control, and a control that is not drawn is a step
/// that is not shown**: the C in a build with no coach. The last step is the
/// exception, since it is the way out: with no start button on the Today card
/// (the day after a race, say) it is said with nothing lit.
enum TourStep {
  today(
    TourPlace.home,
    TourSpot.today,
    "This is Home. It opens on today, so you can see what's on at a glance.",
  ),

  week(
    TourPlace.home,
    TourSpot.week,
    "Under it is your week, run by run, so you can see how it's going.",
  ),

  /// Lights the tab on the bar, with the Plan tab open behind the veil.
  plan(
    TourPlace.plan,
    TourSpot.planTab,
    'Plan is where I build you a plan for a race or a goal, week by week. '
    'Plans come with the subscription.',
  ),

  profile(
    TourPlace.profile,
    TourSpot.profileTab,
    'Profile keeps every run you do, with your totals and your records.',
  ),

  /// Said to somebody signed out. Somebody signed in, replaying it from
  /// Settings, is told [kSettingsLineSignedIn] instead.
  settings(
    TourPlace.profile,
    TourSpot.settings,
    'Your runs stay on this phone. Sign in from Settings whenever you want '
    'them backed up.',
  ),

  /// Skipped in a build with no coach.
  coach(
    null,
    TourSpot.coach,
    'And this is me. Tap the C any time to ask about your running. Coaching '
    'is a subscription. Recording your runs never is.',
  ),

  /// The last step: [kTourDone], and no Skip, since the button is the way
  /// out. Lights the start button and lands on Home.
  start(
    TourPlace.home,
    TourSpot.start,
    "That's it. When you head out, press this and your route, pace and "
    'splits are recorded as you go.',
  );

  const TourStep(this.place, this.spot, this.line);

  /// The tab the step is shown on. Null stays wherever the step before left
  /// the app: the C floats over every tab.
  final TourPlace? place;

  /// The control the step lights.
  final TourSpot spot;

  /// What the coach says.
  final String line;

  /// What the coach says to this runner: [line], or the variant for somebody
  /// it would not be true for.
  String lineFor({required bool signedIn}) => switch (this) {
    settings when signedIn => kSettingsLineSignedIn,
    _ => line,
  };
}

/// [TourStep.settings], to somebody signed in. Signed in is not backed up: the
/// backup is its own answer in Settings.
const String kSettingsLineSignedIn =
    'Settings is where you choose whether your runs back up to your account.';
