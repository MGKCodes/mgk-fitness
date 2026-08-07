import 'package:meta/meta.dart';

/// One thing said, by either side.
@immutable
class CoachTurn {
  const CoachTurn({
    required this.id,
    required this.body,
    required this.fromCoach,
    required this.at,
  });

  final String id;
  final String body;
  final bool fromCoach;
  final DateTime at;
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
  /// [history] is everything said so far, oldest first, NOT including
  /// [message]. Without it every turn arrives at the model alone, and a coach
  /// that cannot remember the sentence before is not having a conversation —
  /// "why?" would be answered as if it were the first thing anyone had said.
  Future<String> ask(String message, {List<CoachTurn> history});
}
