import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/coaching/data/supabase_coach.dart';
import 'package:mgk_lift/preview/fakes.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';
import 'package:mgk_lift/src/features/legal/presentation/legal_document_screen.dart';
import 'package:mgk_lift/src/features/settings/data/local_coach_preference.dart';
import 'package:mgk_lift/src/features/settings/domain/coach_preference.dart';
import 'package:mgk_lift/src/features/settings/domain/unit_preferences.dart';
import 'package:mgk_lift/src/features/settings/presentation/settings_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpTall(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  group('where the choice is kept', () {
    test('a device that has never been asked gets the coach', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      expect(await LocalCoachPreference(prefs: prefs).load(), isTrue);
    });

    test('the answer survives a relaunch', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      await LocalCoachPreference(prefs: prefs).save(enabled: false);
      // A second instance, as a relaunch would build.
      expect(await LocalCoachPreference(prefs: prefs).load(), isFalse);
    });

    test('resolves the plugin per call rather than at construction', () async {
      // Constructing this must not require the binding to be ready — the same
      // property LocalUnitPreferences has, and what lets main.dart build it
      // inline in a const-ish widget tree.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = LocalCoachPreference();

      // A launch is not worth failing over a switch, so a store that has never
      // been told anything answers the default instead of throwing.
      expect(await store.load(), isTrue);
    });
  });

  group('the switch in Settings', () {
    testWidgets('is absent when there is no coach to switch off', (
      WidgetTester tester,
    ) async {
      await pumpTall(
        tester,
        SettingsScreen(
          initial: const UnitPreferences(),
          store: InMemoryUnitPreferences(),
        ),
      );

      expect(find.text('Use the AI coach'), findsNothing);
    });

    testWidgets('names the provider in the row, not only in the document', (
      WidgetTester tester,
    ) async {
      await pumpTall(
        tester,
        SettingsScreen(
          initial: const UnitPreferences(),
          store: InMemoryUnitPreferences(),
          useCoach: true,
          onUseCoachChanged: (_) {},
        ),
      );

      expect(find.text('Use the AI coach'), findsOneWidget);
      expect(
        find.text('On. What you write is sent to OpenRouter.'),
        findsOneWidget,
      );
      // The sentence under it is the one that says what "it" actually is.
      expect(find.textContaining('injury notes'), findsOneWidget);
    });

    testWidgets('says what is happening now, not what the switch does', (
      WidgetTester tester,
    ) async {
      await pumpTall(
        tester,
        SettingsScreen(
          initial: const UnitPreferences(),
          store: InMemoryUnitPreferences(),
          useCoach: false,
          onUseCoachChanged: (_) {},
        ),
      );

      expect(find.text('Off. Nothing is sent to OpenRouter.'), findsOneWidget);
    });

    testWidgets('reports the flip', (WidgetTester tester) async {
      final changes = <bool>[];
      await pumpTall(
        tester,
        SettingsScreen(
          initial: const UnitPreferences(),
          store: InMemoryUnitPreferences(),
          useCoach: true,
          onUseCoachChanged: changes.add,
        ),
      );

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(changes, <bool>[false]);
    });

    testWidgets('offers the disclosure beside the switch', (
      WidgetTester tester,
    ) async {
      await pumpTall(
        tester,
        SettingsScreen(
          initial: const UnitPreferences(),
          store: InMemoryUnitPreferences(),
          useCoach: true,
          onUseCoachChanged: (_) {},
        ),
      );

      await tester.tap(find.text('How your coach uses AI'));
      await tester.pumpAndSettle();

      expect(find.byType(LegalDocumentScreen), findsOneWidget);
      expect(
        find.textContaining('We send your request to OpenRouter'),
        findsOneWidget,
      );
    });
  });

  group('what the switch actually turns off', () {
    testWidgets('off means the mark is absent, not inert', (
      WidgetTester tester,
    ) async {
      // Absent rather than inert is the same call main.dart makes when there is
      // no server. A mark that opens something refusing to answer is worse than
      // no mark.
      await pumpTall(
        tester,
        LiftShell(
          coach: FakeCoach(),
          coachPreference: InMemoryCoachPreference(enabled: false),
        ),
      );

      expect(find.byType(CoachButton), findsNothing);
    });

    testWidgets('on leaves the mark where it was', (WidgetTester tester) async {
      await pumpTall(
        tester,
        LiftShell(
          coach: FakeCoach(),
          coachPreference: InMemoryCoachPreference(),
        ),
      );

      expect(find.byType(CoachButton), findsOneWidget);
    });

    testWidgets('the mark goes as soon as the switch does', (
      WidgetTester tester,
    ) async {
      // The reason the value lives on the shell rather than in Settings: the
      // thing it governs floats over every surface, so flipping it has to reach
      // further than the screen holding the switch.
      final store = InMemoryCoachPreference();
      await pumpTall(
        tester,
        LiftShell(coach: FakeCoach(), coachPreference: store),
      );
      expect(find.byType(CoachButton), findsOneWidget);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      // Persisted on the way out, not on the way back in.
      expect(store.enabled, isFalse);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(CoachButton), findsNothing);
    });

    testWidgets('Plan says who turned it off, not that the signal is bad', (
      WidgetTester tester,
    ) async {
      // Building a plan is an AI request, so the switch reaches it. The note
      // under the disabled button has to name the real reason: sending somebody
      // to check their connection over a setting they chose is a small lie the
      // screen tells confidently.
      await pumpTall(
        tester,
        LiftShell(
          coach: FakeCoach(),
          planner: FakePlanner(),
          isEntitled: true,
          coachPreference: InMemoryCoachPreference(enabled: false),
        ),
      );

      await tester.tap(find.text('Plan'));
      await tester.pumpAndSettle();

      expect(find.textContaining('The AI coach is off'), findsOneWidget);
      expect(find.textContaining('needs a connection'), findsNothing);
    });

    testWidgets('a build with no store keeps the coach and hides the switch', (
      WidgetTester tester,
    ) async {
      await pumpTall(tester, LiftShell(coach: FakeCoach()));

      expect(find.byType(CoachButton), findsOneWidget);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Use the AI coach'), findsNothing);
    });
  });
}
