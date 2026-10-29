/// What Lift says the first time it is opened: the welcome, and the coach's
/// lines in the walkthrough over the app (ADR-0006).
///
/// ## A walkthrough over the real app
///
/// The first version of this file (29 October 2026, the same day) held six
/// lines the coach said on a screen of their own, Run's arrival in Lift's
/// words. The owner looked at it and asked instead for "a walkthrough in the
/// UI, not just a screen saying what happens: a full run through where it
/// takes you through the app". So the lines moved onto the app itself. Each
/// step lights one real control under a dimmed screen, with the coach's line
/// beside it, and the tabs change as it goes; then a practice set in a real
/// session screen, which nothing keeps.
///
/// ## Why a script and not the model
///
/// The coach cannot run before there is an account: every request goes
/// through the coach's server with the lifter's session, and the coach is the
/// paid half. Nothing here needs it either. These are statements about
/// controls the lifter can see, and a statement has no wrong answer to
/// recover from. **No network, anywhere in the walkthrough**, the practice
/// set included.
///
/// ## The rules the lines keep
///
/// - **The price is said once, plainly, where the C is.** "Coaching is a
///   subscription. Logging never is." A coach that introduces itself and is
///   then found to cost money has hidden something. No figure: prices are the
///   store's, and a number written here would be wrong in every other
///   currency. Plan says its own half where Plan is lit.
/// - **The sessions are said to be on the phone**, to somebody signed out,
///   and signing in is offered as what it buys, a backup, not as a step.
///   Somebody signed in replaying it from Settings is told the true thing for
///   them instead (see [WalkthroughStep.settings]).
/// - **No em dashes.** The coach's server tells the model never to use one,
///   and a scripted line that breaks the voice the model keeps afterwards is a
///   seam the lifter can see. `welcome_test.dart` holds this.
library;

import 'walkthrough_spot.dart';

/// The welcome screen's headline. Broken after the comma, as Run's is, so the
/// line falls where it is read rather than where the width runs out.
const String kWelcomeHeadline = 'Every session,\nlogged.';

/// Under the headline: the three things Lift is, in the order they matter in
/// a gym. Set by set is the product, no signal is the gym, and the coach is
/// offered rather than pushed, because it is the paid half and the free half
/// stands on its own.
const String kWelcomeLine =
    'Set by set, with no signal,\nand a coach when you want one.';

/// The welcome's primary action. Straight into the walkthrough over the app,
/// not to a form: nothing in Lift needs an account to start.
const String kWelcomeStart = 'Get started';

/// For somebody who already has an MGKFitness account, from Run or from Lift
/// on another phone. Opens Lift's own sign-in, then the app, with no
/// walkthrough: the owner's ruling (29 October 2026) is that somebody with an
/// account has a reason to be here already, and can play it from Settings.
const String kWelcomeHaveAccount = 'I already have an account';

/// The last step's one button, which ends the walkthrough on Track.
const String kWalkthroughStart = 'Start training';

/// The card's two buttons on every other step.
const String kWalkthroughNext = 'Next';
const String kWalkthroughSkip = 'Skip';

/// Settings' row that plays the walkthrough again.
const String kShowMeAround = 'Show me around';

/// Where a step is shown.
enum WalkthroughPlace {
  track,
  plan,
  profile,

  /// The practice session, a real session screen over an in-memory recorder
  /// that nothing keeps (`PracticeSession`).
  practice,
}

/// The walkthrough, in order: over the shell, then in a practice session.
///
/// **Each step names a control, and a control that is not drawn is a step
/// that is not shown.** The C is not drawn with the coach switched off;
/// *Your workouts* is not behind Track's button while a session is open; a
/// build with no database has no workouts at all. The walkthrough never
/// points at nothing.
///
/// The words are the owner's (29 October 2026), kept as given except where a
/// control did not fit them, each said on the step it changes.
enum WalkthroughStep {
  track(
    WalkthroughPlace.track,
    WalkthroughSpot.start,
    'Track is where you log. Start a session here and log it set by set. It '
    'works with no signal.',
  ),

  /// **"This opens your workouts." is added to the owner's line.** TR3 took
  /// the saved workouts off Track: they are behind *Start a session*, which
  /// on a new install is the same button the step before lit. Without the
  /// first sentence the same button is lit twice with no reason given.
  workouts(
    WalkthroughPlace.track,
    WalkthroughSpot.workouts,
    'This opens your workouts. Save a session as a workout and next time it '
    'starts with every set filled in.',
  ),

  /// Lights the tab on the bar, with the Plan tab open behind the veil:
  /// what the tab holds differs (the offer, a plan to build, the week), and
  /// the tab is the one thing every lifter has.
  plan(
    WalkthroughPlace.plan,
    WalkthroughSpot.planTab,
    "Plan is a week I build around your days, your kit and anything you're "
    'working around. Plans come with the subscription.',
  ),

  profile(
    WalkthroughPlace.profile,
    WalkthroughSpot.profileTab,
    'Profile keeps your history, your bests and your progress photos.',
  ),

  /// Said to somebody signed out. Somebody signed in, replaying it from
  /// Settings, is told [kSettingsLineSignedIn] instead: their sessions do not
  /// stay on the phone, and an offer to sign in would be wrong twice.
  settings(
    WalkthroughPlace.profile,
    WalkthroughSpot.settings,
    'Your sessions stay on this phone. Sign in from Settings whenever you '
    'want them backed up.',
  ),

  /// Skipped when the C is not drawn: the coach switched off, or a build
  /// with no coach.
  coach(
    null,
    WalkthroughSpot.coach,
    'And this is me. Tap the C any time to ask about your training. Coaching '
    'is a subscription. Logging never is.',
  ),

  /// Lights nothing; the next step opens the practice session.
  tryASet(null, null, "Let's try a set."),

  /// **The one step that waits for the lifter**: the tick takes a real tap,
  /// and ticking it moves on. *Next* moves on too, for anybody who would
  /// rather not.
  logASet(
    WalkthroughPlace.practice,
    WalkthroughSpot.setTick,
    "Lift something, then tap here. That's a set logged.",
    interactive: true,
  ),

  /// Skipped when no rest is running, which is when the set above was not
  /// ticked.
  rest(
    WalkthroughPlace.practice,
    WalkthroughSpot.rest,
    'Your rest starts by itself, and it reaches your lock screen.',
  ),

  /// Said to a lifter whose swap asks the coach: subscribed, with the coach
  /// on. Everybody else picks the replacement themselves, and is told
  /// [kSwapLineByHand], since "I'll suggest something else" is the paid half
  /// promised to somebody who has not got it.
  swap(
    WalkthroughPlace.practice,
    WalkthroughSpot.swap,
    "Machine taken? Swap it, and I'll suggest something else.",
  ),

  reorder(
    WalkthroughPlace.practice,
    WalkthroughSpot.movement,
    'Hold a movement and drag it to change the order.',
  ),

  /// The last step: [kWalkthroughStart], and no Skip, since the button is the
  /// way out. Closes the practice session and lands on Track.
  done(
    WalkthroughPlace.practice,
    null,
    "That's it. Your real sessions start from Track.",
  );

  const WalkthroughStep(
    this.place,
    this.spot,
    this.line, {
    this.interactive = false,
  });

  /// Where the step is shown. Null stays wherever the step before left the
  /// app: the C floats over every tab.
  final WalkthroughPlace? place;

  /// The control the step lights. Null lights nothing.
  final WalkthroughSpot? spot;

  /// What the coach says, as the owner wrote it.
  final String line;

  /// Whether the lit control takes a tap.
  final bool interactive;

  /// What the coach says to this lifter: [line], or the variant for somebody
  /// it would not be true for.
  String lineFor({required bool signedIn, required bool coached}) =>
      switch (this) {
        settings when signedIn => kSettingsLineSignedIn,
        swap when !coached => kSwapLineByHand,
        _ => line,
      };
}

/// [WalkthroughStep.settings], to somebody signed in.
const String kSettingsLineSignedIn =
    'Your sessions back up to your account. Settings shows where that stands.';

/// [WalkthroughStep.swap], to somebody who chooses the replacement by hand.
const String kSwapLineByHand = 'Machine taken? Swap it for something else.';
