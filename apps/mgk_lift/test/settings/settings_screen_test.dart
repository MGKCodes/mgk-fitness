import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/settings/domain/unit_preferences.dart';
import 'package:mgk_lift/src/features/settings/presentation/credits_screen.dart';
import 'package:mgk_lift/src/features/settings/presentation/settings_screen.dart';
import 'package:mgk_units/mgk_units.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('units', () {
    testWidgets('distance and weight are two separate controls', (
      WidgetTester tester,
    ) async {
      // The whole point of the units work: miles with kilograms is ordinary,
      // and one metric/imperial switch made it unreachable.
      await tester.pumpWidget(
        wrap(
          SettingsScreen(
            initial: const UnitPreferences(),
            store: InMemoryUnitPreferences(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kilometres'), findsOneWidget);
      expect(find.text('Miles'), findsOneWidget);
      expect(find.text('Kilograms'), findsOneWidget);
      expect(find.text('Pounds'), findsOneWidget);
    });

    testWidgets('choosing miles leaves the weight unit alone', (
      WidgetTester tester,
    ) async {
      final store = InMemoryUnitPreferences();
      await tester.pumpWidget(
        wrap(SettingsScreen(initial: const UnitPreferences(), store: store)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Miles'));
      await tester.pumpAndSettle();

      final saved = await store.load();
      expect(saved.distance, UnitSystem.imperial);
      expect(saved.mass, MassUnit.kilograms);
    });

    testWidgets('the change is reported up before it is persisted', (
      WidgetTester tester,
    ) async {
      // Track logs and Profile reports in these units, so the shell has to hear
      // about it without waiting for a round trip or for this screen to close.
      UnitPreferences? reported;
      await tester.pumpWidget(
        wrap(
          SettingsScreen(
            initial: const UnitPreferences(),
            store: InMemoryUnitPreferences(),
            onChanged: (p) => reported = p,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pounds'));
      await tester.pump();

      expect(reported?.mass, MassUnit.pounds);
    });

    testWidgets('with no store the controls are inert, not absent', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const SettingsScreen(initial: UnitPreferences())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pounds'), findsOneWidget);
      await tester.tap(find.text('Pounds'));
      await tester.pumpAndSettle();

      // Nothing happened, and the screen says why rather than silently
      // swallowing the tap.
      expect(find.text('Sign in to change these.'), findsOneWidget);
    });
  });

  group('credits', () {
    // These assertions exist because the original app deleted its Everkinetic
    // credit in a single commit and then claimed sole ownership of the art.
    // Attribution is a licence condition, so it is tested like one.

    testWidgets('are reachable from settings', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(const SettingsScreen(initial: UnitPreferences())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Credits'));
      await tester.pumpAndSettle();

      expect(find.byType(CreditsScreen), findsOneWidget);
    });

    testWidgets('name the creator, the licence and the original', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap(const CreditsScreen()));
      await tester.pumpAndSettle();

      // CC BY-SA 4.0 s3(a)(1): creator, copyright notice, licence notice,
      // disclaimer, and a URI to the licensed material.
      expect(find.textContaining('Greg Priday'), findsOneWidget);
      expect(find.textContaining('© Everkinetic'), findsOneWidget);
      expect(find.textContaining('CC BY-SA 4.0'), findsOneWidget);
      expect(find.textContaining('without warranties'), findsOneWidget);
      expect(find.text('github.com/everkinetic/data'), findsOneWidget);
      expect(
        find.text('creativecommons.org/licenses/by-sa/4.0/'),
        findsOneWidget,
      );
    });

    testWidgets('say the images were modified', (WidgetTester tester) async {
      // s3(a)(1)(B) — indicating modification is its own condition, separate
      // from naming the creator.
      await tester.pumpWidget(wrap(const CreditsScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('redrawn'), findsOneWidget);
    });

    testWidgets('pass the licence on rather than claiming the art', (
      WidgetTester tester,
    ) async {
      // ShareAlike. This is the line that contradicts "all rights reserved",
      // and it is the reason the credit alone would not have been enough.
      await tester.pumpWidget(wrap(const CreditsScreen()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('adaptations are likewise offered under CC BY-SA'),
        findsOneWidget,
      );
    });
  });
}
