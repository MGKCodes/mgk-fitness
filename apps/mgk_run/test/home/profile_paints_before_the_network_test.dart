import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/history/domain/run_writer.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_run/src/features/profile/presentation/backup_card.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';
import 'package:mgk_run/src/features/settings/domain/backup_health.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **The log is on the phone, so it must not wait for the server.**
///
/// Everything Profile and the run log draw comes from the shell's `_allRuns`,
/// which only `_refreshHome` fills — and `_refreshHome` used to run *last*, at
/// the end of a sequence that awaited a modal consent dialog and then an
/// unbounded `restoreAll()`. A runner signing in on a phone holding three years
/// of running watched a blank page until the network answered, and watched it
/// forever if the network never did. Reported on the build 13 sheet as "Profile
/// reads from the server first and shows a blank screen until it loads".
///
/// The read itself was always local — `DriftRunRepository.fetchRuns`, ADR-0023,
/// chosen precisely so the log reads the phone. It was the *ordering* that gave
/// it away.
///
/// Driven through the real shell rather than [ProfileScreen], because the
/// screen was never the problem: it renders whatever it is handed, and what it
/// was handed was an empty list for as long as the network took.
void main() {
  RunSummary run(int daysAgo) => RunSummary(
    id: 'run-$daysAgo',
    startedAt: DateTime.now().subtract(Duration(days: daysAgo)),
    duration: const Duration(minutes: 30),
    distanceMeters: 5000,
    avgPaceSecondsPerKm: 360,
  );

  testWidgets('the log is on screen while the restore is still hanging', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final restore = _NeverAnswers();
    addTearDown(restore.abandon);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'sam@example.com'),
          initialTab: 2,
          restore: restore,
          historySource: () async => <RunSummary>[run(1), run(2), run(3)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('3 RUNS'),
      findsOneWidget,
      reason: 'the phone knew this before the server was asked',
    );
    expect(restore.asked, isTrue, reason: 'and the restore did still start');
  });

  testWidgets('and it says the backup is running while it is', (tester) async {
    // The other half of the same field-test note: "Profile needs a visible sync
    // state — showing whether data has reached the back end." Asserted through
    // the shell because the state is assembled there, from three things that
    // live in three places: the auth session, the consent store, and the local
    // health record `main.dart` used to say nothing outside Settings read.
    await tester.binding.setSurfaceSize(const Size(430, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final restore = _NeverAnswers();
    addTearDown(restore.abandon);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'sam@example.com'),
          initialTab: 2,
          restore: restore,
          consentStore: InMemoryBackupConsent(BackupConsent.granted),
          backupHealth: InMemoryBackupHealth(),
          historySource: () async => <RunSummary>[run(1)],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Backing up…'), findsOneWidget);
  });

  testWidgets('and says nothing at all without an account', (tester) async {
    // No account means nowhere for the data to go, which is a state to leave
    // unremarked rather than to warn about (ADR-0019).
    await tester.binding.setSurfaceSize(const Size(430, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(),
          initialTab: 2,
          consentStore: InMemoryBackupConsent(BackupConsent.granted),
          backupHealth: InMemoryBackupHealth(),
          historySource: () async => <RunSummary>[run(1)],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BackupCard), findsNothing);
  });
}

/// A restore that starts and never finishes — a dead connection, which is the
/// state the ordering has to survive rather than the one it may assume away.
class _NeverAnswers implements DataRestore {
  final Completer<RestoreResult> _never = Completer<RestoreResult>();
  bool asked = false;

  @override
  Future<RestoreResult> restoreAll() {
    asked = true;
    return _never.future;
  }

  void abandon() {
    if (!_never.isCompleted) _never.complete(RestoreResult());
  }
}
