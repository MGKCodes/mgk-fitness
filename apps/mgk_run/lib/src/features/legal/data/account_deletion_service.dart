import 'package:supabase_flutter/supabase_flutter.dart';

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
class AccountDeletionService implements AccountDeleter {
  const AccountDeletionService({SupabaseClient? client}) : _injected = client;

  final SupabaseClient? _injected;

  SupabaseClient get _client => _injected ?? Supabase.instance.client;

  @override
  Future<AccountDeletionResult> deleteAccount() async {
    final Object? data;
    try {
      final res = await _client.functions.invoke('delete-account');
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
            'Email hello@mgkcodes.com and we will remove your data.';
      case 'delete_failed':
        return 'The server could not complete the deletion. '
            'Nothing was removed. Please try again.';
      default:
        return 'Something went wrong and your data was not deleted. '
            'Please try again.';
    }
  }
}
