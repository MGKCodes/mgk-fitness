import 'dart:math';

import 'package:meta/meta.dart';

/// A value the coach has asked for, and the shape of the control that answers.
///
/// **Proposed by the coach, like [CoachTurn.suggestions].** The app does not
/// decide that now is the moment to ask a person their weight; it renders the
/// question it was given. The same rule, for the same reason: a control the
/// client raised on its own, whose answer is then sent as the lifter's message,
/// puts words in the coach's mouth.
///
/// Three kinds, because three is what the profile needs — see
/// docs/coach-profile.md. Anything else is a sentence, and the coach has a
/// composer for those.
enum CoachAskKind {
  /// A year, not a birthday. Programming cares whether somebody is thirty or
  /// sixty; a full date is more personal data carrying no more usable signal.
  yearOfBirth,
  heightCm,
  weightKg,
}

@immutable
class CoachAsk {
  const CoachAsk({
    required this.kind,
    required this.min,
    required this.max,
    required this.initial,
  });

  final CoachAskKind kind;
  final double min;
  final double max;

  /// Where the slider starts. A sensible middle rather than the minimum: a
  /// control that opens at 40 kg makes everybody drag, and a person who drags
  /// past their own number twice stops trusting the reading.
  final double initial;

  /// Asked once each, with ranges wide enough to be nobody's edge case.
  static const yearOfBirth = CoachAsk(
    kind: CoachAskKind.yearOfBirth,
    min: 1940,
    max: 2012,
    initial: 1994,
  );
  static const heightCm = CoachAsk(
    kind: CoachAskKind.heightCm,
    min: 130,
    max: 220,
    initial: 175,
  );
  static const weightKg = CoachAsk(
    kind: CoachAskKind.weightKg,
    min: 35,
    max: 200,
    initial: 80,
  );
}

/// One thing said, by either side.
@immutable
class CoachTurn {
  const CoachTurn({
    required this.id,
    required this.body,
    required this.fromCoach,
    required this.at,
    this.suggestions = const <String>[],
    this.ask,
    this.step,
    this.stepsTotal,
  });

  final String id;
  final String body;
  final bool fromCoach;
  final DateTime at;

  /// Replies the coach offered, for somebody who does not want to type.
  ///
  /// **On the turn that proposed them, deliberately.** The app is not allowed
  /// to put words in the coach's mouth — see [CoachService.ask] — and a chip
  /// the client invented, then sent as the lifter's own message, is precisely
  /// that. Hanging them off the turn means a turn with none renders none, and
  /// there is nowhere for a local default to appear.
  ///
  /// Not persisted. `coach.turns` stores what was said; an offer that was not
  /// taken was not said, and replaying it later would put stale options under a
  /// year-old message.
  final List<String> suggestions;

  /// A value this turn is asking for, rendered as a slider rather than left to
  /// the composer.
  ///
  /// None of these are typed. A height, a weight and a year are things somebody
  /// knows approximately and adjusts until it looks right, and a keyboard over
  /// a conversation is the most expensive thing you can put in front of a
  /// person who has not yet decided the app is worth the effort.
  final CoachAsk? ask;

  /// Where this turn sits in a fixed sequence of questions, 1-based, and how
  /// many there are. Both null outside one.
  ///
  /// **Drawn as chrome, never said.** A coach that announces "question two of
  /// four" is reading its own progress bar aloud, which turns a conversation
  /// into a form with a friendly voice. Like [suggestions] and [ask] it comes
  /// from the coach, because only the coach knows how many questions are left.
  final int? step;
  final int? stepsTotal;
}

/// Why a turn could not happen.
enum CoachFailure {
  /// No account.
  signedOut,

  /// Free tier. The coach is the paid half of the app.
  notEntitled,

  /// Today's allowance is spent.
  limitReached,

  /// No network, or the model is down. **The one the app must handle best** —
  /// it is the normal case in a gym basement, and it is not the lifter's fault.
  unavailable;

  String get message => switch (this) {
    signedOut => 'Sign in to talk to your coach.',
    notEntitled => 'Coaching is part of the paid plan.',
    limitReached =>
      'That is all the coaching for today. It resets in the morning.',
    unavailable => 'Could not reach your coach. Tracking works without one.',
  };
}

@immutable
class CoachException implements Exception {
  const CoachException(this.failure);

  final CoachFailure failure;

  @override
  String toString() => failure.message;
}

/// Talking to the coach.
///
/// **Every implementation goes through the server, never to a model directly.**
/// The app is open source; a key compiled into it would be a key published. The
/// interface exists so the screen can be driven by a fake.
abstract interface class CoachService {
  /// Sends a message and returns the reply. Throws [CoachException].
  ///
  /// **The conversation is not passed in.** The server keeps the transcript and
  /// replays it, so what the coach remembers is the same on any device and
  /// survives closing the app. It also means this app cannot put words in the
  /// coach's mouth and then ask it to act on them.
  /// [conversationId] is the session this turn belongs to, generated by
  /// [newCoachConversationId]. **The function uses what it is given and derives
  /// nothing** — see ADR-0002. Sending the same id twice continues a
  /// conversation; sending a new one starts one.
  Future<String> ask(String message, {required String conversationId});
}

/// Reading back what was already said.
///
/// **A separate interface from [CoachService], for the same reason
/// [CoachMemoryStore] is one:** this does not go through the Edge Function. The
/// function exists to hold a provider key and to gate spending, and neither
/// applies to selecting rows the caller already owns. RLS scopes the read, so
/// routing it through a function would add a hop and a second place for the
/// scoping to be wrong.
///
/// One method, because one is what the screen uses. Widening it to cover
/// deleting or paging would be inventing requirements for the fake that
/// implements it — clearing the transcript already exists, on
/// [CoachMemoryStore.clear], which cascades from `coach.conversations`.
/// How long a conversation stays open with nothing said in it.
///
/// **This is the session boundary**, and it is a gap rather than a lifecycle
/// event on purpose — see ADR-0002, and mgk_run's ADR-0025 which this follows.
/// Measured from the last turn, one rule settles the cold start, the return
/// from the background and the lifter who never closed the app: somebody who
/// checks a notification and comes back in ten seconds is still in the same
/// conversation; somebody who comes back after their session is not.
///
/// Thirty minutes is deliberately short, and the asymmetry is the argument.
/// Ending one too eagerly costs the coach context it already had, which the
/// rolling summary largely covers. Ending one too late is how a month-old
/// complaint about a shoulder gets read as today's.
const Duration coachSessionWindow = Duration(minutes: 30);

/// A fresh session id, generated by the client.
///
/// **Pure, and deliberately knows nothing about who is signed in.** The Edge
/// Function writes `user_id` from the verified JWT, so this only has to be
/// unique — putting the lifter's id in it would be decoration that a caller
/// then needs auth to produce.
///
/// The `lift:` prefix survives from the constant this replaces. `coach` is one
/// table shared with the run app, and a prefix is what makes a row readable
/// without joining to find out whose it is.
///
/// Entropy is not security here. Two devices opening a conversation in the same
/// microsecond would otherwise collide on a primary key, and a hard write
/// failure is a poor trade for seven characters.
String newCoachConversationId() {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final entropy = Random().nextInt(1 << 32).toRadixString(36);
  return 'lift:$stamp-$entropy';
}

/// One past conversation, as the "previous chats" list needs it.
@immutable
class CoachConversationSummary {
  const CoachConversationSummary({
    required this.id,
    required this.startedAt,
    required this.lastTurnAt,
    this.turns = 0,
    this.opening,
  });

  final String id;
  final DateTime startedAt;

  /// When it was last spoken in — what the list is ordered by.
  final DateTime lastTurnAt;

  /// How many turns it holds.
  final int turns;

  /// The first thing the lifter said, or null when there is nothing to show.
  ///
  /// **The opening line is what makes this a list somebody recognises
  /// themselves in.** A column of dates is a filing cabinet.
  final String? opening;
}

abstract interface class CoachTranscript {
  /// What the coach still has in mind in [conversationId], oldest first.
  ///
  /// **Deliberately the same window the server replays**, not everything ever
  /// said. The screen and the coach then agree about what the conversation is:
  /// a lifter who can see a turn can assume it was taken into account, and one
  /// who cannot see it can assume it was not. Showing more would reintroduce
  /// the gap this exists to close, in the direction that misleads.
  ///
  /// Never throws. A transcript that will not load is not worth an error on a
  /// screen whose composer works regardless — the fallback is an empty list,
  /// which is the state the screen already handles.
  Future<List<CoachTurn>> read(String conversationId);

  /// The conversation still open, or null when the last thing said is older
  /// than [window] — in which case the next thing said starts a new one.
  ///
  /// **Derived from the turns rather than stored as a pointer.** A pointer is
  /// one more thing that can disagree with the table it points into, and the
  /// answer is one row deep.
  Future<String?> openConversationId({Duration window});

  /// The conversations spoken in most recently, newest first.
  ///
  /// Sessions mean the screen no longer opens on last month's transcript, so
  /// this is where last month's transcript went.
  Future<List<CoachConversationSummary>> conversations({int limit});

  /// Everything said in [conversationId], oldest first.
  ///
  /// **Not [read], and the difference is the point.** [read] answers "what does
  /// the coach still have in mind", so it is windowed to what the server
  /// replays. This answers "what was said in this conversation", which for one
  /// that has ended is the whole of it — a read-back that stopped at twenty
  /// turns would silently truncate the thing somebody opened it to re-read.
  Future<List<CoachTurn>> fullTranscript(String conversationId);
}
