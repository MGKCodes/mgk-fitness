import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/planning/domain/moved_day.dart';
import 'package:mgk_lift/src/features/planning/domain/standing_plan.dart';
import 'package:mgk_lift/src/features/planning/presentation/standing_plan_surface.dart';

MovementSlot slot(String id, String movement) =>
    MovementSlot(id: id, role: id, movement: movement, sets: 3, reps: 8);

/// Push on Monday, Pull on Wednesday, Legs on Friday.
StandingPlan ppl() => StandingPlan(
  id: 'p',
  name: 'Push / Pull / Legs',
  dayOrder: const <String>['Push', 'Pull', 'Legs'],
  weekdays: const <int>[1, 3, 5],
  slots: <String, List<MovementSlot>>{
    'Push': <MovementSlot>[slot('a', 'Barbell Bench Press')],
    'Pull': <MovementSlot>[slot('b', 'Barbell Row')],
    'Legs': <MovementSlot>[slot('c', 'Barbell Squat')],
  },
);

/// A Monday.
final DateTime monday = DateTime(2026, 8, 17, 9);

Future<void> pump(
  WidgetTester tester, {
  VoidCallback? onGoToTrack,
  ValueChanged<String>? onDoToday,
  String? movedDay,
}) async {
  tester.view
    ..physicalSize = const Size(1179, 3600)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StandingPlanSurface(
          plan: ppl(),
          today: monday,
          onGoToTrack: onGoToTrack,
          onDoToday: onDoToday,
          movedDay: movedDay,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('nothing starts here (R8)', (tester) async {
    // Today's session starts from Track, like every session. Two front doors
    // to the same session could disagree.
    await pump(tester, onGoToTrack: () {}, onDoToday: (_) {});
    expect(find.textContaining('Start'), findsNothing);
  });

  testWidgets("today says what today is, and goes to Track", (tester) async {
    var went = 0;
    await pump(tester, onGoToTrack: () => went++, onDoToday: (_) {});

    expect(find.text('Push is on Track, ready to start.'), findsOneWidget);
    await tester.tap(find.text('Go to Track'));
    await tester.pumpAndSettle();
    expect(went, 1);
  });

  testWidgets('another day offers Do it today, for that day', (tester) async {
    final chosen = <String>[];
    await pump(tester, onGoToTrack: () {}, onDoToday: chosen.add);

    // Wednesday, in the week strip.
    await tester.tap(find.text('W'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Do it today'));
    await tester.pumpAndSettle();

    expect(chosen, <String>['Pull']);
  });

  testWidgets('a day already brought forward says so, on both days', (
    tester,
  ) async {
    await pump(tester, onGoToTrack: () {}, onDoToday: (_) {}, movedDay: 'Pull');
    expect(
      find.text('Pull is on Track today, brought forward.'),
      findsOneWidget,
    );

    await tester.tap(find.text('W'));
    await tester.pumpAndSettle();
    expect(find.text('On Track today.'), findsOneWidget);
    expect(find.text('Do it today'), findsNothing);
  });

  group('a day brought forward (O4)', () {
    test('lasts the day it was chosen for, and no longer', () async {
      final store = InMemoryMovedDay();
      await store.write('Pull', monday);

      expect(await store.read(monday.add(const Duration(hours: 10))), 'Pull');
      expect(await store.read(monday.add(const Duration(days: 1))), isNull);
    });

    test('goes once cleared', () async {
      final store = InMemoryMovedDay();
      await store.write('Pull', monday);
      await store.clear();
      expect(await store.read(monday), isNull);
    });
  });
}
