import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/history/domain/run_draft.dart';
import 'package:mgk_run/src/features/history/domain/run_writer.dart';
import 'package:mgk_run/src/features/history/presentation/run_form_screen.dart';

/// Add a run by hand (screen board S6). It opened with "How far did you go?"
/// and "How long did it take?" in red under two fields nobody had touched yet,
/// and with Kind on Treadmill, so a run added after the phone was left at home
/// was a treadmill run unless the runner noticed.
void main() {
  final now = DateTime(2026, 9, 30, 18, 5);

  Future<_Writer> pump(WidgetTester tester, {RunDraft? initial}) async {
    final writer = _Writer();
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RunFormScreen(
          editor: writer,
          runId: initial == null ? null : 'run-1',
          initial: initial,
          now: () => now,
        ),
      ),
    );
    await tester.pump();
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
}
