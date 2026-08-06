import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_note.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_button.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_reveal.dart';

void main() {
  const note = CoachNote(
    headline: 'Longest one yet.',
    detail: 'You went further than you ever have.',
    kind: CoachNoteKind.record,
  );

  /// Mounts the reveal the way the shell does: stretched full width, in a
  /// stack, with no height of its own.
  Future<void> pump(
    WidgetTester tester, {
    CoachNote? shown = note,
    VoidCallback? onTap,
    VoidCallback? onFinished,
    bool reduceMotion = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: CoachReveal(
                    note: shown,
                    onTap: onTap,
                    onFinished: onFinished,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('it says the line, then retracts into the mark', (tester) async {
    await pump(tester);

    // Typing is done by here, and what it typed is the whole observation —
    // heading and detail. A heading alone is a trailer for a sentence the
    // runner then has to go and find.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Longest one yet.'), findsOneWidget);
    expect(
      find.text('You went further than you ever have.'),
      findsOneWidget,
      reason: 'the detail is set under the heading, not run into it',
    );

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('C'), findsOneWidget);
  });

  // The rule that decides whether this is a nice touch or the thing everyone
  // turns off: it announces an observation, not a page load.
  testWidgets('a delivered observation does not announce itself again', (
    tester,
  ) async {
    var finished = 0;
    await pump(tester, onFinished: () => finished++);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(finished, 1);

    // What the shell does next: stops passing the note, so the mark rests.
    await pump(tester, shown: null);
    await tester.pumpAndSettle();
    expect(find.byType(CoachButton), findsOneWidget);
    expect(find.textContaining('Longest'), findsNothing);
  });

  testWidgets('tapping mid-sentence goes straight there', (tester) async {
    var opened = 0;
    await pump(tester, onTap: () => opened++);
    await tester.pump(const Duration(milliseconds: 800));

    await tester.tap(find.byType(CoachReveal));
    await tester.pump();

    expect(opened, 1, reason: 'the runner does not wait out the animation');
  });

  testWidgets('reduced motion means no motion, and no lost note', (
    tester,
  ) async {
    var finished = 0;
    await pump(tester, reduceMotion: true, onFinished: () => finished++);
    await tester.pumpAndSettle();

    // Straight to rest — nothing types, nothing retracts — and the caller is
    // still told, so the observation is not stuck undelivered forever.
    expect(find.text('C'), findsOneWidget);
    expect(finished, 1);
  });

  testWidgets('no observation is just the mark', (tester) async {
    await pump(tester, shown: null);
    await tester.pumpAndSettle();

    expect(find.byType(CoachButton), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
  });

  // The note arrives after the first build, because the run log is read
  // asynchronously. Without handling that the reveal sat at opacity zero
  // forever, which looked exactly like the mark having been deleted.
  testWidgets('an observation that arrives late still gets said', (
    tester,
  ) async {
    await pump(tester, shown: null);
    await tester.pumpAndSettle();

    await pump(tester);
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.textContaining('Longest'), findsOneWidget);
  });
}
