import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:mgk_lift/src/features/sync/data/supabase_backup_remote.dart';
import 'package:mgk_lift/src/features/sync/domain/sync_status.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A refused row is set aside until edited; everything else stops the run and
/// is retried. Getting a network failure wrong here would park a good workout
/// until somebody happened to edit it.
void main() {
  BackupProblem kind(Object e) => classifyBackupError(e).problem;

  PostgrestException pg(String code) =>
      PostgrestException(message: 'm', code: code);

  group('the row itself', () {
    test('a value the server will not store', () {
      expect(kind(pg('22003')), BackupProblem.rejected);
      expect(kind(pg('22P02')), BackupProblem.rejected);
      expect(kind(pg('23514')), BackupProblem.rejected);
      expect(kind(pg('23502')), BackupProblem.rejected);
      expect(kind(pg('P0001')), BackupProblem.rejected);
    });

    test('a row that belongs to somebody else', () {
      expect(kind(pg('42501')), BackupProblem.rejected);
    });
  });

  group('not the row — stop, and retry', () {
    test('no connection', () {
      expect(
        kind(ClientException('Connection refused')),
        BackupProblem.offline,
      );
      expect(
        kind(AuthRetryableFetchException(message: 'Failed host lookup')),
        BackupProblem.offline,
      );
    });

    test('a lapsed sign-in', () {
      expect(kind(pg('PGRST301')), BackupProblem.expired);
      expect(kind(pg('401')), BackupProblem.expired);
      expect(
        kind(const AuthException('Invalid Refresh Token')),
        BackupProblem.expired,
      );
    });

    test("the server's set-up", () {
      expect(kind(pg('PGRST106')), BackupProblem.unavailable);
      expect(kind(pg('PGRST205')), BackupProblem.unavailable);
      expect(kind(pg('42883')), BackupProblem.unavailable);
    });

    test('a server error or a timeout', () {
      expect(kind(pg('503')), BackupProblem.server);
      expect(kind(pg('57014')), BackupProblem.server);
      expect(kind(TimeoutException('slow')), BackupProblem.server);
    });

    test('anything unrecognised is retried, never set aside', () {
      expect(kind(StateError('what')), BackupProblem.server);
      expect(kind(pg('XX000')), BackupProblem.server);
    });
  });

  test('the raw code goes to the detail, for the log', () {
    expect(classifyBackupError(pg('22003')).detail, startsWith('22003'));
  });
}
