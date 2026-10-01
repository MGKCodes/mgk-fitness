import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_run/src/features/history/domain/run_writer.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **The prompt the account removal left owing.**
///
/// Taking the sign-in wall down meant a runner could record for months with
/// everything on one phone and never once be told. The only consent question in
/// the app was asked at launch, before the restore — which is the right moment
/// for somebody returning to an account, and no moment at all for somebody who
/// has never had one. Asked of *them* it would land ninety seconds after
/// install, about data that does not exist yet, from an app they have not
/// watched do anything (ADR-0012), and a yes could not have been honoured
/// anyway: the mirror needs a user to attribute rows to.
///
/// So they are asked here instead, after the second recorded run, when the
/// phone holds a log they would mind losing. Saying yes raises sign-up, because
/// that is the mechanism the answer needs, not a further question.
void main() {
  RunSummary run(int daysAgo) => RunSummary(
    id: 'run-$daysAgo',
    startedAt: DateTime.now().subtract(Duration(days: daysAgo)),
    duration: const Duration(minutes: 30),
    distanceMeters: 5000,
    avgPaceSecondsPerKm: 360,
  );

  /// The shell as a runner with no account meets it, holding [runs] runs.
  ///
  /// No coach injected on purpose: the coach mark plays its reveal on a repeating
  /// timer and `pumpAndSettle` never comes back on a shell that has one. Nothing
  /// here is about the coach.
  Future<void> pumpShell(
    WidgetTester tester, {
    required int runs,
    required BackupConsentStore consent,
    FakeAuthRepository? auth,
    DataRestore? restore,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: auth ?? FakeAuthRepository(),
          consentStore: consent,
          restore: restore,
          historySource: () async => <RunSummary>[
            for (var i = 1; i <= runs; i++) run(i),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('one run is a trial, and is left alone', (tester) async {
    // Somebody walking to the end of the road to see whether the app works.
    // Interrupting that with a consent dialog and a sign-up is how a tracker
    // turns into a thing that wants something.
    final consent = InMemoryBackupConsent();
    await pumpShell(tester, runs: 1, consent: consent);

    expect(find.text('Keep these safe?'), findsNothing);
    expect(await consent.read(), BackupConsent.unknown);
  });

  testWidgets('by the second there is a log worth keeping, and it says so', (
    tester,
  ) async {
    final consent = InMemoryBackupConsent();
    await pumpShell(tester, runs: 2, consent: consent);

    expect(find.text('Keep these safe?'), findsOneWidget);
    // Their own number, not "some runs" — the whole reason to ask now rather
    // than at launch is that there is something real on the phone.
    expect(find.textContaining("You've recorded 2 runs"), findsOneWidget);
    // And what it covers, in the same words the switch in Settings uses.
    expect(
      find.textContaining('what the coach remembers about you'),
      findsOneWidget,
    );
    // Said before it is asked for, rather than sprung after the tap.
    expect(find.textContaining('You will need an account'), findsOneWidget);
  });

  testWidgets('declining is a decision, and it is not put again', (
    tester,
  ) async {
    // "Not now" is deliberately not on offer: this is the only time it is
    // asked, so an answer implying otherwise would be a lie. Recording the
    // decline is what stops it coming back — and the switch in Settings is
    // where it lives from then on.
    final consent = InMemoryBackupConsent();
    await pumpShell(tester, runs: 2, consent: consent);

    await tester.tap(find.text('Keep them on this phone only'));
    await tester.pumpAndSettle();

    expect(await consent.read(), BackupConsent.declined);
    expect(consent.read(), completion(isNot(BackupConsent.unknown)));
  });

  testWidgets('and an answered question is never raised a second time', (
    tester,
  ) async {
    final consent = InMemoryBackupConsent(BackupConsent.declined);
    await pumpShell(tester, runs: 5, consent: consent);

    expect(find.text('Keep these safe?'), findsNothing);
  });

  group('saying yes', () {
    testWidgets('raises the account the answer needs', (tester) async {
      final consent = InMemoryBackupConsent();
      await pumpShell(tester, runs: 2, consent: consent);

      await tester.tap(find.text('Back them up'));
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsOneWidget);
    });

    testWidgets('and the consent lands once it arrives', (tester) async {
      final consent = InMemoryBackupConsent();
      await pumpShell(tester, runs: 2, consent: consent);

      await tester.tap(find.text('Back them up'));
      await tester.pumpAndSettle();

      // The form is the second step since build 27.
      await tester.tap(find.text('Continue with email'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'sam@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'hunter2222',
      );
      await tester.tap(find.widgetWithText(PrimaryButton, 'Sign up'));
      // Fixed pumps: a submitting `PrimaryButton` draws an indeterminate
      // spinner, and settle never returns on a screen showing one.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(await consent.read(), BackupConsent.granted);
    });

    testWidgets('but an abandoned sign-up writes nothing at all', (
      tester,
    ) async {
      // They did not decline, they were interrupted. Recording a grant here
      // would leave the switch reading On over an account that does not exist;
      // recording a decline would put words in their mouth. The question stays
      // open and is asked again next time.
      final consent = InMemoryBackupConsent();
      await pumpShell(tester, runs: 2, consent: consent);

      await tester.tap(find.text('Back them up'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsNothing);
      expect(await consent.read(), BackupConsent.unknown);
    });

    testWidgets('and is not asked again in the same session', (tester) async {
      // **E1 on the build 13 sheet: "the backup prompt appears repeatedly".**
      //
      // Backing out used to clear the in-session flag, so the next reload
      // raised the dialog afresh -- and `_refreshHome` runs after a finished
      // run, after an edit, after a unit change. The question staying open for
      // next launch is ADR-0012's intent and is asserted above, on the store;
      // asking again thirty seconds later is badgering.
      //
      // The restore is what makes the shell reload a second time within one
      // launch, which is the shape the field test was in.
      final consent = InMemoryBackupConsent();
      await pumpShell(
        tester,
        runs: 2,
        consent: consent,
        restore: _RestoredSomething(),
      );

      await tester.tap(find.text('Back them up'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Keep these safe?'), findsNothing);
      expect(await consent.read(), BackupConsent.unknown);
    });
  });

  testWidgets('two reloads in one launch raise one dialog, not two', (
    tester,
  ) async {
    // The concurrent half. The in-session flag is set *after* `store.read()`,
    // so two reloads that overlap both passed it and both opened a dialog --
    // and the launch path reloads twice whenever a restore actually brought
    // something back. Guarded by a single-flight future rather than a second
    // boolean, because the second caller should join the first rather than be
    // turned away.
    final consent = InMemoryBackupConsent();
    await pumpShell(
      tester,
      runs: 2,
      consent: consent,
      restore: _RestoredSomething(),
    );

    expect(find.text('Keep these safe?'), findsOneWidget);
  });

  testWidgets('a runner who has an account is asked the other way, at launch', (
    tester,
  ) async {
    // The two doors are not interchangeable. For somebody signed in the answer
    // decides whether there is a restore at all, so it has to be asked before
    // one — no number of runs comes into it.
    final consent = InMemoryBackupConsent();
    await pumpShell(
      tester,
      runs: 0,
      consent: consent,
      auth: FakeAuthRepository(signedIn: true, email: 'sam@example.com'),
    );

    expect(find.text('Keep a copy of your training?'), findsOneWidget);
    expect(find.text('Keep these safe?'), findsNothing);
  });
}

/// A restore that brought something back, so the shell reloads a second time
/// after it — the only way to get two reloads out of one launch.
class _RestoredSomething implements DataRestore {
  @override
  Future<RestoreResult> restoreAll() async => RestoreResult()..runs = 3;
}
