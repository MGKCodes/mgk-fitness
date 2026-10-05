/// Design plates: a widget rendered straight to a PNG, with no browser.
///
/// The web harness answers a different question. Judging a letterform used to
/// cost a two-minute release build, a static server and a headed Chrome, for
/// five rows of static text — and the browser is the part of that loop least
/// suited to it, since Flutter draws its own glyphs into a canvas anyway. This
/// renders the same widget tree through the same engine and writes the pixels
/// out in about a second.
///
/// Not a golden test: nothing here asserts. These are throwaway plates for a
/// design call, so the file is named `plate.dart` rather than `*_test.dart` and
/// stays out of the suite. Run one directly:
///
///     flutter test test/plates/hero_weights.dart
///
/// Keep the browser for what it is actually needed for — the draggable sheet
/// and anything else driven by touch.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The surface every plate is pinned to.
///
/// The default 800x600 test surface is not a phone, and it has already hidden
/// three P1s on this screen. A plate drawn at a size no runner holds is worse
/// than no plate, because it looks like evidence.
const Size kPhone = Size(393, 852);

/// The narrowest phone still worth supporting, and the widest. Both belong on
/// a board: the small one is where a computed detent strands the controls, and
/// the large one is where a layout tuned on the small one goes slack.
const Size kSmallPhone = Size(320, 568);
const Size kMaxPhone = Size(430, 932);

/// Real Inter, loaded from the package's assets.
///
/// Without this the test framework draws every glyph as a placeholder box,
/// which is silently useless for the one thing a plate is for. Note the family
/// is the package-qualified name — see [AppTheme.fontFamily].
///
/// Only the cuts that exist are listed, and there is no `Inter-ExtraLight`:
/// the package ships 100/300/400/500/600/700/800/900. Asking for `w200` gets
/// Thin, not a synthesised ExtraLight, which is worth knowing before picking a
/// weight off a plate.
Future<void> loadInter() async {
  const String root = '../../packages/mgk_ui/assets/fonts';
  const List<String> faces = <String>[
    'Inter-Thin.ttf',
    'Inter-Light.ttf',
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
    'Inter-Bold.ttf',
    'Inter-ExtraBold.ttf',
    'Inter-Black.ttf',
  ];

  final FontLoader loader = FontLoader(AppTheme.fontFamily);
  for (final String face in faces) {
    final File file = File('$root/$face');
    if (!file.existsSync()) {
      throw StateError(
        'Missing font $face at ${file.absolute.path}. Plates are run from '
        'apps/mgk_run, and the paths above are relative to it.',
      );
    }
    loader.addFont(
      Future<ByteData>.value(ByteData.view(file.readAsBytesSync().buffer)),
    );
  }
  await loader.load();
  await _loadIcons();
}

/// **Real icons, for the same reason as real Inter.**
///
/// Without this every `Icon` in the app draws as a hollow square, because the
/// icon font is an SDK artifact rather than a package asset and the test bundle
/// does not carry it. That is not a neutral omission on a design board: the nav
/// bar, every affordance in Settings and every glyph on a run's stats grid all
/// come out as boxes, and a reader cannot tell a square that means "no icon
/// font" from a square that means "nobody drew this icon yet". The board is
/// read for exactly that kind of gap, so it has to stop manufacturing them.
///
/// Found through `FLUTTER_ROOT`, which `flutter test` sets, rather than a path
/// typed into this file — the SDK does not live in the same place on two
/// machines. A missing font is skipped rather than thrown: squares are worse
/// than icons, but they are much better than no plate at all.
Future<void> _loadIcons() async {
  final String? root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final File file = File(
    '$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  );
  if (!file.existsSync()) return;
  final FontLoader icons = FontLoader('MaterialIcons');
  icons.addFont(
    Future<ByteData>.value(ByteData.view(file.readAsBytesSync().buffer)),
  );
  await icons.load();
}

final GlobalKey _boundary = GlobalKey();

/// **The safe areas of the phone a plate is drawn as.**
///
/// A real iPhone never lays a screen out edge to edge: the status bar and the
/// Dynamic Island take the top 59pt of a 393x852 phone and the home indicator
/// the bottom 34pt, and every `SafeArea` in the app answers to those numbers.
/// Plates used to be drawn with none, so a nav bar or a sheet's last button
/// could sit where a thumb and the home indicator are and the board would call
/// it fine. The top band is left empty rather than drawn: the clock is the
/// phone's, not the app's.
///
/// Only the three phone sizes get insets. A crop of one component (the year
/// grid, the coach mark, a route drawing) is not a screen and has none.
EdgeInsets safeAreaFor(Size size) {
  if (size == kPhone || size == kMaxPhone) {
    return const EdgeInsets.only(top: 59, bottom: 34);
  }
  if (size == kSmallPhone) return const EdgeInsets.only(top: 20);
  return EdgeInsets.zero;
}

/// Renders [child] at [size] and writes it to `plates/<name>.png`.
///
/// [pixelRatio] 3 matches a modern phone's density, so hairline strokes are
/// judged at the density they will actually be drawn at rather than at 1x,
/// where a thin cut looks heavier than it is.
///
/// **[platform] is an iPhone unless a plate says otherwise.** `flutter test`
/// runs as Android by default, so every plate before build 26 was quietly an
/// Android screen: the paywall named a Google Play account, the intro dropped
/// its Health step, and the App Store review screenshot cut from `paywall-store`
/// described the wrong store. The board is read against the App Store build
/// first; a plate that is about Android asks for it by name.
///
/// [safeArea] and [into] are for the store's screenshots (`store.dart`), which
/// are drawn as phones the board has no size for and are written somewhere the
/// board does not read.
Future<void> plate(
  WidgetTester tester,
  String name,
  Widget child, {
  Size size = kPhone,
  double pixelRatio = 3,
  TargetPlatform platform = TargetPlatform.iOS,
  Future<void> Function(WidgetTester tester)? drive,
  EdgeInsets? safeArea,
  String into = 'plates',
}) async {
  await loadInter();
  debugDefaultTargetPlatformOverride = platform;
  // **The view, not only the surface.** `setSurfaceSize` sizes what is laid
  // out, but `MediaQuery` reads the test *view*, which stays at its default
  // 800x600. Every plate was therefore laid out at 393x852 while telling the
  // app the screen was 800x600 — so each sheet that sizes itself off the
  // screen (the coach's conversation, the consent sheet, the report sheet)
  // came out the wrong height, and nothing looked broken enough to notice.
  tester.view.devicePixelRatio = pixelRatio;
  tester.view.physicalSize = size * pixelRatio;
  final EdgeInsets inset = safeArea ?? safeAreaFor(size);
  tester.view.padding = FakeViewPadding(
    top: inset.top * pixelRatio,
    bottom: inset.bottom * pixelRatio,
  );
  tester.view.viewPadding = FakeViewPadding(
    top: inset.top * pixelRatio,
    bottom: inset.bottom * pixelRatio,
  );
  addTearDown(tester.view.reset);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: child,
      ),
    ),
  );
  // Fixed pumps rather than pumpAndSettle: a live screen emits on a repeating
  // timer and settle never returns. A plate of a *state* — half a kilometre in,
  // signal lost — supplies its own [drive] to reach it.
  if (drive != null) {
    await drive(tester);
  } else {
    await tester.pump(const Duration(milliseconds: 700));
  }

  // Every image on the screen is loaded for real before it is photographed.
  // Decoding happens off the fake clock, so an image this file had not drawn
  // before came out as an empty box: Run's icon on the arrival's sign-in, on
  // 3 October 2026, beside a backdrop that only showed because an earlier
  // plate had already loaded it.
  await tester.runAsync(() async {
    for (final Element element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pump();

  final RenderRepaintBoundary boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  // Inside runAsync: toImage hands its work to the engine and completes on a
  // real microtask. The test zone's fake clock never runs one, so awaiting it
  // directly hangs forever rather than failing.
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? png = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();

    final Directory out = Directory(into);
    if (!out.existsSync()) out.createSync(recursive: true);
    final File file = File('${out.path}/$name.png');
    file.writeAsBytesSync(png!.buffer.asUint8List());
    // ignore: avoid_print
    print('plate -> ${file.absolute.path}');
  });
  // Reset here rather than in a tear-down: the framework checks that no
  // foundation debug variable is left set before tear-downs run.
  debugDefaultTargetPlatformOverride = null;
}
