/// What Lift says the first time it is opened: the welcome, and the coach's
/// first lines.
///
/// ## Run's pattern, in Lift's words
///
/// Chosen by the owner on 29 October 2026 (ADR-0005) over three swipe pages
/// and over hints laid on the screens themselves. Run opens the same way
/// (Run's ADR-0018 and ADR-0019): a welcome, then the coach saying a few lines
/// one after another, then a button. The two apps are one product, so they
/// arrive alike.
///
/// What Lift's does **not** do, and why:
///
/// - **It asks nothing.** Run's asks a name, and the permissions a run tracker
///   needs. Lift needs no permission, and the name is the account's (Run's
///   ADR-0047), asked once after an account is made, so there is nothing here
///   for anybody to answer.
/// - **It is not a tour.** Nothing points at a button. The lines say what each
///   tab is for, in the order they sit on the bar, and the app is learned by
///   using it.
///
/// ## Why a script and not the model
///
/// The coach cannot run before there is an account: every request goes
/// through the coach's server with the lifter's session, and the coach is the
/// paid half. Nothing here needs it either. These are statements, and a
/// statement has no wrong answer to recover from.
library;

/// The welcome screen's headline. Broken after the comma, as Run's is, so the
/// line falls where it is read rather than where the width runs out.
const String kWelcomeHeadline = 'Every session,\nlogged.';

/// Under the headline: the three things Lift is, in the order they matter in
/// a gym. Set by set is the product, no signal is the gym, and the coach is
/// offered rather than pushed, because it is the paid half and the free half
/// stands on its own.
const String kWelcomeLine =
    'Set by set, with no signal,\nand a coach when you want one.';

/// The welcome's primary action. To the coach's lines, not to a form: nothing
/// in Lift needs an account to start.
const String kWelcomeStart = 'Get started';

/// For somebody who already has an MGKFitness account, from Run or from Lift
/// on another phone. Opens Lift's own sign-in, then the coach's lines: Lift is
/// new to them even if the account is not.
const String kWelcomeHaveAccount = 'I already have an account';

/// The intro's one button, under the last line.
const String kIntroStart = 'Start training';

/// What the coach says, in order.
///
/// **One line per tab, in the bar's order**, then the C, then where the
/// sessions live. Each is something a lifter can act on in their first
/// minute: where to log, what the plan is, where the history went, what the
/// letter in the corner is, and what an account is for.
///
/// **The price is said here, once, plainly.** "Coaching and plans are a
/// subscription. Logging never is." A coach that introduces itself and is then
/// found to cost money has hidden something; one that says so up front, beside
/// the promise that the free half stays free, has not. No figure: prices are
/// the store's, and a number written here would be wrong in every other
/// currency.
///
/// **The last line is about the phone, not the account.** A new lifter is
/// signed out, so their sessions are on this phone and nowhere else, and that
/// is the honest thing to say before they log one. Signing in is offered as
/// what it buys (a backup), not as a step.
///
/// **No em dashes.** The coach's server tells the model never to use one, and
/// a scripted line that breaks the voice the model keeps afterwards is a seam
/// the lifter can see. `intro_test.dart` holds this.
const List<String> kIntroLines = <String>[
  "Hey. I'm your coach.",
  'Track is where you log a session, set by set. It works with no signal.',
  "Plan is a week I build around your days, your kit and anything you're "
      'working around.',
  'Profile keeps your history, your bests and your progress photos.',
  'Tap the C at the bottom to ask me anything about your training. Coaching '
      'and plans are a subscription. Logging never is.',
  'Your sessions stay on this phone. Sign in whenever you want them backed '
      'up.',
];
