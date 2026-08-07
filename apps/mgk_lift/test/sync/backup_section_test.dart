import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/sync/domain/sync_status.dart';
import 'package:mgk_lift/src/features/sync/presentation/backup_section.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('signed out', () {
    testWidgets('says the training exists in one place only', (
      WidgetTester tester,
    ) async {
      // Discovering this after losing a phone is the worst possible time, so
      // the screen says it while the phone still exists.
      await tester.pumpWidget(
        wrap(
          const BackupSection(
            pending: SyncPending(workouts: 0, lastSyncedAt: null),
            isSignedIn: false,
          ),
        ),
      );

      expect(find.text('This device only'), findsOneWidget);
      expect(find.textContaining('only on this phone'), findsOneWidget);
      expect(find.text('Sign in to back up'), findsOneWidget);
    });

    testWidgets('counts what would be lost, rather than just warning', (
      WidgetTester tester,
    ) async {
      // "Sign in to back up" is easy to ignore. "9 sessions exist nowhere
      // else" is not.
      await tester.pumpWidget(
        wrap(
          const BackupSection(
            pending: SyncPending(workouts: 9, lastSyncedAt: null),
            isSignedIn: false,
          ),
        ),
      );

      expect(
        find.textContaining('9 sessions exist nowhere else'),
        findsOneWidget,
      );
    });

    testWidgets('gets the singular right', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const BackupSection(
            pending: SyncPending(workouts: 1, lastSyncedAt: null),
            isSignedIn: false,
          ),
        ),
      );
      expect(
        find.textContaining('1 session exists nowhere else'),
        findsOneWidget,
      );
    });
  });

  group('signed in', () {
    testWidgets('reports what is waiting', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          const BackupSection(
            pending: SyncPending(workouts: 3, lastSyncedAt: null),
            isSignedIn: true,
          ),
        ),
      );

      expect(find.text('Backup'), findsOneWidget);
      expect(find.text('3 sessions waiting to upload.'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
    });

    testWidgets('offers to check when there is nothing to send', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BackupSection(
            pending: SyncPending(
              workouts: 0,
              lastSyncedAt: DateTime.now().subtract(
                const Duration(minutes: 3),
              ),
            ),
            isSignedIn: true,
          ),
        ),
      );

      expect(find.textContaining('Everything is backed up'), findsOneWidget);
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
          BackupSection(
            pending: const SyncPending(workouts: 0, lastSyncedAt: null),
            isSignedIn: true,
            lastReport: SyncReport(
              outcome: SyncOutcome.synced,
              pushed: 3,
              pulled: 1,
              at: DateTime.now(),
            ),
          ),
        ),
      );

      expect(find.text('Backed up. 3 up, 1 down just now.'), findsOneWidget);
    });

    testWidgets('a failure explains itself without the server error', (
      WidgetTester tester,
    ) async {
      // A PostgREST code is not something to put in front of somebody who was
      // trying to back up their training, and it is not theirs to fix.
      await tester.pumpWidget(
        wrap(
          const BackupSection(
            pending: SyncPending(workouts: 2, lastSyncedAt: null),
            isSignedIn: true,
            lastReport: SyncReport.unavailable('PGRST002: schema cache'),
          ),
        ),
      );

      expect(find.textContaining('Could not reach the server'), findsOneWidget);
      expect(find.textContaining('safe on this device'), findsOneWidget);
      expect(find.textContaining('PGRST002'), findsNothing);
    });

    testWidgets('syncing blocks a second tap', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          BackupSection(
            pending: const SyncPending(workouts: 1, lastSyncedAt: null),
            isSignedIn: true,
            isSyncing: true,
            onSyncNow: () {},
          ),
        ),
      );

      final button = tester.widget<OutlinedButton>(
        find.byType(OutlinedButton),
      );
      expect(button.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
