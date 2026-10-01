import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_run/src/features/history/domain/run_draft.dart';
import 'package:mgk_run/src/features/history/domain/run_writer.dart';
import 'package:mgk_run/src/features/history/presentation/run_form_screen.dart';

/// Add a run by hand (screen board S6). It opened with "How far did you go?"
/// and "How long did it take?" in red under two fields nobody had touched yet,
/// and with Kind on Treadmill, so a run added after the phone was left at home
/// was a treadmill run unless the runner noticed.
void main() {
  final now = DateTime(2026, 9, 30, 18, 5);

  Future<_Writer> pump(
    WidgetTester tester, {
    RunDraft? initial,
    UnitSystem unit = UnitSystem.metric,
    // An add can open with a draft too: Home's treadmill shortcut does.
    bool edit = true,
    void Function(String? result)? onPopped,
  }) async {
    final writer = _Writer();
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        // A fresh navigator each time: a test that pumps twice would otherwise
        // find the first form still on top of the button that opens the next.
        key: UniqueKey(),
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final result = await Navigator.of(context).push<String>(
                    MaterialPageRoute<String>(
                      builder: (_) => RunFormScreen(
                        editor: writer,
                        runId: initial == null || !edit ? null : 'run-1',
                        initial: initial,
                        unit: unit,
                        now: () => now,
                      ),
                    ),
                  );
                  onPopped?.call(result);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return writer;
  }

  final distance = find.byType(TextField).at(0);
  final time = find.byType(TextField).at(1);

  testWidgets('an untouched form shows no problems', (tester) async {
    await pump(tester);

    expect(find.text('How far did you go?'), findsNothing);
    expect(find.text('How long did it take?'), findsNothing);
    // The button still says what is missing.
    expect(find.text('Fill in the details above'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    // Nothing to delete yet.
    expect(find.byTooltip('Delete this run'), findsNothing);
  });

  // The unit was suffix text, which Material draws only once a field is
  // focused or filled: an empty Distance gave no sign of km or miles.
  testWidgets('an empty Distance says its unit before anything is typed', (
    tester,
  ) async {
    // Present is not enough: Material keeps suffix text in the tree at zero
    // opacity until the field is focused or filled. Shown means no fade above
    // it is at zero.
    void expectShown(String unit) {
      final label = find.descendant(of: distance, matching: find.text(unit));
      expect(label, findsOneWidget);
      final fades = <double>[
        for (final w in tester.widgetList<AnimatedOpacity>(
          find.ancestor(of: label, matching: find.byType(AnimatedOpacity)),
        ))
          w.opacity,
        for (final w in tester.widgetList<Opacity>(
          find.ancestor(of: label, matching: find.byType(Opacity)),
        ))
          w.opacity,
      ];
      expect(fades.where((o) => o == 0), isEmpty, reason: '$unit is hidden');
    }

    await pump(tester);
    expectShown('km');

    await pump(tester, unit: UnitSystem.imperial);
    expectShown('mi');
  });

  testWidgets('Kind starts outdoors', (tester) async {
    await pump(tester);

    final outdoor = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Outdoor'),
    );
    final treadmill = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Treadmill'),
    );
    expect(outdoor.selected, isTrue);
    expect(treadmill.selected, isFalse);
  });

  testWidgets('and a run added without changing it is saved as outdoor', (
    tester,
  ) async {
    final writer = await pump(tester);
    await tester.enterText(distance, '5');
    await tester.enterText(time, '28:30');
    await tester.pump();
    await tester.tap(find.text('Add run'));
    await tester.pumpAndSettle();

    expect(writer.added.single.type, kTypeOutdoor);
  });

  testWidgets('a field says what is wrong once it has been typed in', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(distance, '5');
    await tester.pump();
    await tester.enterText(distance, '');
    await tester.pump();

    expect(find.text('How far did you go?'), findsOneWidget);
    // The one not yet reached stays quiet.
    expect(find.text('How long did it take?'), findsNothing);
  });

  testWidgets('or once the runner has been into it and left', (tester) async {
    await pump(tester);
    await tester.tap(time);
    await tester.pump();
    expect(find.text('How long did it take?'), findsNothing);

    await tester.tap(distance);
    await tester.pump();
    expect(find.text('How long did it take?'), findsOneWidget);
  });

  testWidgets('an edit shows a stored value that is wrong straight away', (
    tester,
  ) async {
    await pump(
      tester,
      initial: RunDraft(
        startedAt: DateTime(2026, 9, 28, 7),
        duration: const Duration(minutes: 30),
        distanceMeters: 5000,
        type: kTypeTreadmill,
        avgHr: 400,
      ),
    );

    expect(find.text('Heart rate looks wrong.'), findsOneWidget);
    // And an edit keeps the kind it was stored with.
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Treadmill'))
          .selected,
      isTrue,
    );
  });

  // Home's "Add a treadmill run" opens the same form already saying so.
  testWidgets('an add can open on Treadmill, and still be an add', (
    tester,
  ) async {
    final writer = await pump(
      tester,
      initial: const RunDraft(type: kTypeTreadmill),
      edit: false,
    );

    expect(find.text('Add a run'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Treadmill'))
          .selected,
      isTrue,
    );
    expect(find.byTooltip('Delete this run'), findsNothing);

    await tester.enterText(distance, '5');
    await tester.enterText(time, '28:00');
    await tester.pump();
    await tester.tap(find.text('Add run'));
    await tester.pumpAndSettle();

    expect(writer.added.single.type, kTypeTreadmill);
  });

  group('deleting', () {
    final stored = RunDraft(
      startedAt: DateTime(2026, 9, 28, 7),
      duration: const Duration(minutes: 30),
      distanceMeters: 5000,
      type: kTypeOutdoor,
    );

    // On a phone, not the tall surface the other tests use: it was first put
    // under Notes, which is below the fold, and nothing here noticed.
    testWidgets('the way to it is on screen without scrolling', (tester) async {
      await pump(tester, initial: stored);
      await tester.binding.setSurfaceSize(const Size(393, 760));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Delete this run').hitTestable(), findsOneWidget);
    });

    testWidgets('asks first, and "Keep it" deletes nothing', (tester) async {
      final writer = await pump(tester, initial: stored);

      await tester.tap(find.byTooltip('Delete this run'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this run?'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);

      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();

      expect(writer.deleted, isEmpty);
      expect(find.text('Edit run'), findsOneWidget, reason: 'still here');
    });

    testWidgets('confirmed, it deletes the run and says so to the caller', (
      tester,
    ) async {
      String? popped;
      final writer = await pump(
        tester,
        initial: stored,
        onPopped: (r) => popped = r,
      );

      await tester.tap(find.byTooltip('Delete this run'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(writer.deleted, <String>['run-1']);
      expect(popped, RunFormScreen.deleted);
      expect(find.text('Edit run'), findsNothing);
    });

    testWidgets('with no signal it stays, and says what to do', (tester) async {
      final writer = await pump(tester, initial: stored);
      writer.offline = true;

      await tester.tap(find.byTooltip('Delete this run'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Couldn't delete that run. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      expect(find.text('Edit run'), findsOneWidget);
      expect(writer.deleted, isEmpty);
    });
  });
}

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
  Future<RunDraft?> draftOf(String runId) async => null;

  @override
  Future<int> backfill() async => 0;

  final List<String> deleted = <String>[];

  /// Set to refuse, standing in for a phone with no signal.
  bool offline = false;

  @override
  Future<void> delete(String runId) async {
    if (offline) throw const RunDeleteFailed();
    deleted.add(runId);
  }
}
