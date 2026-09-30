import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('HeroStatTile', () {
    testWidgets('counts up to its figure and sets the suffix beside it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const HeroStatTile(
            label: 'This week',
            count: 2,
            suffix: 'of 4',
            caption: 'sessions since Monday',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('THIS WEEK'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('of 4'), findsOneWidget);
      expect(find.text('sessions since Monday'), findsOneWidget);
    });

    testWidgets('is glass, because it sits over the photograph', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const HeroStatTile(label: 'This week', count: 0)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GlassSurface), findsOneWidget);
    });
  });

  group('the tiles moved from Run', () {
    testWidgets('a stat tile is square and shows its figure', (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 160,
            child: HomeStatTile(label: 'Streak', value: '3', caption: 'weeks'),
          ),
        ),
      );
      final size = tester.getSize(find.byType(HomeStatTile));
      expect(size.width, size.height);
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('ActionPill', () {
    testWidgets('presses once per tap', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 340,
            child: ActionPill(
              label: 'Start a session',
              onPressed: () => pressed++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start a session'));
      await tester.pumpAndSettle();
      expect(pressed, 1);
    });

    testWidgets('is announced as a button, and as disabled without an action', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 340,
            child: ActionPill(label: 'Start a session', onPressed: null),
          ),
        ),
      );
      final semantics = tester.getSemantics(find.byType(ActionPill));
      expect(
        semantics,
        matchesSemantics(
          label: 'Start a session',
          isButton: true,
          hasEnabledState: true,
        ),
      );
    });

    testWidgets('is taller than a primary button', (tester) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 340,
            child: ActionPill(label: 'Start', onPressed: () {}),
          ),
        ),
      );
      expect(tester.getSize(find.byType(ActionPill)).height, ActionPill.height);
    });
  });

  group('PhotoBackdrop.hero', () {
    testWidgets('keeps the photograph full width and at the top', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 390,
            height: 844,
            child: PhotoBackdrop.hero(image: 'missing.webp'),
          ),
        ),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.fitWidth);
      expect(image.alignment, Alignment.topCenter);
      // Strong, which is the whole difference from the texture.
      final opacity = tester.widget<Opacity>(
        find.ancestor(of: find.byType(Image), matching: find.byType(Opacity)),
      );
      expect(opacity.opacity, greaterThan(0.6));
    });

    testWidgets('the texture is unchanged by it', (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 390,
            height: 844,
            child: PhotoBackdrop(image: 'missing.webp'),
          ),
        ),
      );
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
    });
  });

  testWidgets('GlowBackdrop draws its child over the light', (tester) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 390,
          height: 844,
          child: GlowBackdrop(child: Text('set')),
        ),
      ),
    );
    expect(find.text('set'), findsOneWidget);
  });

  group('SmallPill', () {
    testWidgets('hugs its label, and its target is taller than it looks', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[SmallPill(label: 'Start', onPressed: () {})],
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byType(SmallPill));
      expect(size.width, lessThan(150));
      expect(size.height, 44);
    });

    testWidgets('presses, and is a disabled button without an action', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        _host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SmallPill(label: 'Start', onPressed: () => presses++),
              const SmallPill(label: 'Add', onPressed: null),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(presses, 1);

      final add = tester.getSemantics(find.byType(SmallPill).last);
      expect(
        add,
        matchesSemantics(
          label: 'Add',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
    });
  });

  group('GlassSurface.grouped', () {
    testWidgets('shares the blur of the group it is in', (tester) async {
      await tester.pumpWidget(
        _host(
          BackdropGroup(
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                GlassSurface(grouped: true, child: Text('one')),
                GlassSurface(grouped: true, child: Text('two')),
              ],
            ),
          ),
        ),
      );
      final keys = <BackdropKey?>[
        for (final r in tester.renderObjectList<RenderBackdropFilter>(
          find.byType(BackdropFilter),
        ))
          r.backdropKey,
      ];
      expect(keys, hasLength(2));
      // One backdrop, read by both panes.
      expect(keys.first, isNotNull);
      expect(keys.first, same(keys.last));
    });

    testWidgets('is an ordinary pane unless asked', (tester) async {
      await tester.pumpWidget(
        _host(BackdropGroup(child: const GlassSurface(child: Text('one')))),
      );
      final filter = tester.renderObject<RenderBackdropFilter>(
        find.byType(BackdropFilter),
      );
      expect(filter.backdropKey, isNull);
    });
  });
}
