import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/profile/presentation/year_activity_grid.dart';
import 'package:mgk_lift/src/features/stats/domain/activity_window.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_ui/mgk_ui.dart';

Session lifted(DateTime day, {Duration length = const Duration(hours: 1)}) =>
    Session(
      id: '${day.toIso8601String()}-${length.inMinutes}',
      name: 'Session',
      startedAt: day,
      endedAt: day.add(length),
    );

ActivityDay day({bool future = false, Duration? trained, int? tier}) =>
    ActivityDay(
      date: DateTime(2026, 8, 19),
      isFuture: future,
      trained: trained,
      tier: tier,
    );

Widget wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 360, child: child)),
);

final DateTime monday = DateTime(2026, 8, 24);

void main() {
  group('what a square is painted', () {
    test('a day that has not arrived is not painted at all', () {
      expect(YearActivityGrid.cellColour(day(future: true)), isNull);
    });

    test('a rest day is the elevated surface, not a faint white', () {
      // The floor of the ramp is 40% white, so a rest day drawn as a lighter
      // white would sit on the same scale as a trained one and read as a very
      // short session.
      expect(YearActivityGrid.cellColour(day()), AppColors.elevated);
    });

    test('the five tiers are white at 40% through 100%', () {
      for (var tier = 0; tier < ActivityWindow.tiers; tier++) {
        final colour = YearActivityGrid.cellColour(
          day(trained: const Duration(minutes: 45), tier: tier),
        );
        expect(colour, isNotNull);
        expect(colour!.r, 1);
        expect(colour.g, 1);
        expect(colour.b, 1);
        expect(colour.a, closeTo(YearActivityGrid.tierOpacities[tier], 0.001));
      }

      expect(YearActivityGrid.tierOpacities, <double>[0.4, 0.55, 0.7, 0.85, 1]);
    });
  });

  group('the grid', () {
    testWidgets('an empty year says what will fill it', (
      WidgetTester tester,
    ) async {
      // The state a new lifter meets. A year of empty squares captioned "no
      // days trained" reads as a year of failure; the same squares captioned
      // with what they are for read as a thing waiting to start.
      await tester.pumpWidget(
        wrap(
          YearActivityGrid(
            window: ActivityWindow.from(const <Session>[], now: monday),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Every day you train fills a square.'), findsOneWidget);
    });

    testWidgets('a filled year counts its days and says what shade means', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          YearActivityGrid(
            window: ActivityWindow.from(<Session>[
              lifted(DateTime(2026, 8, 17)),
              lifted(DateTime(2026, 8, 19)),
            ], now: monday),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 days trained · darker is longer'), findsOneWidget);
    });

    testWidgets('one day is not "1 days"', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          YearActivityGrid(
            window: ActivityWindow.from(<Session>[
              lifted(DateTime(2026, 8, 17)),
            ], now: monday),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 day trained · darker is longer'), findsOneWidget);
    });

    testWidgets('the months are labelled above the squares', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          YearActivityGrid(
            window: ActivityWindow.from(const <Session>[], now: monday),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Twelve months in the window; the ones near the right edge are dropped
      // rather than clipped mid-word, so this is a floor rather than a count.
      expect(find.text('JAN'), findsOneWidget);
      expect(find.text('SEP'), findsOneWidget);
    });

    testWidgets('the grid fits the width it is given', (
      WidgetTester tester,
    ) async {
      // 52 columns rarely divide a phone evenly. Found by pumping it: an
      // integer square size leaves a visible gutter down the right of the card.
      await tester.pumpWidget(
        wrap(
          YearActivityGrid(
            window: ActivityWindow.from(const <Session>[], now: monday),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final grid = tester.getSize(find.byType(YearActivityGrid));
      expect(grid.width, 360);
      expect(tester.takeException(), isNull);
    });
  });
}
