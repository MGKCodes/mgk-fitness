import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/sync/domain/sync_status.dart';
import 'package:mgk_lift/src/features/sync/presentation/account_section.dart';
import 'package:mgk_lift/src/features/sync/presentation/backup_scheduler.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

BackupStatus status({
  int sessions = 0,
  int saved = 0,
  DateTime? last,
  BackupState state = BackupState.idle,
  SyncReport? report,
  List<RejectedWorkout> rejected = const <RejectedWorkout>[],
}) => BackupStatus(
  state: state,
  lastReport: report,
  pending: SyncPending(
    workouts: sessions,
    savedWorkouts: saved,
    lastSyncedAt: last,
    rejected: rejected,
  ),
);

void main() {
  group('signed out', () {
    testWidgets('says the training exists in one place only', (
      WidgetTester tester,
    ) async {
      // The one fact worth stating unprompted, because discovering it after
      // losing a phone is the worst possible time.
      await tester.pumpWidget(
        wrap(AccountSection(status: status(), isSignedIn: false)),
      );

      expect(find.text('Not signed in'), findsOneWidget);
      expect(find.text('Your training is on this phone only.'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);

      // Reports, does not sell. An account is a thing people already
      // understand, so the card must not explain that a cloud account is
      // readable when you sign in, nor argue for creating one.
      for (final pitch in <String>[
        'keeps it with you',
        'new phone',
        'follows you',
        'back up',
        'backed up',
      ]) {
        expect(
          find.textContaining(pitch),
          findsNothing,
          reason: 'the card is arguing for an account: "$pitch"',
        );
      }
    });

    testWidgets('counts what would be lost, rather than just warning', (
      WidgetTester tester,
    ) async {
      // The number makes the state concrete where there is one.
      await tester.pumpWidget(
        wrap(AccountSection(status: status(sessions: 9), isSignedIn: false)),
      );

      expect(find.text('9 sessions are on this phone only.'), findsOneWidget);
    });

    testWidgets('counts the library too, now that it can go up', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          AccountSection(
            status: status(sessions: 9, saved: 3),
            isSignedIn: false,
          ),
        ),
      );

      expect(
        find.text('9 sessions and 3 saved workouts are on this phone only.'),
        findsOneWidget,
      );
    });

    testWidgets('gets the singular right', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(AccountSection(status: status(sessions: 1), isSignedIn: false)),
      );
      expect(
        find.textContaining('1 session is on this phone only'),
        findsOneWidget,
      );
    });
  });

  group('signed in', () {
    testWidgets('reports what is waiting', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          AccountSection(
            status: status(sessions: 3),
            isSignedIn: true,
            email: 'lifter@example.com',
          ),
        ),
      );

      // The card is titled with the account it is talking about, so somebody
      // signed in as the wrong address finds out here rather than by
      // wondering where their training went.
      expect(find.text('lifter@example.com'), findsOneWidget);
      expect(find.text('3 sessions waiting to upload.'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
    });

    testWidgets('offers to check when there is nothing to send', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          AccountSection(
            status: status(
              last: DateTime.now().subtract(const Duration(minutes: 3)),
            ),
            isSignedIn: true,
          ),
        ),
      );

      expect(find.textContaining('Everything is saved'), findsOneWidget);
      expect(find.textContaining('3 min ago'), findsOneWidget);
      // "Sync now" either way: the run pushes and pulls regardless, so
      // "check for changes" understated what pressing it does.
      expect(find.text('Sync now'), findsOneWidget);
    });

    testWidgets('reports what the last run actually moved', (
      WidgetTester tester,
    ) async {
      // The one moment the feature visibly did something used to pass in
      // silence - `pushed` and `pulled` were computed and never shown.
      await tester.pumpWidget(
        wrap(
          AccountSection(
            status: status(
              report: SyncReport(
                outcome: SyncOutcome.synced,
                pushed: 3,
                pulled: 1,
                at: DateTime.now(),
              ),
            ),
            isSignedIn: true,
          ),
        ),
      );

      expect(find.text('Saved. 3 up, 1 down just now.'), findsOneWidget);
    });

    testWidgets('a failure explains itself without the server error', (
      WidgetTester tester,
    ) async {
      // A PostgREST code is not something to put in front of somebody, and it
      // is not theirs to fix.
      await tester.pumpWidget(
        wrap(
          AccountSection(
            status: status(
              sessions: 2,
              state: BackupState.failed,
              report: const SyncReport.unavailable('PGRST002: schema cache'),
            ),
            isSignedIn: true,
          ),
        ),
      );

      expect(find.textContaining('Backup failed'), findsOneWidget);
      expect(find.textContaining('safe on this phone'), findsOneWidget);
      expect(find.textContaining('PGRST002'), findsNothing);
    });

    testWidgets('no connection says so, and that it will go', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          AccountSection(
            status: status(sessions: 1, state: BackupState.offline),
            isSignedIn: true,
          ),
        ),
      );
      expect(find.textContaining('No connection'), findsOneWidget);
      expect(find.textContaining("when you're back online"), findsOneWidget);
    });

    testWidgets('a lapsed sign-in asks for one', (WidgetTester tester) async {
      var asked = 0;
      await tester.pumpWidget(
        wrap(
          AccountSection(
            status: status(sessions: 1, state: BackupState.expired),
            isSignedIn: true,
            onSignIn: () => asked++,
          ),
        ),
      );
      expect(find.text('Sign in again to keep backing up.'), findsOneWidget);
      await tester.tap(find.text('Sign in again'));
      expect(asked, 1);
    });

    testWidgets('each refusal is listed with its reason, never its code', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          AccountSection(
            status: status(
              rejected: const <RejectedWorkout>[
                RejectedWorkout(
                  id: 'w',
                  name: 'Push',
                  isTemplate: false,
                  detail: '22003: numeric field overflow',
                ),
              ],
            ),
            isSignedIn: true,
          ),
        ),
      );
      expect(
        find.text('"Push" couldn\'t be backed up: a value is out of range.'),
        findsOneWidget,
      );
      expect(find.textContaining('22003'), findsNothing);
    });

    testWidgets('syncing blocks a second tap', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          AccountSection(
            status: status(sessions: 1, state: BackupState.running),
            isSignedIn: true,
            onSyncNow: () {},
          ),
        ),
      );

      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
