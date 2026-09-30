import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/coaching/data/supabase_coach_memory.dart';
import 'package:mgk_lift/src/features/coaching/presentation/coach_memory_screen.dart';
import 'package:mgk_lift/src/features/settings/domain/unit_preferences.dart';
import 'package:mgk_lift/src/features/settings/presentation/credits_screen.dart';
import 'package:mgk_lift/src/features/settings/presentation/settings_screen.dart';
import 'package:mgk_lift/src/features/sync/domain/sync_status.dart';
import 'package:mgk_lift/src/features/sync/presentation/backup_scheduler.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// Pumps on a viewport tall enough to hold the whole screen.
///
/// The default 800x600 is shorter than a phone, so rows near the bottom are
/// off-screen and `tap()` misses them - it warns rather than failing, and the
/// assertion afterwards is what breaks.
Future<void> pumpTall(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrap(child));
  await tester.pumpAndSettle();
}

void main() {
  backupSmoke();
  coachMemoryRow();
  group('units', () {
    testWidgets('distance and weight are two separate controls', (
      WidgetTester tester,
    ) async {
      // The whole point of the units work: miles with kilograms is ordinary,
      // and one metric/imperial switch made it unreachable.
      await tester.pumpWidget(
        wrap(
          SettingsScreen(
            initial: const UnitPreferences(),
            store: InMemoryUnitPreferences(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Two rows, each showing what it is set to (19).
      expect(find.widgetWithText(SettingsRow, 'Weight'), findsOneWidget);
      expect(find.widgetWithText(SettingsRow, 'Distance'), findsOneWidget);
      expect(find.text('Kilograms'), findsOneWidget);
      expect(find.text('Kilometres'), findsOneWidget);

      // Each opens its own choice, with its explanation where it is made.
      await tester.tap(find.text('Weight'));
      await tester.pumpAndSettle();
      expect(find.text('Pounds'), findsOneWidget);
      expect(find.textContaining('A separate choice from distance'), findsOne);
    });

    testWidgets('choosing miles leaves the weight unit alone', (
      WidgetTester tester,
    ) async {
      final store = InMemoryUnitPreferences();
      await tester.pumpWidget(
        wrap(SettingsScreen(initial: const UnitPreferences(), store: store)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Distance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Miles'));
      await tester.pumpAndSettle();

      final saved = await store.load();
      expect(saved.distance, UnitSystem.imperial);
      expect(saved.mass, MassUnit.kilograms);
    });

    testWidgets('the change is reported up before it is persisted', (
      WidgetTester tester,
    ) async {
      // Track logs and Profile reports in these units, so the shell has to hear
      // about it without waiting for a round trip or for this screen to close.
      UnitPreferences? reported;
      await tester.pumpWidget(
        wrap(
          SettingsScreen(
            initial: const UnitPreferences(),
            store: InMemoryUnitPreferences(),
            onChanged: (p) => reported = p,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Weight'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pounds'));
      await tester.pump();

      expect(reported?.mass, MassUnit.pounds);
      // And the row says so at once.
      await tester.pumpAndSettle();
      expect(find.text('Pounds'), findsOneWidget);
    });

    testWidgets('with no store the controls are inert, not absent', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const SettingsScreen(initial: UnitPreferences())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kilograms'), findsOneWidget);
      await tester.tap(find.text('Weight'));
      await tester.pumpAndSettle();

      // Nothing opened, and the screen says why rather than silently
      // swallowing the tap.
      expect(find.text('Pounds'), findsNothing);
      expect(find.text('Sign in to change these.'), findsOneWidget);
    });
  });

  group('the account (19)', () {
    testWidgets('comes first, and opens its own screen', (
      WidgetTester tester,
    ) async {
      var signedOut = 0;
      var restored = 0;
      await pumpTall(
        tester,
        SettingsScreen(
          initial: const UnitPreferences(),
          store: InMemoryUnitPreferences(),
          isSignedIn: true,
          email: 'lifter@example.com',
          planLabel: 'Subscribed',
          onSignOut: () => signedOut++,
          onRestorePurchases: () async => restored++,
        ),
      );

      // The profile card: initial, address, plan — above everything else.
      expect(find.text('L'), findsOneWidget);
      expect(find.text('Subscribed'), findsOneWidget);
      final card = tester.getTopLeft(find.text('lifter@example.com')).dy;
      expect(card, lessThan(tester.getTopLeft(find.text('Weight')).dy));
      // Sign out and Restore are not rows on the index any more.
      expect(find.text('Sign out'), findsNothing);

      await tester.tap(find.text('lifter@example.com'));
      await tester.pumpAndSettle();
      expect(find.text('Account'), findsOneWidget);

      await tester.tap(find.text('Restore purchases'));
      await tester.pumpAndSettle();
      expect(restored, 1);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(signedOut, 1);
    });

    testWidgets('signed out, the card offers to sign in and opens nothing', (
      WidgetTester tester,
    ) async {
      var signIns = 0;
      await pumpTall(
        tester,
        SettingsScreen(
          initial: const UnitPreferences(),
          store: InMemoryUnitPreferences(),
          onSignIn: () => signIns++,
        ),
      );
      await tester.tap(find.text('Not signed in'));
      await tester.pumpAndSettle();
      expect(find.text('Account'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Sign in'));
      expect(signIns, 1);
    });

    testWidgets('the account and the units fit a 375pt phone unscrolled', (
      WidgetTester tester,
    ) async {
      tester.view
        ..physicalSize = const Size(375 * 3, 667 * 3)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        wrap(
          SettingsScreen(
            initial: const UnitPreferences(),
            store: InMemoryUnitPreferences(),
            isSignedIn: true,
            email: 'lifter@example.com',
            planLabel: 'Free',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getBottomLeft(find.text('Distance')).dy, lessThan(667));
    });
  });

  group('credits', () {
    // These assertions exist because the original app deleted its Everkinetic
    // credit in a single commit and then claimed sole ownership of the art.
    // Attribution is a licence condition, so it is tested like one.

    testWidgets('are reachable from settings', (WidgetTester tester) async {
      await pumpTall(tester, const SettingsScreen(initial: UnitPreferences()));

      await tester.tap(find.text('Credits'));
      await tester.pumpAndSettle();

      expect(find.byType(CreditsScreen), findsOneWidget);
    });

    testWidgets('name the creator, the licence and the original', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap(const CreditsScreen()));
      await tester.pumpAndSettle();

      // CC BY-SA 4.0 s3(a)(1): creator, copyright notice, licence notice,
      // disclaimer, and a URI to the licensed material.
      expect(find.textContaining('Greg Priday'), findsOneWidget);
      expect(find.textContaining('© Everkinetic'), findsOneWidget);
      expect(find.textContaining('CC BY-SA 4.0'), findsOneWidget);
      expect(find.textContaining('without warranties'), findsOneWidget);
      expect(find.text('github.com/everkinetic/data'), findsOneWidget);
      expect(
        find.text('creativecommons.org/licenses/by-sa/4.0/'),
        findsOneWidget,
      );
    });

    testWidgets('say the images were modified', (WidgetTester tester) async {
      // s3(a)(1)(B) — indicating modification is its own condition, separate
      // from naming the creator.
      await tester.pumpWidget(wrap(const CreditsScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('redrawn'), findsOneWidget);
    });

    testWidgets('pass the licence on rather than claiming the art', (
      WidgetTester tester,
    ) async {
      // ShareAlike. This is the line that contradicts "all rights reserved",
      // and it is the reason the credit alone would not have been enough.
      await tester.pumpWidget(wrap(const CreditsScreen()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('adaptations are likewise offered under CC BY-SA'),
        findsOneWidget,
      );
    });
  });
}

void coachMemoryRow() {
  testWidgets('the coach row says the coach remembers, and opens it', (
    WidgetTester tester,
  ) async {
    // The subtitle is doing real work: a lifter who never opens the screen
    // should still learn from this row that a memory exists at all.
    await pumpTall(
      tester,
      SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        isSignedIn: true,
        coachMemory: FakeCoachMemory(),
      ),
    );

    expect(find.text('What your coach remembers'), findsOneWidget);

    await tester.tap(find.text('What your coach remembers'));
    await tester.pumpAndSettle();
    expect(find.byType(CoachMemoryScreen), findsOneWidget);
  });

  testWidgets('signed out, there is no memory row to open', (
    WidgetTester tester,
  ) async {
    // Nothing is stored without an account, so a row here would open a screen
    // that can only say so.
    await pumpTall(
      tester,
      SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        coachMemory: FakeCoachMemory(),
      ),
    );
    expect(find.text('What your coach remembers'), findsNothing);
  });

  testWidgets('a build with no server shows no memory row', (
    WidgetTester tester,
  ) async {
    await pumpTall(
      tester,
      SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        isSignedIn: true,
      ),
    );
    expect(find.text('What your coach remembers'), findsNothing);
  });
}

// Added after the preview crashed on device with exactly these parameters.
void backupSmoke() {
  testWidgets('settings builds with a signed-out backup section', (
    WidgetTester tester,
  ) async {
    await pumpTall(
      tester,
      SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        backup: ValueNotifier<BackupStatus>(
          const BackupStatus(
            pending: SyncPending(workouts: 9, lastSyncedAt: null),
          ),
        ),
        onSignIn: () {},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('9 sessions are on this phone only.'), findsOneWidget);
  });

  testWidgets('the account card follows backup while the screen is open', (
    WidgetTester tester,
  ) async {
    // A run started from here — or by a checkpoint behind it — is reported
    // as it happens, not the next time the screen is opened.
    final backup = ValueNotifier<BackupStatus>(
      const BackupStatus(pending: SyncPending(workouts: 2, lastSyncedAt: null)),
    );
    await pumpTall(
      tester,
      SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        isSignedIn: true,
        backup: backup,
        onSyncNow: () {},
      ),
    );
    expect(find.text('2 sessions waiting to upload.'), findsOneWidget);

    backup.value = BackupStatus(
      pending: SyncPending(workouts: 0, lastSyncedAt: DateTime.now()),
    );
    await tester.pump();
    expect(find.textContaining('Everything is saved'), findsOneWidget);
  });
}
