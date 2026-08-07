import 'package:meta/meta.dart';

/// What the coach has learned about this lifter, and when.
///
/// A few sentences of prose, written by the coach and reloaded into every
/// conversation. It is **shown to the lifter and not editable by them** — the
/// only thing they can do to it is delete it, which is why the prompt that
/// writes it is constrained to what they actually said rather than to what a
/// model concluded about them.
///
/// [updatedAt] is here because "when did it decide that" is the first question
/// anyone asks about a sentence they disagree with.
@immutable
class CoachMemory {
  const CoachMemory({required this.summary, required this.updatedAt});

  /// The memory itself. Empty when the coach has not formed one yet — which is
  /// a real state, not an error: it is written after a conversation has run
  /// long enough to be worth remembering.
  final String summary;

  final DateTime? updatedAt;

  bool get isEmpty => summary.trim().isEmpty;

  static const CoachMemory none = CoachMemory(summary: '', updatedAt: null);
}

/// Reading and erasing what the coach remembers.
///
/// Deliberately has no `save`. An edited memory is silently rewritten by the
/// next regeneration, so a text field would be a promise the coach does not
/// keep; erasing is the control that actually holds.
abstract interface class CoachMemoryStore {
  /// The current memory. Throws [CoachMemoryException].
  Future<CoachMemory> read();

  /// Erases the memory **and the conversations behind it**, for this app only.
  ///
  /// Both, because either alone is a half-measure that undoes itself: the
  /// memory is rebuilt from the transcript, and a transcript with no memory is
  /// still a stored record of somebody discussing their body. Throws
  /// [CoachMemoryException].
  Future<void> clear();
}

/// Why the memory could not be read or erased.
enum CoachMemoryFailure {
  signedOut,

  /// No network, or the backend is down.
  unavailable;

  String get message => switch (this) {
    signedOut => 'Sign in to see what your coach remembers.',
    unavailable => 'Could not reach your coach. Try again in a moment.',
  };
}

@immutable
class CoachMemoryException implements Exception {
  const CoachMemoryException(this.failure);

  final CoachMemoryFailure failure;

  @override
  String toString() => failure.message;
}
