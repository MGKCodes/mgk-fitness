import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/launch/launch_curtain.dart';

/// Stands in for the app: counts how many times it was built from nothing, and
/// how many times it was tapped.
class _App extends StatefulWidget {
  const _App(this.log);

  final Map<String, int> log;

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  @override
  void initState() {
    super.initState();
    widget.log['inits'] = (widget.log['inits'] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => widget.log['taps'] = (widget.log['taps'] ?? 0) + 1,
    child: const Center(child: Text('the app')),
  );
}

/// The app used to drop straight in. It opens now on the icon's mark going,
/// and leaving the app's name behind it, with the app loading underneath.
void main() {
  Future<Map<String, int>> pump(
    WidgetTester tester, {
    bool enabled = true,
    bool reduceMotion = false,
  }) async {
    final log = <String, int>{};
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: LaunchCurtain(enabled: enabled, child: child!),
        ),
        home: _App(log),
      ),
    );
    return log;
  }

  final curtain = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is LaunchMarkPainter,
  );

  testWidgets('the app is built underneath from the first frame', (
    tester,
  ) async {
    final log = await pump(tester);

    expect(curtain, findsOneWidget);
    expect(log['inits'], 1, reason: 'loading while the animation plays');
    await tester.pumpAndSettle();
  });

  testWidgets('it takes every touch while it is up', (tester) async {
    final log = await pump(tester);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tapAt(tester.getCenter(find.byType(MaterialApp)));

    expect(log['taps'], isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('and then it is gone, and the app was never rebuilt', (
    tester,
  ) async {
    final log = await pump(tester);

    await tester.pump(kLaunchCurtainUp - const Duration(milliseconds: 50));
    expect(curtain, findsOneWidget, reason: 'still lifting');

    await tester.pump(const Duration(milliseconds: 100));
    expect(curtain, findsNothing);
    expect(log['inits'], 1, reason: 'the same app that loaded under it');

    // The app takes a tap the moment the curtain is gone, though it is still
    // settling behind where the curtain was.
    await tester.tap(find.text('the app'));
    expect(log['taps'], 1);
    await tester.pumpAndSettle();
    expect(log['inits'], 1);
  });

  testWidgets('it lifts by fading, at the end', (tester) async {
    await pump(tester);
    double opacity() => tester
        .widget<Opacity>(
          find.ancestor(of: curtain, matching: find.byType(Opacity)),
        )
        .opacity;

    await tester.pump(const Duration(milliseconds: 1500));
    expect(opacity(), 1, reason: 'the name is held at full strength');

    await tester.pump(const Duration(milliseconds: 330));
    expect(opacity(), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
  });

  testWidgets('the app arrives: a touch large, then at rest', (tester) async {
    await pump(tester);
    double scale() => tester
        .widget<Transform>(
          find
              .ancestor(
                of: find.text('the app'),
                matching: find.byType(Transform),
              )
              .last,
        )
        .transform
        .getMaxScaleOnAxis();

    await tester.pump(const Duration(milliseconds: 800));
    expect(scale(), closeTo(1.035, 0.0005));

    await tester.pumpAndSettle();
    expect(scale(), 1);
  });

  testWidgets('with Reduce Motion on, it is not shown at all', (tester) async {
    final log = await pump(tester, reduceMotion: true);

    expect(curtain, findsNothing);
    await tester.tap(find.text('the app'));
    expect(log['taps'], 1);
  });

  testWidgets('nor anywhere that did not ask for it', (tester) async {
    await pump(tester, enabled: false);
    expect(curtain, findsNothing);
    expect(find.text('the app'), findsOneWidget);
  });

  // Every beat, at the smallest phone and the largest, without throwing.
  testWidgets('every frame can be drawn, at every size', (tester) async {
    for (final size in const <Size>[
      Size(320, 568),
      Size(393, 852),
      Size(430, 932),
      Size(1024, 1366),
    ]) {
      for (var i = 0; i <= 100; i++) {
        final recorder = ui.PictureRecorder();
        LaunchMarkPainter(progress: i / 100).paint(Canvas(recorder), size);
        recorder.endRecording().dispose();
      }
    }
  });

  test('it repaints only when the moment changes', () {
    const a = LaunchMarkPainter(progress: 0.4);
    expect(a.shouldRepaint(const LaunchMarkPainter(progress: 0.4)), isFalse);
    expect(a.shouldRepaint(const LaunchMarkPainter(progress: 0.5)), isTrue);
  });
}
