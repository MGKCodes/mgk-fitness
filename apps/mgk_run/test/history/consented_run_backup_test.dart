import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/history/data/consented_run_backup.dart';
import 'package:mgk_run/src/features/history/data/run_backup.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';

/// Records what reached it, so a test can assert on what did NOT.
class _SpyBackup implements RunBackup {
  final List<String> pushed = <String>[];
  final List<String> traced = <String>[];
  final List<String> deleted = <String>[];

  @override
  Future<bool> pushRun(String runId) async {
    pushed.add(runId);
    return true;
  }

  @override
  Future<void> pushTrace(String runId) async => traced.add(runId);

  @override
  Future<void> deleteRun(String runId) async => deleted.add(runId);

  int backfills = 0;

  @override
  Future<int> backfill() async {
    backfills++;
    return 7;
  }
}

void main() {
  late _SpyBackup inner;
  late InMemoryBackupConsent consent;
  late ConsentedRunBackup backup;

  void given(BackupConsent value) {
    inner = _SpyBackup();
    consent = InMemoryBackupConsent(value);
    backup = ConsentedRunBackup(inner: inner, consent: consent);
  }

  // ---- the three states ----------------------------------------------------

  test('nothing leaves the phone before the runner has been asked', () async {
    // `unknown` behaves as a no. An install is not consent, and Art. 9 data
    // needs consent that was actually given.
    given(BackupConsent.unknown);

    expect(await backup.pushRun('r1'), isFalse);
    await backup.pushTrace('r1');

    expect(inner.pushed, isEmpty);
    expect(inner.traced, isEmpty);
  });

  test('nothing leaves the phone after a refusal', () async {
    given(BackupConsent.declined);

    expect(await backup.pushRun('r1'), isFalse);
    await backup.pushTrace('r1');

    expect(inner.pushed, isEmpty);
    expect(inner.traced, isEmpty);
  });

  test('everything is mirrored once consent is given', () async {
    given(BackupConsent.granted);

    expect(await backup.pushRun('r1'), isTrue);
    await backup.pushTrace('r1');

    expect(inner.pushed, <String>['r1']);
    expect(inner.traced, <String>['r1']);
  });

  // ---- withdrawal ----------------------------------------------------------

  test(
    'withdrawing consent stops the next push, not the next launch',
    () async {
      // Read per call rather than cached at construction: a runner who turns
      // backup off expects it off for the run they are finishing.
      given(BackupConsent.granted);
      await backup.pushRun('r1');

      await consent.write(BackupConsent.declined);
      await backup.pushRun('r2');

      expect(inner.pushed, <String>[
        'r1',
      ], reason: 'r2 must not have been sent');
    },
  );

  test('granting consent later starts the mirror without a restart', () async {
    given(BackupConsent.unknown);
    await backup.pushRun('r1');

    await consent.write(BackupConsent.granted);
    await backup.pushRun('r2');

    expect(inner.pushed, <String>['r2']);
  });

  test('a backfill is gated like the pushes it is made of', () async {
    // The operation a runner who declined would least want run for them: it
    // sends every run on the phone at once.
    given(BackupConsent.declined);
    expect(await backup.backfill(), 0);
    expect(inner.backfills, 0);

    given(BackupConsent.unknown);
    expect(await backup.backfill(), 0);
    expect(inner.backfills, 0);

    given(BackupConsent.granted);
    expect(await backup.backfill(), 7);
    expect(inner.backfills, 1);
  });

  // ---- the exception, and why it is one ------------------------------------

  test('deletion always reaches the backup, whatever consent says', () async {
    // The others ask "may I send this?". This asks "remove what you already
    // have", and the runner who just withdrew consent is precisely the person
    // who needs it to work. Gating it would strand their data in the place
    // they asked it to leave.
    for (final state in BackupConsent.values) {
      given(state);
      await backup.deleteRun('r1');
      expect(inner.deleted, <String>['r1'], reason: state.name);
    }
  });

  // ---- the flags the UI reads ----------------------------------------------

  test('needsAsking separates an unanswered question from a refusal', () async {
    // Without this the UI would re-prompt someone who already said no.
    expect(BackupConsent.unknown.needsAsking, isTrue);
    expect(BackupConsent.declined.needsAsking, isFalse);
    expect(BackupConsent.granted.needsAsking, isFalse);

    expect(BackupConsent.unknown.allowsBackup, isFalse);
    expect(BackupConsent.declined.allowsBackup, isFalse);
    expect(BackupConsent.granted.allowsBackup, isTrue);
  });
}
