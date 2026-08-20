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
  Future<String> ask(String message);
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
abstract interface class CoachTranscript {
  /// What the coach still has in mind, oldest first.
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
  Future<List<CoachTurn>> read();
}
