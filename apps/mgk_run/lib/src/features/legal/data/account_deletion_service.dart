import 'package:mgk_auth/mgk_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/data/provider_ids.dart';
import '../domain/account_deleter.dart';

/// Calls the `delete-account` Edge Function.
///
/// Deletion needs privileges the client must never hold: removing an
/// `auth.users` row requires the service-role key, and the sweep crosses schemas
/// that RLS deliberately walls off. So the client's whole job is "ask, then sign
/// out" — the function verifies the caller's JWT and does the work, exactly as
/// the `coach` function does for the LLM key (ADR-0007).
///
/// The Supabase client is resolved **lazily**, per call, so constructing this
/// service does not require Supabase to be initialised — the same trick
/// `AuthRepository` uses to stay widget-test friendly.
///
/// **An account made with Apple asks Apple first.** Apple requires its tokens
/// revoked when the account goes, and Supabase keeps none to revoke with, so a
/// fresh code from Apple's sheet goes with the request (`delete-account`'s
/// README). Closing that sheet stops the deletion; Apple failing does not.
class AccountDeletionService implements AccountDeleter {
  const AccountDeletionService({
    SupabaseClient? client,
    Future<AppleRevocation> Function(User? user)? apple,
  }) : _injected = client,
       _apple = apple;

  final SupabaseClient? _injected;
  final Future<AppleRevocation> Function(User? user)? _apple;

  SupabaseClient get _client => _injected ?? Supabase.instance.client;

  @override
  Future<AccountDeletionResult> deleteAccount() async {
    final apple = await _appleRevocation();
    if (apple is AppleDeclined) throw const AccountDeletionException(_declined);

    final Object? data;
    try {
      // **`app` is not optional here, whatever the wire contract says.**
      //
      // The function treats an absent `app` as "erase everything, everywhere,
      // and the login" — its own comment calls that safe-by-omission, on the
      // reasoning that a client which forgets to say gets the full erasure it
      // asked for in plain English. This client forgot to say. It sent no body
      // at all, so every Run account deletion took the whole-suite branch and
      // erased `lift.*` with it.
      //
      // Nothing else in this feature agreed with that. `AccountDeletionResult`
      // carries `loginRetainedForSiblingApp`, the server can answer
      // `sibling_app_data`, and `DeleteAccountScreen` tells the runner in as
      // many words: "we delete everything this app holds and keep only the
      // profile, so your data in Lift survives". The published privacy policy
      // says the same. Every layer was built for app-scoped deletion except
      // the one line that had to name the app.
      //
      // See the decision *Account deletion is scoped by the app asking, not by
      // which binary deployed last* — this is that decision's client half,
      // which never landed.
      final res = await _client.functions.invoke(
        'delete-account',
        body: <String, Object>{
          'app': 'run',
          if (apple is AppleCode) 'apple': apple.toJson(),
        },
      );
      data = res.data;
    } on FunctionException catch (e) {
      throw AccountDeletionException(_messageForError(_codeFrom(e.details)));
    } on Object {
      throw const AccountDeletionException(
        'We could not reach the server. Check your connection and try again.',
      );
    }

    if (data is! Map<String, dynamic>) {
      throw const AccountDeletionException(
        'The server returned an unexpected response. Nothing was deleted.',
      );
    }
    if (data['error'] != null) {
      throw AccountDeletionException(_messageForError(data['error']));
    }
    return _resultFrom(data);
  }

  Future<AppleRevocation> _appleRevocation() {
    final ask =
        _apple ??
        ProviderSignIn(
          ids: runProviderIds,
          auth: () => _client.auth,
        ).appleRevocation;
    return ask(_client.auth.currentUser);
  }

  static const _declined =
      'Nothing was deleted. An account made with Apple asks Apple to confirm '
      'before it goes.';

  static AccountDeletionResult _resultFrom(Map<String, dynamic> data) {
    final rows = data['deleted_rows'];
    return AccountDeletionResult(
      accountDeleted: data['account_deleted'] == true,
      retainedReason: data['account_retained_reason'] as String?,
      deletedRows: rows is Map
          ? <String, int>{
              for (final entry in rows.entries)
                if (entry.value is num)
                  entry.key.toString(): (entry.value as num).toInt(),
            }
          : const <String, int>{},
    );
  }

  static String? _codeFrom(Object? details) {
    if (details is Map && details['error'] != null) {
      return details['error'].toString();
    }
    return null;
  }

  static String _messageForError(Object? code) {
    switch (code) {
      case 'unauthorized':
        return 'Please sign in again, then retry the deletion.';
      case 'not_configured':
        return 'Deletion is not set up on the server yet. '
            'Email run@mgkfitness.mgkcodes.com and we will remove your '
            'data.';
      case 'delete_failed':
        return 'The server could not complete the deletion. '
            'Nothing was removed. Please try again.';
      default:
        return 'Something went wrong and your data was not deleted. '
            'Please try again.';
    }
  }
}
