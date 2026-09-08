import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/profile/domain/backup_state.dart';
import 'package:mgk_run/src/features/profile/presentation/backup_card.dart';
import 'package:mgk_run/src/features/settings/domain/backup_health.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **"Profile needs a visible sync state"**, off the build 13 field test.
///
/// The screen had none: its own class doc said everything on it was derived
/// from data already on the device, with *"nothing to keep in sync"*, which
/// stopped being the whole truth the moment backup existed.
///
/// What is asserted here is mostly what it does **not** say. `BackupHealth`
/// records the last *attempt* and its own doc is explicit that it cannot say
/// whether everything on the phone is mirrored — so "everything is backed up"
/// is a guarantee this screen would be inventing out of a timestamp.
void main() {
  Future<void> pump(WidgetTester tester, ProfileBackupState state) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(body: BackupCard(state: state)),
        ),
      );

  ProfileBackupState stateWith({
    bool syncing = false,
    int justSent = 0,
    DateTime? succeeded,
    DateTime? failed,
  }) => ProfileBackupState(
    signedIn: true,
    consented: true,
    syncing: syncing,
    justSent: justSent,
    health: BackupHealth(lastSucceededAt: succeeded, lastFailedAt: failed),
  );

  testWidgets('in flight, it says so and shows a spinner', (tester) async {
    await pump(tester, stateWith(syncing: true));

    expect(find.text('Backing up…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a push that just happened reports what it sent', (tester) async {
    // The only line here that reports an event rather than a condition, and it
    // comes from a count `HomeShell` used to throw away.
    await pump(tester, stateWith(justSent: 3, succeeded: DateTime.now()));

    expect(find.text('Backed up. 3 runs sent just now.'), findsOneWidget);
  });

  testWidgets('and one run is not "1 runs"', (tester) async {
    await pump(tester, stateWith(justSent: 1, succeeded: DateTime.now()));
    expect(find.text('Backed up. 1 run sent just now.'), findsOneWidget);
  });

  testWidgets('a failure says where the training still is', (tester) async {
    // Not an alarm. The data is on the phone, which is where it has always
    // primarily lived (ADR-0023) — the backup failing is a fact to state, not
    // a loss to apologise for.
    final now = DateTime.now();
    await pump(
      tester,
      stateWith(succeeded: now.subtract(const Duration(days: 2)), failed: now),
    );

    expect(
      find.textContaining('Your training is safe on this phone'),
      findsOneWidget,
    );
  });

  testWidgets('a quiet phone reports the last attempt, not a guarantee', (
    tester,
  ) async {
    await pump(
      tester,
      stateWith(succeeded: DateTime.now().subtract(const Duration(hours: 3))),
    );

    expect(find.text('Last backed up 3h ago.'), findsOneWidget);
    expect(
      find.textContaining('Everything'),
      findsNothing,
      reason: 'the record is of one attempt and cannot vouch for the rest',
    );
  });

  testWidgets('and a phone that has never pushed says that instead', (
    tester,
  ) async {
    await pump(tester, stateWith());
    expect(find.text('Nothing has been backed up yet.'), findsOneWidget);
  });

  test('there is nothing to show without an account or consent', () {
    // The card is absent rather than empty. An empty status line is furniture
    // on a page whose own rule is that a zero is a claim.
    const health = BackupHealth();
    expect(
      const ProfileBackupState(
        signedIn: false,
        consented: true,
        syncing: false,
        health: health,
      ).isWorthShowing,
      isFalse,
    );
    expect(
      const ProfileBackupState(
        signedIn: true,
        consented: false,
        syncing: false,
        health: health,
      ).isWorthShowing,
      isFalse,
    );
  });
}
