import 'package:mgk_auth/mgk_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/data/provider_ids.dart';
import '../domain/account_deleter.dart';

/// Calls the `delete-account` Edge Function.
///
/// Deletion needs privileges the client must never hold: removing an
/// `auth.users` row requires the service-role key, and the sweep crosses
/// schemas RLS deliberately walls off. So the client's whole job is "ask, then
/// sign out" — the function verifies the caller's JWT and does the work,
/// exactly as the `coach` function does for the LLM key (ADR-0007).
///
/// **The scope is the only thing this sends, and it is sent every time.** The
/// user id always comes from the verified token. Omitting the scope is not a
/// neutral default: the function reads an absent `app` as *everything, in every
/// app, and the login*, which is why [DeletionScope.everything] says so by
/// being chosen rather than by a field being forgotten.
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

  /// Resolved lazily, per call, so constructing this does not require Supabase
  /// to be initialised — the same reason `SupabaseAuth` does it.
  SupabaseClient get _client => _injected ?? Supabase.instance.client;

  @override
  Future<AccountDeletionResult> deleteAccount({
    required DeletionScope scope,
  }) async {
    final apple = await _appleRevocation();
    if (apple is AppleDeclined) throw const AccountDeletionException(_declined);

    final Object? data;
    try {
      final res = await _client.functions.invoke(
        'delete-account',
        // An explicit null rather than an omitted key, so the request says
        // "everything" in as many words. The function accepts both; a reader of
        // this file should not have to know that to know what happens.
        body: <String, Object?>{
          'app': scope.app,
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
          ids: liftProviderIds,
          auth: () => _client.auth,
        ).appleRevocation;
    return ask(_client.auth.currentUser);
  }

  static const _declined =
      'Nothing was deleted. An account made with Apple asks Apple to confirm '
      'before it goes.';

  static AccountDeletionResult _resultFrom(Map<String, dynamic> data) {
    final rows = data['deleted_rows'];
    final remaining = data['remaining_apps'];
    return AccountDeletionResult(
      accountDeleted: data['account_deleted'] == true,
      retainedReason: data['account_retained_reason'] as String?,
      remainingApps: remaining is List
          ? <String>[for (final app in remaining) app.toString()]
          : const <String>[],
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

  static String _messageForError(Object? code) => switch (code) {
    'unauthorized' => 'Please sign in again, then retry the deletion.',
    'unknown_app' =>
      'The app could not tell the server what to delete. '
          'Nothing was removed. Please update the app and try again.',
    'not_configured' =>
      'Deletion is not set up on the server yet. '
          'Email hello@mgkcodes.com and we will remove your data.',
    'delete_failed' =>
      'The server could not complete the deletion. '
          'Nothing was removed. Please try again.',
    _ =>
      'Something went wrong and your data was not deleted. '
          'Please try again.',
  };
}

/// An in-memory deleter, for tests and the preview harness.
///
/// Here rather than under `test/` for the reason [FakeAuth] gives: the preview
/// binary drives this screen too, and a second near-identical fake is how two
/// versions of "what deletion does" start disagreeing.
class FakeAccountDeleter implements AccountDeleter {
  FakeAccountDeleter({
    this.result = const AccountDeletionResult(accountDeleted: true),
    this.failWith,
  });

  final AccountDeletionResult result;
  final AccountDeletionException? failWith;

  /// Every scope asked for, in order, so a test can assert the screen sent the
  /// one the person chose rather than the one the button defaulted to.
  final List<DeletionScope> asked = <DeletionScope>[];

  @override
  Future<AccountDeletionResult> deleteAccount({
    required DeletionScope scope,
  }) async {
    asked.add(scope);
    final failure = failWith;
    if (failure != null) throw failure;
    return result;
  }
}
