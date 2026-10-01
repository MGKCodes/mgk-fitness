import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/history/domain/run_draft.dart';
import 'package:mgk_run/src/features/history/domain/run_writer.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/home/presentation/home_today_tile.dart';
import 'package:mgk_run/src/features/home/presentation/home_week_tile.dart';
import 'package:mgk_ui/mgk_ui.dart';

class _Writer implements RunWriter {
  final List<RunDraft> added = <RunDraft>[];

  @override
  Future<String> add(RunDraft draft) async {
    added.add(draft);
    return 'run-${added.length}';
  }

  @override
  Future<void> edit(String runId, RunDraft draft) async {}

  @override
  Future<void> delete(String runId) async {}

  @override
  Future<RunDraft?> draftOf(String runId) async => null;

  @override
  Future<int> backfill() async => 0;
}

/// **Home could start a run and could not log one.** Every button on the
/// today card opened the GPS recorder, and a treadmill has no GPS: the only
/// way to log one was "Add a run" at the top of the log, two tabs from the
/// button a runner presses to go running.
///
/// It lives on the week tile, as a full-width row at its foot. For one build
/// it was a button under Start on the today card, alone on the left with
/// nothing beside it.
void main() {
  Future<_Writer?> pumpHome(WidgetTester tester, {bool editor = true}) async {
    final writer = editor ? _Writer() : null;
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'runner@example.com'),
          historySource: () async => const [],
          runEditor: writer,
        ),
      ),
    );
    // Pumped rather than settled, as the other shell tests are: the coach mark
    // plays a reveal that `pumpAndSettle` would wait out.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return writer;
  }

  testWidgets('it is a row on the week tile, not a button on the today card', (
    tester,
  ) async {
    await pumpHome(tester);
    final row = find.text('Add a treadmill run');

    expect(
      find.descendant(of: find.byType(HomeWeekTile), matching: row),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(HomeTodayTile), matching: row),
      findsNothing,
    );
    // The row runs the width of the tile: its plus sits at the far side.
    final tile = tester.getRect(find.byType(HomeWeekTile));
    expect(
      tester.getRect(find.byIcon(Icons.add)).right,
      greaterThan(tile.right - 40),
    );
  });

  testWidgets('Home offers it, and the form opens already on Treadmill', (
    tester,
  ) async {
    final writer = await pumpHome(tester);

    await tester.tap(find.text('Add a treadmill run'));
    await tester.pumpAndSettle();

    expect(find.text('Add a run'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Treadmill'))
          .selected,
      isTrue,
    );

    await tester.enterText(find.byType(TextField).at(0), '6');
    await tester.enterText(find.byType(TextField).at(1), '32:00');
    await tester.pump();
    await tester.tap(find.text('Add run'));
    await tester.pumpAndSettle();

    expect(writer!.added.single.type, kTypeTreadmill);
    expect(writer.added.single.distanceMeters, 6000);
    // Back on Home, not left on the form.
    expect(find.text('Add a run'), findsNothing);
  });

  testWidgets('and nothing is offered where a run cannot be written', (
    tester,
  ) async {
    await pumpHome(tester, editor: false);
    expect(find.text('Add a treadmill run'), findsNothing);
  });
}
