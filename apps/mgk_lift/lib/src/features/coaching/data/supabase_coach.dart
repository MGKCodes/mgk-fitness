import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/coach.dart';

/// The coach, via the `coach` Edge Function.
///
/// **There is no model key in this app and there never will be.** The function
/// holds it; this sends a message and the caller's JWT. Everything that costs
/// money — the entitlement check and the daily allowance — is decided there, so
/// nothing in this file is worth tampering with.
class SupabaseCoach implements CoachService {
  SupabaseCoach(this._client);

  final SupabaseClient _client;

  @override
  Future<String> ask(String message) async {
    if (_client.auth.currentUser == null) {
      throw const CoachException(CoachFailure.signedOut);
    }

    try {
      final res = await _client.functions.invoke(
        'coach',
        body: <String, Object?>{'message': message},
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
  static CoachFailure _map(FunctionException e) => switch (e.status) {
    401 => CoachFailure.signedOut,
    402 => CoachFailure.notEntitled,
    429 => CoachFailure.limitReached,
    _ => CoachFailure.unavailable,
  };
}

/// A scripted coach, for tests and the preview harness.
class FakeCoach implements CoachService {
  FakeCoach({this.reply = 'Add 2.5kg to your top set next week.', this.failWith});

  final String reply;
  final CoachFailure? failWith;

  @override
  Future<String> ask(String message) async {
    final failure = failWith;
    if (failure != null) throw CoachException(failure);
    return reply;
  }
}
