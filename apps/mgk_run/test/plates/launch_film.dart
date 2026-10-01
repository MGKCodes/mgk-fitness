/// **The launch animation, as a film.**
///
/// `launch.dart` draws it stopped, which is how a board reads it. This draws
/// it moving: the real [LaunchCurtain] over the real shell, one frame every
/// thirtieth of a second, written to `plates/launch-film/`. Stitch them with
///
///     python tool/stitch_launch_film.py
///
/// which writes `plates/launch.gif`. Not on the board and not in the suite: it
/// exists so the animation can be watched without a phone.
///
/// Regenerate with:
///
///     flutter test test/plates/launch_film.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/core/launch/launch_curtain.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_ui/mgk_ui.dart';

import 'fixture.dart';
import 'plate.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets('the launch, a frame every thirtieth of a second', (
    tester,
  ) async {
    const double pixelRatio = 1.5;
    const Duration step = Duration(microseconds: 33333);
    // The animation, and a beat of the app afterwards so the film has an end.
    final int frames =
        (kLaunchDuration.inMicroseconds / step.inMicroseconds).ceil() + 22;

    final store = DriftPlanStore(db);
    await seedPlan(store);
    final runs = plateLog();

    await loadInter();
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.devicePixelRatio = pixelRatio;
    tester.view.physicalSize = kPhone * pixelRatio;
    final EdgeInsets inset = safeAreaFor(kPhone);
    tester.view.padding = FakeViewPadding(
      top: inset.top * pixelRatio,
      bottom: inset.bottom * pixelRatio,
    );
    tester.view.viewPadding = FakeViewPadding(
      top: inset.top * pixelRatio,
      bottom: inset.bottom * pixelRatio,
    );
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final GlobalKey boundary = GlobalKey();
    final Directory out = Directory('plates/launch-film');
    if (out.existsSync()) out.deleteSync(recursive: true);
    out.createSync(recursive: true);

    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          // As `main.dart` wires it: the curtain over the navigator, the app
          // loading underneath from the first frame.
          builder: (context, child) => LaunchCurtain(child: child!),
          home: plateApp(db, store, runs),
        ),
      ),
    );

    for (var i = 0; i < frames; i++) {
      final RenderRepaintBoundary render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final ui.Image image = await render.toImage(pixelRatio: pixelRatio);
        final ByteData? png = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        image.dispose();
        File(
          '${out.path}/f${i.toString().padLeft(3, '0')}.png',
        ).writeAsBytesSync(png!.buffer.asUint8List());
      });
      await tester.pump(step);
    }
    // ignore: avoid_print
    print('film -> ${out.absolute.path} ($frames frames)');
    debugDefaultTargetPlatformOverride = null;
  });
}
