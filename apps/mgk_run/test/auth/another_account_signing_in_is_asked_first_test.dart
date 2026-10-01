import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/auth/presentation/auth_gate.dart';
import 'package:mgk_run/src/features/history/domain/run_draft.dart';
import 'package:mgk_run/src/features/history/domain/run_writer.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_store.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';
import 'package:mgk_auth/mgk_auth.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **A second account signing in got the first account's training.**
///
/// One database, one photo, one stored name and one backup answer for the
/// whole phone, and nothing saying whose. When a different account signed in,
/// the shell ran the restore and then the backfill for it, and the backfill
/// pushed every local run the server lacked into the new account, GPS traces
/// and all. The new account saw the first runner's log, plan, injury notes and
/// coach transcripts, and the coach wrote its brief about them from somebody
/// else's training.
///
/// Now the phone knows whose training it holds, and a different account is
/// asked -- erase it, or sign out -- before anything restores, backfills or
/// reaches the coach. These drive the real gate and shell; only the stores
/// behind them are fakes.
void main() {
  late FakeAuthRepository auth;
  late InMemoryLocalDataOwner owner;
  late _Training training;
  late LocalDataGuard guard;
  late _CountingRestore restore;
  late _CountingWriter writer;

  setUp(() {
    owner = InMemoryLocalDataOwner('alex');
    training = _Training();
    guard = LocalDataGuard(owner: owner, data: training);
    restore = _CountingRestore();
    writer = _CountingWriter();
  });

  Future<void> pumpGate(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AuthGate(
          auth: auth,
          introStore: InMemoryIntroStore(done: true),
          localData: guard,
          restore: restore,
          runEditor: writer,
          // Granted, and deliberately not keyed to anybody: what stops the
          // pull and the push here is the question, not the answer on file.
          consentStore: InMemoryBackupConsent(BackupConsent.granted),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Somebody else signing in over a shell that is already running.
  Future<void> signInAs(WidgetTester tester, String id, String email) async {
    auth.userId = id;
    await auth.signIn(email: email, password: 'password');
    await tester.pumpAndSettle();
  }

  testWidgets('the same account signing back in is not asked', (tester) async {
    auth = FakeAuthRepository(signedIn: true, email: 'alex@example.com')
      ..userId = 'alex';
    await pumpGate(tester);
    expect(find.text('Record a run'), findsOneWidget);
    final restoredAtLaunch = restore.calls;
    expect(restoredAtLaunch, 1);

    await auth.signOut();
    await tester.pumpAndSettle();
    await signInAs(tester, 'alex', 'alex@example.com');

    expect(find.byType(AnotherAccountScreen), findsNothing);
    expect(find.text('Record a run'), findsOneWidget);
    expect(restore.calls, restoredAtLaunch + 1, reason: 'their own history');
    expect(training.erased, 0);
  });

  testWidgets('a different account is asked, and nothing moves first', (
    tester,
  ) async {
    auth = FakeAuthRepository(signedIn: true, email: 'alex@example.com')
      ..userId = 'alex';
    await pumpGate(tester);
    await auth.signOut();
    await tester.pumpAndSettle();
    final restores = restore.calls;
    final backfills = writer.backfills;

    await signInAs(tester, 'sam', 'sam@example.com');

    expect(find.byType(AnotherAccountScreen), findsOneWidget);
    expect(
      find.text("Erase this phone's training and continue as sam@example.com"),
      findsOneWidget,
    );
    expect(find.text('Sign out'), findsOneWidget);
    expect(
      restore.calls,
      restores,
      reason: "nothing of Sam's may be pulled into Alex's training",
    );
    expect(
      writer.backfills,
      backfills,
      reason: "and none of Alex's runs may be pushed into Sam's account",
    );
    expect(training.erased, 0, reason: 'nothing is erased without asking');
    expect(await owner.read(), 'alex');
  });

  testWidgets('a session for another account at launch paints nothing first', (
    tester,
  ) async {
    auth = FakeAuthRepository(signedIn: true, email: 'sam@example.com')
      ..userId = 'sam';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AuthGate(
          auth: auth,
          introStore: InMemoryIntroStore(done: true),
          localData: guard,
          restore: restore,
          runEditor: writer,
          consentStore: InMemoryBackupConsent(BackupConsent.granted),
        ),
      ),
    );
    // The first frame, before the answer: blank, not Alex's log.
    expect(find.text('Record a run'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(AnotherAccountScreen), findsOneWidget);
    expect(find.text('Record a run'), findsNothing);
    expect(restore.calls, 0);
    expect(writer.backfills, 0);
  });

  testWidgets('erasing hands the phone over, and only then restores', (
    tester,
  ) async {
    auth = FakeAuthRepository(signedIn: true, email: 'sam@example.com')
      ..userId = 'sam';
    await pumpGate(tester);
    expect(restore.calls, 0);

    await tester.tap(
      find.text("Erase this phone's training and continue as sam@example.com"),
    );
    await tester.pumpAndSettle();

    expect(training.erased, 1);
    expect(await owner.read(), 'sam');
    expect(find.byType(AnotherAccountScreen), findsNothing);
    expect(find.text('Record a run'), findsOneWidget);
    expect(restore.calls, 1, reason: "Sam's own history, onto an empty phone");
  });

  testWidgets('signing out leaves the phone exactly as it was', (tester) async {
    auth = FakeAuthRepository(signedIn: true, email: 'sam@example.com')
      ..userId = 'sam';
    await pumpGate(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(auth.isSignedIn, isFalse);
    expect(training.erased, 0);
    expect(await owner.read(), 'alex');
    expect(find.byType(AnotherAccountScreen), findsNothing);
  });

  testWidgets('it clears whatever was open on top of the shell', (
    tester,
  ) async {
    // Sign-in is raised as a route over a running shell -- from Settings, the
    // plan gate, the backup prompt. Left there, the question would sit behind
    // Alex's Settings, name and photo on show.
    auth = FakeAuthRepository(signedIn: false)..userId = 'alex';
    await pumpGate(tester);
    // Not awaited: the route's future completes only when it is popped, which
    // is the thing being tested.
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Alex, in Settings')),
            ),
          ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alex, in Settings'), findsOneWidget);

    await signInAs(tester, 'sam', 'sam@example.com');

    expect(find.text('Alex, in Settings'), findsNothing);
    expect(find.byType(AnotherAccountScreen), findsOneWidget);
  });

  testWidgets('the first account on a phone nobody has claimed is not asked', (
    tester,
  ) async {
    // Weeks of runs with no account, then an account: the runs are theirs.
    await owner.clear();
    auth = FakeAuthRepository(signedIn: false)..userId = 'alex';
    await pumpGate(tester);

    await signInAs(tester, 'sam', 'sam@example.com');

    expect(find.byType(AnotherAccountScreen), findsNothing);
    expect(await owner.read(), 'sam');
    expect(training.erased, 0);
  });
}

class _Training implements LocalTrainingData {
  bool hasTraining = true;
  int erased = 0;

  @override
  Future<bool> isEmpty() async => !hasTraining;

  @override
  Future<void> eraseAll() async {
    erased++;
    hasTraining = false;
  }
}

class _CountingRestore implements DataRestore {
  int calls = 0;

  @override
  Future<RestoreResult> restoreAll() async {
    calls++;
    return RestoreResult();
  }
}

class _CountingWriter implements RunWriter {
  int backfills = 0;

  @override
  Future<int> backfill() async {
    backfills++;
    return 0;
  }

  @override
  Future<String> add(RunDraft draft) async => 'run';

  @override
  Future<RunDraft?> draftOf(String runId) async => null;

  @override
  Future<void> edit(String runId, RunDraft draft) async {}

  @override
  Future<void> delete(String runId) async {}
}
