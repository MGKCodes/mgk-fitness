import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The delete screen's pieces, shared by both apps since 4 October 2026, so
/// the two ask the same question in the same words.
void main() {
  Future<void> pumpChoice(
    WidgetTester tester, {
    required bool wide,
    required ValueChanged<bool> onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: DeletionChoice(
            wide: wide,
            onChanged: onChanged,
            otherApp: '$kPlatformName: Run',
            holds: 'Your sessions.',
          ),
        ),
      ),
    );
  }

  testWidgets('two choices, one chosen, and a tap says which', (tester) async {
    final picked = <bool>[];
    await pumpChoice(tester, wide: false, onChanged: picked.add);

    expect(find.text("Delete this app's data"), findsOneWidget);
    expect(find.text('Delete my whole $kPlatformName account'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(DeletionChoice.narrowKey),
        matching: find.byIcon(Icons.radio_button_checked),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(DeletionChoice.wideKey));
    await tester.tap(find.byKey(DeletionChoice.narrowKey));
    expect(picked, <bool>[true, false]);
  });

  testWidgets('the narrow one promises only what is always true', (
    tester,
  ) async {
    // The login goes too when the other app holds nothing, so the card does
    // not say it stays. The other app's data is never touched, so it says
    // that.
    await pumpChoice(tester, wide: false, onChanged: (_) {});

    expect(
      find.text(
        'Your sessions. Anything $kPlatformName: Run holds is left alone.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('account stays'), findsNothing);
  });

  group('what the server did', () {
    String outcome({
      bool wide = false,
      bool accountDeleted = false,
      bool kept = false,
    }) => deletionOutcome(
      removed: 'Gone.',
      wide: wide,
      accountDeleted: accountDeleted,
      keptForOtherApp: kept,
      otherApp: 'Other',
      supportEmail: 'help@example.com',
    );

    test('kept for the other app, as asked', () {
      expect(
        outcome(kept: true),
        'Gone. Your $kPlatformName account is still active because Other is '
        'using it, which is what you asked for.',
      );
    });

    test('this app only, and the login went anyway', () {
      expect(
        outcome(accountDeleted: true),
        contains('nothing else was using it'),
      );
    });

    test('everything, as asked', () {
      expect(
        outcome(wide: true, accountDeleted: true),
        'Gone. Everything Other held is gone as well, along with your login.',
      );
    });

    test('a login still there for no reason given could not be removed', () {
      final said = outcome();
      expect(said, contains('could not be removed'));
      expect(said, contains('help@example.com'));
    });
  });

  test('the login note names the other app either way', () {
    expect(
      deletionLoginNote(wide: false, otherApp: 'Other'),
      contains('shared with Other'),
    );
    expect(
      deletionLoginNote(wide: true, otherApp: 'Other'),
      contains('anything Other holds goes with it'),
    );
  });
}
