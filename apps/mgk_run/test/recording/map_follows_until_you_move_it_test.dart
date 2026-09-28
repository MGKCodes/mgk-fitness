import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';
import 'package:mgk_run/src/features/recording/presentation/route_map.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **The in-run map pans now, and following is a mode** (ADR-0031).
///
/// It took no gestures at all until 2026-09-08. The build 13 field test asked
/// for panning and a recentre control directly, which reverses a decision this
/// screen's class doc had recorded — so what is asserted here is the half that
/// makes the reversal safe rather than merely possible: a pan **parks** the
/// camera, and only the control puts it back.
///
/// Without that, panning is worse than useless: the follow used to be
/// unconditional, so a moved map would be dragged back by the next GPS fix,
/// roughly once a second.
void main() {
  Future<FakeRunRecorder> pumpRun(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final recorder = FakeRunRecorder();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(recorder: recorder),
      ),
    );
    // Fixed pumps: the fake recorder emits on a repeating timer, so the tree
    // never goes quiet and `pumpAndSettle` waits forever.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    return recorder;
  }

  RouteMap mapOf(WidgetTester tester) =>
      tester.widget<RouteMap>(find.byType(RouteMap));

  testWidgets('it follows until somebody moves it, and offers no control', (
    tester,
  ) async {
    final recorder = await pumpRun(tester);

    expect(mapOf(tester).follow, isTrue);
    expect(
      find.byTooltip('Recentre'),
      findsNothing,
      reason: 'a recentre on a centred map is furniture',
    );
    await recorder.stop(); // cancel the replay timer before teardown
  });

  testWidgets('a pan parks the camera and raises the control', (tester) async {
    final recorder = await pumpRun(tester);

    // Through the widget's own callback rather than by dragging: what a real
    // pan does is call this, and driving flutter_map's gesture detector in a
    // test asserts flutter_map rather than this screen.
    mapOf(tester).onUserPan!();
    await tester.pump();

    expect(mapOf(tester).follow, isFalse);
    expect(find.byTooltip('Recentre'), findsOneWidget);
    await recorder.stop();
  });

  testWidgets('and the control puts it back', (tester) async {
    final recorder = await pumpRun(tester);
    mapOf(tester).onUserPan!();
    await tester.pump();

    await tester.tap(find.byTooltip('Recentre'));
    await tester.pump();

    expect(mapOf(tester).follow, isTrue);
    expect(find.byTooltip('Recentre'), findsNothing);
    await recorder.stop();
  });

  testWidgets('following is never restored on its own', (tester) async {
    // The disconfirming condition for ADR-0031. An auto-resume yanks the camera
    // back while somebody is reading a junction, unasked — which is worse than
    // the map not panning at all, and is the failure panning was refused to
    // avoid. If this ever goes green by itself, the decision was wrong.
    final recorder = await pumpRun(tester);
    mapOf(tester).onUserPan!();
    await tester.pump();

    await tester.pump(const Duration(seconds: 10));

    expect(mapOf(tester).follow, isFalse);
    expect(find.byTooltip('Recentre'), findsOneWidget);
    await recorder.stop();
  });

  testWidgets('rotation stays declined, whatever else the map accepts', (
    tester,
  ) async {
    // ADR-0022 declines rotation as a decision rather than an omission, and
    // `InteractiveFlag.all` includes it — so turning panning on with `all`
    // would have reversed that ADR in one word, silently.
    final recorder = await pumpRun(tester);

    final int flags = mapOf(tester).interactionFlags;
    expect(flags & InteractiveFlag.rotate, 0);
    expect(flags & InteractiveFlag.drag, isNot(0));
    expect(
      flags & InteractiveFlag.pinchMove,
      0,
      reason: 'it takes slow vertical drags the sheet needs',
    );
    await recorder.stop();
  });
}
