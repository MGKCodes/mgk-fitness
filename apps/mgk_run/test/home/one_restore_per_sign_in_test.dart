import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/auth/data/auth_repository.dart';
import 'package:mgk_run/src/features/history/domain/run_writer.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **A4 on the build 13 sheet: the restore announced itself over and over.**
///
/// Three causes, and the shell owned one of them. `authChanges()` was
/// `Stream<void>`, so this listener could not tell a sign-in from a token
/// refresh — and gotrue emits the latter periodically and on every resume. Each
/// one re-entered the restore, and because `_restoreRuns` reported the rows it
/// *fetched* rather than the rows it *inserted*, each one had a sentence to
/// show. A runner watched their history be discovered again every few minutes.
///
/// Asserted at the shell rather than on the stream, because the defect was the
/// reaction rather than the event: the listener has to hold the last identity
/// it acted on, and only a mounted shell does that.
void main() {
  RunSummary run(int daysAgo) => RunSummary(
    id: 'run-$daysAgo',
    startedAt: DateTime.now().subtract(Duration(days: daysAgo)),
    duration: const Duration(minutes: 30),
    distanceMeters: 5000,
    avgPaceSecondsPerKm: 360,
  );

  Future<void> pumpShell(
    WidgetTester tester, {
    required FakeAuthRepository auth,
    required DataRestore restore,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        // No coach: its mark reveals on a repeating timer and `pumpAndSettle`
        // never returns on a shell holding one.
        home: HomeShell(
          auth: auth,
          restore: restore,
          historySource: () async => <RunSummary>[run(1), run(2)],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('gotrue re-announcing the same session restores once', (
    tester,
  ) async {
    final auth = FakeAuthRepository(signedIn: true, email: 'sam@example.com');
    final restore = _CountingRestore();
    await pumpShell(tester, auth: auth, restore: restore);

    // What a token refresh looks like from here, three times over, plus a
    // rename. None of them is somebody arriving.
    auth
      ..emit(AuthChange.signedIn)
      ..emit(AuthChange.signedIn)
      ..emit(AuthChange.signedIn)
      ..emit(AuthChange.userUpdated);
    await tester.pumpAndSettle();

    expect(
      restore.calls,
      1,
      reason: 'the launch restored; nothing after it was a new identity',
    );
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('a restore that inserted nothing says nothing', (tester) async {
    // The other half of A4, at this seam. A phone that already holds everything
    // used to be told it had restored all of it, on every launch forever,
    // because the count was of rows fetched rather than rows added.
    final auth = FakeAuthRepository(signedIn: true, email: 'sam@example.com');
    final restore = _CountingRestore(added: 0);
    await pumpShell(tester, auth: auth, restore: restore);

    expect(restore.calls, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a different person signing in does restore', (tester) async {
    // The guard against over-correcting. De-duplicating on the event rather
    // than on the identity would swallow this, and a runner signing into their
    // own account on a shared phone would never see their history.
    final auth = FakeAuthRepository(signedIn: true, email: 'sam@example.com')
      ..userId = 'sam';
    final restore = _CountingRestore();
    await pumpShell(tester, auth: auth, restore: restore);
    expect(restore.calls, 1);

    auth
      ..userId = 'alex'
      ..emit(AuthChange.signedIn);
    await tester.pumpAndSettle();

    expect(restore.calls, 2, reason: 'a second identity is a second history');
  });
}

/// Records that it was asked, and how much it claims to have brought back.
class _CountingRestore implements DataRestore {
  _CountingRestore({this.added = 3});

  /// Rows this restore reports having *inserted* — the count the shell decides
  /// whether to say anything about.
  final int added;

  int calls = 0;

  @override
  Future<RestoreResult> restoreAll() async {
    calls++;
    return RestoreResult()..runs = added;
  }
}
