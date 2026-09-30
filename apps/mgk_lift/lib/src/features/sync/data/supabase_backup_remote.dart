import 'dart:async';

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/backup_remote.dart';
import '../domain/sync_status.dart';

/// Backup's server half, on Supabase — and the only code that sees the
/// client's own exceptions. Everything thrown from here is a [BackupFailure].
class SupabaseBackupRemote implements BackupRemote {
  SupabaseBackupRemote(this._client);

  final SupabaseClient _client;

  /// Whether `lift.save_workout` turned out not to exist on this server.
  ///
  /// The function arrives by migration, and the app may reach a server before
  /// the migration does. Until then a workout goes up the way it always has —
  /// four requests, not atomic — rather than not at all. Remembered for this
  /// launch so each workout does not ask first.
  bool _saveFunctionMissing = false;

  /// `lift` is not the default schema and is not `public`; PostgREST only
  /// serves it because it is listed under Exposed Schemas in the dashboard.
  /// Getting this wrong is a 404 on every call, not a compile error.
  SupabaseQuerySchema get _lift => _client.schema('lift');

  @override
  String? get userId => _client.auth.currentUser?.id;

  @override
  Future<void> save(Map<String, Object?> workout) async {
    try {
      if (!_saveFunctionMissing) {
        try {
          await _lift.rpc<void>(
            'save_workout',
            params: <String, Object?>{'payload': workout},
          );
          return;
        } on PostgrestException catch (e) {
          if (e.code != 'PGRST202') rethrow;
          _saveFunctionMissing = true;
        }
      }
      await _saveInParts(workout);
    } on Object catch (e) {
      throw classifyBackupError(e);
    }
  }

  /// The old way: the row, then the movements deleted and inserted, then the
  /// sets. Kept only for a server without `lift.save_workout`.
  Future<void> _saveInParts(Map<String, Object?> workout) async {
    final uid = userId;
    if (uid == null) {
      throw const BackupFailure(BackupProblem.signedOut, 'no account');
    }
    final id = workout['id']! as String;
    final exercises = (workout['exercises']! as List<Object?>)
        .cast<Map<String, Object?>>();

    await _lift.from('workouts').upsert(<String, Object?>{
      // Not `updated_at`: the server's own clock stamps it, as the function
      // does — this phone's clock is not the one the pull watermark reads.
      for (final e in workout.entries)
        if (e.key != 'exercises' && e.key != 'updated_at') e.key: e.value,
      'user_id': uid,
    });
    // Children replaced wholesale rather than diffed. They have no clock of
    // their own, so there is nothing to diff against; deleting first is also
    // what makes a locally removed set actually disappear from the server.
    await _lift.from('exercises').delete().eq('workout_id', id);
    if (exercises.isEmpty) return;

    await _lift.from('exercises').insert(<Map<String, Object?>>[
      for (final e in exercises)
        <String, Object?>{
          for (final f in e.entries)
            if (f.key != 'sets') f.key: f.value,
          'user_id': uid,
          'workout_id': id,
        },
    ]);
    final sets = <Map<String, Object?>>[
      for (final e in exercises)
        for (final s
            in (e['sets']! as List<Object?>).cast<Map<String, Object?>>())
          <String, Object?>{...s, 'user_id': uid, 'exercise_id': e['id']},
    ];
    if (sets.isNotEmpty) await _lift.from('sets').insert(sets);
  }

  @override
  Future<List<Map<String, dynamic>>> changedSince(DateTime? since) async {
    final uid = userId;
    if (uid == null) {
      throw const BackupFailure(BackupProblem.signedOut, 'no account');
    }
    try {
      var query = _lift
          .from('workouts')
          .select('*, exercises(*, sets(*))')
          .eq('user_id', uid);
      if (since != null) {
        query = query.gt('updated_at', since.toUtc().toIso8601String());
      }
      final rows = await query.order('updated_at') as List<dynamic>;
      return rows.cast<Map<String, dynamic>>();
    } on Object catch (e) {
      throw classifyBackupError(e);
    }
  }
}

/// What a failure from the Supabase client means for backup.
///
/// **Refused rows and broken runs are different things, and the difference is
/// the whole of this function.** A value the server will not store is about
/// one workout: set it aside and carry on. A dropped connection, a server
/// error or a lapsed sign-in is about every workout: stop, and try again.
/// Anything not recognised is treated as the second — retried — because
/// wrongly setting a good workout aside until it is edited is the worse
/// mistake.
BackupFailure classifyBackupError(Object error) {
  if (error is BackupFailure) return error;

  if (error is PostgrestException) {
    final code = error.code ?? '';
    final detail = '$code: ${error.message}';
    // PostgREST's own: PGRST3xx is the JWT; the rest here are a schema,
    // table or function it cannot find — the server's set-up, not the row.
    if (code.startsWith('PGRST3')) {
      return BackupFailure(BackupProblem.expired, detail);
    }
    if (const <String>{
      'PGRST106',
      'PGRST202',
      'PGRST205',
      '42883',
      '42P01',
      '42703',
      '404',
    }.contains(code)) {
      return BackupFailure(BackupProblem.unavailable, detail);
    }
    if (code == '401') return BackupFailure(BackupProblem.expired, detail);
    // SQLSTATE classes 22 (data) and 23 (integrity), a function's own raise,
    // and a policy refusing this row: the row itself.
    if (code.startsWith('22') ||
        code.startsWith('23') ||
        code == 'P0001' ||
        code == '42501') {
      return BackupFailure(BackupProblem.rejected, detail);
    }
    return BackupFailure(BackupProblem.server, detail);
  }

  if (error is AuthRetryableFetchException) {
    return BackupFailure(BackupProblem.offline, error.message);
  }
  if (error is AuthException) {
    return BackupFailure(BackupProblem.expired, error.message);
  }
  if (error is ClientException || '$error'.contains('SocketException')) {
    return BackupFailure(BackupProblem.offline, '$error');
  }
  if (error is TimeoutException) {
    return BackupFailure(BackupProblem.server, '$error');
  }
  return BackupFailure(BackupProblem.server, '$error');
}
