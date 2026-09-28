import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/history/data/reported_run_backup.dart';
import 'package:mgk_run/src/features/history/data/run_backup.dart';
import 'package:mgk_run/src/features/settings/domain/backup_health.dart';

/// A backup that does whatever the test needs it to do next.
class _Backup implements RunBackup {
  bool throws = false;
  bool lands = true;
  final List<String> deleted = <String>[];

  T _run<T>(T value) {
    if (throws) throw StateError('the backup is unreachable');
    return value;
  }

  @override
  Future<bool> pushRun(String runId) async => _run(lands);

  @override
  Future<void> pushTrace(String runId) async {
    _run(true);
  }

  @override
  Future<int> backfill() async => _run(3);

  @override
  Future<void> deleteRun(String runId) async {
    deleted.add(runId);
    if (throws) throw StateError('the backup is unreachable');
  }
}

/// The wrapper that stops "a failed push cannot fail the caller" from meaning
/// "a failed push cannot be noticed by anybody". It is the only thing standing
/// between a backup that has been broken for a month and a backup that is
/// working, since every caller of these methods deliberately swallows.
void main() {
  late _Backup inner;
  late InMemoryBackupHealth health;
  late ReportedRunBackup backup;
  late DateTime clock;

  setUp(() {
    inner = _Backup();
    health = InMemoryBackupHealth();
    clock = DateTime(2026, 8, 23, 10);
    backup = ReportedRunBackup(inner: inner, health: health, now: () => clock);
  });

  test('records a push that landed', () async {
    expect(await backup.pushRun('r1'), isTrue);

    final record = await health.read();
    expect(record.lastSucceededAt, clock);
    expect(record.isFailing, isFalse);
  });

  test('records a push that threw, and still throws it', () async {
    // Rethrown rather than absorbed: the recorder and the editor each catch
    // for their own reasons, and this class exists to observe them, not to
    // take their decision away.
    inner.throws = true;

    await expectLater(backup.pushRun('r1'), throwsStateError);

    expect((await health.read()).isFailing, isTrue);
  });

  test('a push that returns false is a push that did not land', () async {
    // No exception, no signed-in user — nothing was sent, which is the only
    // fact this file exists to record. Treating a quiet `false` as a success
    // would report a backup that never happened as one that did.
    inner.lands = false;

    expect(await backup.pushRun('r1'), isFalse);

    expect((await health.read()).isFailing, isTrue);
  });

  test('the trace and the backfill are watched too', () async {
    // Runs are pushed from four places and the coach will add more. Wrapping
    // rather than reporting per call site is what keeps the fifth honest.
    inner.throws = true;

    await expectLater(backup.pushTrace('r1'), throwsStateError);
    expect((await health.read()).isFailing, isTrue);

    inner.throws = false;
    clock = clock.add(const Duration(minutes: 1));
    expect(await backup.backfill(), 3);
    expect((await health.read()).isFailing, isFalse);
  });

  test(
    'a later success clears the warning without erasing the failure',
    () async {
      inner.throws = true;
      await expectLater(backup.pushRun('r1'), throwsStateError);
      final failedAt = clock;

      inner.throws = false;
      clock = clock.add(const Duration(hours: 2));
      await backup.pushRun('r2');

      final record = await health.read();
      expect(
        record.isFailing,
        isFalse,
        reason: 'the backup is reachable again',
      );
      expect(
        record.lastFailedAt,
        failedAt,
        reason: 'the failure is history, not fiction',
      );
    },
  );

  test('a deletion is passed through unwatched', () async {
    // This asks the backup to remove something rather than to hold it, so a
    // failure is a deletion that did not happen — a different problem, with a
    // different remedy, and its own surface in Settings. Folding it in would
    // raise a warning that says the opposite of what went wrong.
    inner.throws = true;

    await expectLater(backup.deleteRun('r1'), throwsStateError);

    expect(inner.deleted, <String>['r1']);
    expect((await health.read()).isFailing, isFalse);
  });

  group('what the record claims', () {
    test('nothing at all before anything has been attempted', () {
      const fresh = BackupHealth();
      expect(fresh.isFailing, isFalse);
      expect(fresh.lastSucceededAt, isNull);
    });

    test('a failure with no success before it still reads as failing', () {
      final only = const BackupHealth().failedAt(DateTime(2026, 8, 23));
      expect(only.isFailing, isTrue);
    });
  });
}
