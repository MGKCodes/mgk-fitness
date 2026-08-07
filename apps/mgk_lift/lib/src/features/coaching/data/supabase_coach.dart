import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/coach.dart';

/// The coach, via the `coach` Edge Function.
///
/// **There is no model key in this app and there never will be.** The function
/// holds it; this sends a message and the caller's JWT. Everything that costs
/// money — the entitlement check, the rate limit and the spend cap — is decided
/// there, so nothing in this file is worth tampering with.
///
/// The same function serves Run, so a request has to say which surface it is
/// for. `lift_chat` is the only one this app calls, and the function reads which
/// app pays for it from that name rather than from anything sent here.
///
/// Note what is deliberately NOT sent: the training log, the conversation, or
/// what the coach remembers. The function reads all three under this caller's
/// own JWT, so RLS decides what the coach sees, and this app cannot describe a
/// session that did not happen or a sentence nobody said. That is why the
/// request is one line long.
class SupabaseCoach implements CoachService {
  SupabaseCoach(this._client);

  final SupabaseClient _client;

  static const _surface = 'lift_chat';

  @override
  Future<String> ask(String message) async {
    if (_client.auth.currentUser == null) {
      throw const CoachException(CoachFailure.signedOut);
    }

    try {
      final res = await _client.functions.invoke(
        'coach',
        body: <String, Object?>{'surface': _surface, 'message': message},
      );

      final data = res.data;
      if (data is Map && data['reply'] is String) {
        final reply = data['reply'] as String;
        if (reply.trim().isEmpty) {
          throw const CoachException(CoachFailure.unavailable);
        }
        return reply;
      }
      throw const CoachException(CoachFailure.unavailable);
    } on FunctionException catch (e) {
      throw CoachException(_map(e));
    } on CoachException {
      rethrow;
    } on Object {
      // Sockets, DNS, timeouts. Ordinary in a gym basement and not an error
      // worth dressing up.
      throw const CoachException(CoachFailure.unavailable);
    }
  }

  /// Maps the function's status codes to something the screen can say.
  ///
  /// The codes are the contract, not the bodies — the function deliberately
  /// never forwards an upstream error message, because those can carry our
  /// billing details rather than anything about the lifter.
  ///
  /// 429 covers both a rate limit and the rolling spend cap. They are one thing
  /// to a lifter — come back later — and the function distinguishes them in the
  /// body for when that stops being true.
  static CoachFailure _map(FunctionException e) => switch (e.status) {
    401 => CoachFailure.signedOut,
    402 => CoachFailure.notEntitled,
    429 => CoachFailure.limitReached,
    _ => CoachFailure.unavailable,
  };
}

/// A scripted coach, for tests and the preview harness.
class FakeCoach implements CoachService {
  FakeCoach({
    this.reply = 'Add 2.5kg to your top set next week.',
    this.failWith,
  });

  final String reply;
  final CoachFailure? failWith;

  /// Everything asked of it, in order, so a test can assert what was sent.
  final List<String> asked = <String>[];

  @override
  Future<String> ask(String message) async {
    asked.add(message);
    final failure = failWith;
    if (failure != null) throw CoachException(failure);
    return reply;
  }
}
