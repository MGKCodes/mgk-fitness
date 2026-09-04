import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

import 'package:mgk_run/src/features/onboarding/domain/intro_permission.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_script.dart';
import 'package:mgk_run/src/features/onboarding/presentation/intro_screen.dart';

/// **The two clocks of the intro conversation, and the join between them.**
///
/// The transcript is paced by `SequencedReveal`, which lands one turn per beat
/// off a `Timer`. The answer area used to be a plain `switch` on the step,
/// rebuilding in the same frame as the tap. Nothing connected the two, so a
/// build 12 tester met the input before the question: tapping "Sounds good"
/// raised a `TextField` and the keyboard a full beat before "What should I call
/// you?" had been said. The first frame had the same fault, painting the
/// button before the greeting existed.
///
/// These tests run **paced**, which a widget test is not by default: the test
/// binding reports reduced motion, so `SequencedReveal` reveals everything in
/// one frame and every other flow test in the suite finds its buttons on the
/// frame it taps them. Overriding `disableAnimations` back to false is what
/// makes the beats — and therefore the ordering being asserted — real.
void main() {
  /// A beat and change. `SequencedReveal` beats at 620ms and opens at 260ms,
  /// so one of these settles exactly one turn.
  const beat = Duration(milliseconds: 700);

  Future<void> pumpIntro(
    WidgetTester tester, {
    bool paced = true,
    IntroAnswers initial = const IntroAnswers(),
    void Function(String? name)? onFinished,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => MediaQuery(
            // Copied from the ambient data rather than built fresh, so the
            // screen keeps a real size and real padding and only the one
            // property under test changes.
            data: MediaQuery.of(context).copyWith(disableAnimations: !paced),
            child: IntroScreen(
              initial: initial,
              onFinished: onFinished,
              requestPermission: (_) async => true,
            ),
          ),
        ),
      ),
    );
  }

  /// Reveals [turns] more of the transcript.
  Future<void> settleTurns(WidgetTester tester, int turns) async {
    for (var i = 0; i < turns; i++) {
      await tester.pump(beat);
    }
  }

  /// Taps, then builds the frame the tap dirtied.
  ///
  /// `pump(duration)` elapses the clock *before* it draws, so a tap followed
  /// straight by a beat measures a beat that had not started: the turns the
  /// tap queued are not scheduled until the frame carrying them is built.
  Future<void> tapAndBuild(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
    await tester.pump();
  }

  group('the input waits for the question', () {
    testWidgets('nothing to tap until the greeting has been said', (
      tester,
    ) async {
      await pumpIntro(tester);

      // The screen opens on somebody composing, not on a button. A button
      // before the first word is the app answering a question it has not
      // asked.
      expect(find.byType(TypingIndicator), findsOneWidget);
      expect(find.text('Sounds good'), findsNothing);

      await settleTurns(tester, 1);
      expect(find.text(introPrompt(IntroStep.greeting)), findsOneWidget);
      expect(
        find.text('Sounds good'),
        findsNothing,
        reason: 'two turns of the greeting are still to come',
      );

      await settleTurns(tester, 1);
      expect(find.text(introWhoIAm), findsOneWidget);
      expect(find.text('Sounds good'), findsNothing);

      await settleTurns(tester, 1);
      expect(find.text(introHowItWorks), findsOneWidget);
      expect(find.text('Sounds good'), findsOneWidget);
    });

    testWidgets('the field and the keyboard never precede the question', (
      tester,
    ) async {
      await pumpIntro(tester);
      await settleTurns(tester, 3);
      await tapAndBuild(tester, find.text('Sounds good'));

      // **The defect, pinned.** The step advanced in this frame, so the old
      // code had already swapped in an autofocusing `TextField`. The question
      // it answers is a beat away.
      expect(find.text(introPrompt(IntroStep.name)), findsNothing);
      expect(find.byType(TextField), findsNothing);

      // Part way through the beat, still nothing — this is what says the
      // failsafe below is a backstop rather than the thing doing the work.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TextField), findsNothing);

      await settleTurns(tester, 1);
      expect(find.text(introPrompt(IntroStep.name)), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a permission is explained before it can be granted', (
      tester,
    ) async {
      // The same seam one step on, where a single tap queues three turns at
      // once — the runner's own answer, the coach's acknowledgement and the
      // next explanation. A gate that counted taps rather than turns would let
      // the button back in after the first of them.
      await pumpIntro(tester);
      await settleTurns(tester, 3);
      await tapAndBuild(tester, find.text('Sounds good'));
      await settleTurns(tester, 1);
      await tester.enterText(find.byType(TextField), 'Sam');
      await tapAndBuild(tester, find.byTooltip('Continue'));

      expect(find.text(introPermissions.first.cta), findsNothing);

      // Reply, "nearly there", then the explanation itself.
      await settleTurns(tester, 2);
      expect(find.text(introPermissions.first.explain), findsNothing);
      expect(find.text(introPermissions.first.cta), findsNothing);

      await settleTurns(tester, 1);
      expect(find.text(introPermissions.first.explain), findsOneWidget);
      expect(find.text(introPermissions.first.cta), findsOneWidget);
    });
  });

  testWidgets('the runner can always answer, at every step of the walk', (
    tester,
  ) async {
    // The gate's failure mode is a runner stranded on a conversation with
    // nothing to tap, which is worse than the mistiming it fixes. This walks
    // the whole paced conversation and refuses to proceed unless each control
    // has turned up.
    String? finishedWith;
    var finished = false;
    await pumpIntro(
      tester,
      onFinished: (name) {
        finished = true;
        finishedWith = name;
      },
    );

    await settleTurns(tester, 3);
    expect(find.text('Sounds good'), findsOneWidget);
    await tapAndBuild(tester, find.text('Sounds good'));

    await settleTurns(tester, 1);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Sam');
    await tapAndBuild(tester, find.byTooltip('Continue'));

    for (final permission in introPermissions) {
      // Reply, "nearly there" on the first pass, then the explanation.
      await settleTurns(tester, 3);
      expect(
        find.text(permission.cta),
        findsOneWidget,
        reason: 'no way to answer ${permission.kind}',
      );
      await tapAndBuild(tester, find.text(permission.cta));

      // The answer and the coach's reply to it.
      await settleTurns(tester, 2);
      expect(find.text('Continue'), findsOneWidget);
      await tapAndBuild(tester, find.text('Continue'));
    }

    expect(finished, isTrue);
    expect(finishedWith, 'Sam');
  });

  group('reduced motion', () {
    testWidgets('answers immediately, because there is no beat to wait for', (
      tester,
    ) async {
      // `SequencedReveal` paints the lot in one frame here and never fires the
      // callback the gate listens on. Waiting for it would mean a runner who
      // asked the OS for less movement got a conversation with no input at
      // all — the gate has to read the same query the reveal does.
      await pumpIntro(tester, paced: false);
      await tester.pump();

      expect(find.text(introHowItWorks), findsOneWidget);
      expect(find.text('Sounds good'), findsOneWidget);

      await tapAndBuild(tester, find.text('Sounds good'));
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  testWidgets('a runner arriving with a name is not asked for one again', (
    tester,
  ) async {
    // The skipped step must not leave a turn pending that never lands: the
    // gate would then hold the input shut for a question the transcript is
    // deliberately not asking.
    await pumpIntro(tester, initial: const IntroAnswers(name: 'Sam'));
    await settleTurns(tester, 3);

    await tapAndBuild(tester, find.text('Sounds good'));
    await settleTurns(tester, 2);

    expect(find.byType(TextField), findsNothing);
    expect(find.text(introPrompt(IntroStep.name)), findsNothing);
    expect(find.text(introPermissions.first.cta), findsOneWidget);
  });
}
