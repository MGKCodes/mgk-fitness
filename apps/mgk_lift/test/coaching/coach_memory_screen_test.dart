import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/coaching/data/supabase_coach_memory.dart';
import 'package:mgk_lift/src/features/coaching/domain/coach_memory.dart';
import 'package:mgk_lift/src/features/coaching/presentation/coach_memory_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

final CoachMemory _remembered = CoachMemory(
  summary: 'Trains four days. Left shoulder complains on overhead work.',
  updatedAt: DateTime.now().subtract(const Duration(days: 2)),
);

void main() {
  testWidgets('the memory is shown to the person it is about', (
    WidgetTester tester,
  ) async {
    // The whole point of the screen. A stored paragraph about somebody's body
    // that they cannot read is one they cannot correct.
    await tester.pumpWidget(
      wrap(CoachMemoryScreen(store: FakeCoachMemory(memory: _remembered))),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Left shoulder complains'), findsOneWidget);
    expect(find.textContaining('2 days ago'), findsOneWidget);
  });

  testWidgets('it says the memory cannot be edited, and why', (
    WidgetTester tester,
  ) async {
    // Offering no edit control without saying so reads as an oversight. The
    // reason matters: an edit would be rewritten within a few conversations.
    await tester.pumpWidget(
      wrap(CoachMemoryScreen(store: FakeCoachMemory(memory: _remembered))),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('cannot edit this'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('an empty memory is a real state, not an error', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(wrap(CoachMemoryScreen(store: FakeCoachMemory())));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing yet'), findsOneWidget);
    // Nothing to forget, so nothing offering to.
    expect(find.text('Forget everything'), findsNothing);
  });

  group('forgetting', () {
    testWidgets('is confirmed first, and says what it does not touch', (
      WidgetTester tester,
    ) async {
      // Not undoable, and not the same as deleting the account. Both have to
      // be said before it happens.
      final store = FakeCoachMemory(memory: _remembered);
      await tester.pumpWidget(wrap(CoachMemoryScreen(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forget everything'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('training log is not touched'),
        findsOneWidget,
      );
      expect(find.textContaining('account stays as it is'), findsOneWidget);
      expect(store.cleared, isFalse);
    });

    testWidgets('backing out changes nothing', (WidgetTester tester) async {
      final store = FakeCoachMemory(memory: _remembered);
      await tester.pumpWidget(wrap(CoachMemoryScreen(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forget everything'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();

      expect(store.cleared, isFalse);
      expect(find.textContaining('Left shoulder complains'), findsOneWidget);
    });

    testWidgets('confirming erases it and the screen agrees', (
      WidgetTester tester,
    ) async {
      final store = FakeCoachMemory(memory: _remembered);
      await tester.pumpWidget(wrap(CoachMemoryScreen(store: store)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Forget everything'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forget'));
      await tester.pumpAndSettle();

      expect(store.cleared, isTrue);
      // The screen must not keep showing what was just erased.
      expect(find.textContaining('Left shoulder complains'), findsNothing);
      expect(find.textContaining('Nothing yet'), findsOneWidget);
    });
  });

  testWidgets('a failure is reported with a way out', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        CoachMemoryScreen(
          store: FakeCoachMemory(failWith: CoachMemoryFailure.unavailable),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not reach your coach'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
