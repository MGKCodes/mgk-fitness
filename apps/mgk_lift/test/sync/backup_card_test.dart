import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/sync/domain/sync_status.dart';
import 'package:mgk_lift/src/features/sync/presentation/backup_card.dart';
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

const refused = RejectedWorkout(
  id: 'w',
  name: 'Push',
  isTemplate: false,
  detail: '22003: numeric field overflow',
);

void main() {
  group('signed out, the note on the profile card', () {
    test('says the training exists in one place only', () {
      // The one fact worth stating unprompted, because discovering it after
      // losing a phone is the worst possible time.
      final line = phoneOnlyLine(status().pending);
      expect(line, 'Your training is on this phone only.');

      // Reports, does not sell. An account is a thing people already
      // understand, so the note must not explain that a cloud account is
      // readable when you sign in, nor argue for creating one.
      for (final pitch in <String>[
        'keeps it with you',
        'new phone',
        'follows you',
        'back up',
        'backed up',
      ]) {
        expect(
          line.contains(pitch),
          isFalse,
          reason: 'the note is arguing for an account: "$pitch"',
        );
      }
    });

    test('counts what would be lost, rather than just warning', () {
      // The number makes the state concrete where there is one.
      expect(
        phoneOnlyLine(status(sessions: 9).pending),
        '9 sessions are on this phone only.',
      );
    });

    test('counts the library too, now that it can go up', () {
      expect(
        phoneOnlyLine(status(sessions: 9, saved: 3).pending),
        '9 sessions and 3 saved workouts are on this phone only.',
      );
    });

    test('gets the singular right', () {
      expect(
        phoneOnlyLine(status(sessions: 1).pending),
        '1 session is on this phone only.',
      );
    });
  });

  group('the card on the account screen', () {
    testWidgets('reports what is waiting', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(BackupCard(status: status(sessions: 3))));

      expect(find.text('3 sessions waiting to upload.'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
    });

    testWidgets('offers to check when there is nothing to send', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BackupCard(
            status: status(
              last: DateTime.now().subtract(const Duration(minutes: 3)),
            ),
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
          BackupCard(
            status: status(
              report: SyncReport(
                outcome: SyncOutcome.synced,
                pushed: 3,
                pulled: 1,
                at: DateTime.now(),
              ),
            ),
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
          BackupCard(
            status: status(
              sessions: 2,
              state: BackupState.failed,
              report: const SyncReport.unavailable('PGRST002: schema cache'),
            ),
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
          BackupCard(status: status(sessions: 1, state: BackupState.offline)),
        ),
      );
      expect(find.textContaining('No connection'), findsOneWidget);
      expect(find.textContaining("when you're back online"), findsOneWidget);
    });

    testWidgets('a lapsed sign-in asks for one', (WidgetTester tester) async {
      var asked = 0;
      await tester.pumpWidget(
        wrap(
          BackupCard(
            status: status(sessions: 1, state: BackupState.expired),
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
          BackupCard(
            status: status(rejected: const <RejectedWorkout>[refused]),
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
          BackupCard(
            status: status(sessions: 1, state: BackupState.running),
            onSyncNow: () {},
          ),
        ),
      );

      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('the row on the settings index', () {
    // One word where the card has a sentence, so the index can be read at a
    // glance. Only what the lifter alone can put right is coloured.
    test('says where backup stands', () {
      expect(backupRowValue(status()), ('Nothing saved yet', false));
      expect(backupRowValue(status(last: DateTime(2026, 10, 1))), (
        'Up to date',
        false,
      ));
      expect(backupRowValue(status(sessions: 2, saved: 1)), (
        '3 waiting',
        false,
      ));
      expect(backupRowValue(status(sessions: 1, state: BackupState.running)), (
        'Backing up',
        false,
      ));
      expect(backupRowValue(status(sessions: 1, state: BackupState.offline)), (
        'Offline',
        false,
      ));
      expect(backupRowValue(status(sessions: 1, state: BackupState.failed)), (
        'Failed, retrying',
        false,
      ));
    });

    test('and asks for the lifter only when it needs them', () {
      expect(backupRowValue(status(sessions: 1, state: BackupState.expired)), (
        'Sign in again',
        true,
      ));
      expect(
        backupRowValue(status(rejected: const <RejectedWorkout>[refused])),
        ('1 needs attention', true),
      );
      expect(
        backupRowValue(
          status(rejected: const <RejectedWorkout>[refused, refused]),
        ),
        ('2 need attention', true),
      );
    });
  });
}
