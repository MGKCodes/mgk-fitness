/// The conversation the app opens with, **before there is an account**.
///
/// ## Why a script and not the model
///
/// The coach cannot run here: every LLM call goes through an Edge Function
/// authenticated with the runner's session
/// ([ADR-0007](../../../../../docs/decisions/0007-secrets-via-backend-proxy.md)),
/// and there is no session yet. Making one would mean anonymous auth, which is
/// a dashboard setting, an abuse surface, and rows in the `public.profiles`
/// table Liftio shares.
///
/// It does not need the model either, which is the point. Nothing asked here
/// has a wrong answer: one is a name (unvalidatable by nature), one is a
/// statement about what the app does, one is a permission the OS answers, and
/// the last is a form.
///
/// ## What this is *not* any more
///
/// It used to ask what the runner was training for, and state what Runio cost.
/// Both moved to the plan flow when onboarding split in two
/// ([ADR-0019](../../../../../docs/decisions/0019-onboarding-is-two-moments.md)):
/// this moment ends with a free account and a working run tracker, and neither
/// a plan shape nor a price is relevant until somebody asks for a plan.
///
/// ## Why it exists at all
///
/// So that the first thing a runner does in the app is **talk to the coach**.
/// The coach is then never something to be discovered later; it is how the app
/// works, learned by doing it once. It also means a runner who opens the app and
/// leaves has cost nothing, where an LLM-from-turn-one intake bills for every
/// bounce.
library;

import '../../../core/brand.dart';

/// The steps of the first conversation, in order.
enum IntroStep {
  /// Who the coach is, and what the app does with a run. Two lines: see
  /// [introPrompt] and [introHowItWorks].
  greeting,

  /// What the coach should call them. Free text, and **anything is accepted** —
  /// a name is not a format, and every rule that rejects one rejects somebody
  /// real.
  ///
  /// That trade only holds because a typo can be put right afterwards, in
  /// Settings. It used to say the fix was "the confirmation screen at the end
  /// of intake", which edits `IntakeSlots` — a type with no name in it. The
  /// recovery path was cited for a long time before it was built.
  name,

  /// The permissions, asked one at a time, **for real**.
  ///
  /// The coach explains one, the runner taps, the OS dialog appears, and the
  /// coach answers whichever way it went before moving to the next. See
  /// `intro_permission.dart` for the list, and for why the dialog fires here
  /// rather than at the moment of first use.
  permissions,
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED IDENTITY — NAME PENDING
//
// This app and Lift share one Supabase project and therefore one `auth.users`
// pool (ADR-0008), so an account made in either already works in the other. The
// intent is for that account to be branded as the platform identity across
// every MGKCodes health app, but **the platform has no agreed name yet**.
//
// The line that had to name it lived here, in the intro's account step. That
// step is gone: the intro no longer creates an account. The copy that still has
// to say it is `sign_in_screen.dart`, which is where the naming question now
// belongs. When the name lands, check there and in
// `docs/decisions/0008-shared-supabase-platform.md`.
//
// Do not invent one. A brand name shipped in onboarding is very hard to take
// back, and this is a line of dialogue, not a positioning exercise.
// ─────────────────────────────────────────────────────────────────────────────

/// What the coach says at each step. First person, plain, and short — the same
/// voice the Edge Function's `PERSONA` sets, so the handover after sign-up is
/// not a change of character.
///
/// **No em dashes.** `PERSONA` says the coach never uses one, and a scripted
/// line that breaks the model's own stated voice is a seam the runner can see.
/// `intro_script_test.dart` holds this.
String introPrompt(IntroStep step, {String? name}) => switch (step) {
  IntroStep.greeting => 'Hey there. Thanks for downloading $kProductName.',
  IntroStep.name => 'First things first. What should I call you?',
  // The permissions speak for themselves — see `introPermissions`, which
  // carries a line per permission rather than one for the step.
  IntroStep.permissions =>
    name == null ? 'Nearly there.' : 'Nearly there, $name.',
};

/// What the coach says when sign-up failed for a reason the runner cannot fix.
///
/// **The reason itself never reaches the screen.** A backend message is written
/// for whoever is reading a log, not for somebody halfway through meeting an
/// app, and this one arrives at the worst possible moment to be shown a stack
/// of jargon. What the runner gets is a sentence in the coach's voice and a
/// short code; what support gets, from a screenshot, is the code.
///
/// The codes are deliberately coarse. A finer set would say more than we want
/// to tell somebody who is guessing at addresses: whether an account exists at
/// all is not something an unauthenticated screen should be willing to answer.
String introTrouble(String code) =>
    'I could not set that up just now. Worth trying again in a moment. ($code)';

/// Something between the app and the backend went wrong: no network, a refused
/// connection, a timeout.
const String kSignUpCodeUnreachable = 'E-ACC-01';

/// The backend answered, and said no. Covers a rejected address, a password it
/// will not take, and an address already in use, on purpose — see
/// [introTrouble] for why the three are not told apart on screen.
const String kSignUpCodeRefused = 'E-ACC-02';

/// What to call the coach.
///
/// **The coach has no name and no gender.** It is not a character with a
/// backstory, it is the role — so it is referred to as Coach, by everyone,
/// everywhere in the app. This line is where a runner learns that, and it is
/// the only introduction the coach gets.
///
/// It briefly said "I'm an AI" here. That is not how a coach talks, and the
/// screen is a first impression rather than a disclosure notice. Runio says
/// what it is in its store listing, its README and its privacy policy, which
/// is where somebody looks when that is the question they are asking.
const String introWhoIAm = 'You can just call me Coach. Everyone does.';

/// What Runio does, before anything is asked for.
///
/// Said first because everything after it is a request. A runner who has been
/// told what the thing does has a reason to give a name and a reason to grant a
/// permission; one who has not is being interrogated by an app they have not
/// seen work yet.
///
/// **What it does, not how it works.** This described the mechanics for a
/// while — press start, tell me about a run you did without your phone, I will
/// log that too. All true, and all meaningless to somebody who has not seen a
/// single screen of the app yet: "press start" names a button they have never
/// laid eyes on, and the untracked-run case is an edge case being explained
/// before the main one has landed. Mechanics are learned by using the thing.
/// What belongs here is the reason to bother.
const String introHowItWorks =
    "I'll track your runs, keep your whole history in one place, and build you "
    'a full training plan when you want one.';
