import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The year both apps draw: Run's runs and Lift's sessions on one grid, so the
/// one account's two apps keep one picture of a year.
void main() {
  // Two weeks, Monday 3 to Sunday 16 August 2026, with today the Wednesday of
  // the second: a day trained, a day missed, today, and days to come.
  final today = DateTime(2026, 8, 12);
  List<List<ActivityYearDay>> weeks() => <List<ActivityYearDay>>[
    for (var w = 0; w < 2; w++)
      <ActivityYearDay>[
        for (var d = 0; d < 7; d++)
          () {
            final date = DateTime(2026, 8, 3 + w * 7 + d);
            final active = date == DateTime(2026, 8, 5);
            return ActivityYearDay(
              date: date,
              active: active,
              isFuture: date.isAfter(today),
              isToday: date == today,
              detail: active ? '2830 kg' : null,
            );
          }(),
      ],
  ];

  Future<void> pump(WidgetTester tester, {String summary = '1 day'}) async {
    await tester.binding.setSurfaceSize(const Size(393, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ActivityYearGrid(
            weeks: weeks(),
            summary: summary,
            activeLabel: 'Trained',
            inactiveDetail: 'rest day',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('is headed The year, with the summary it is given', (
    tester,
  ) async {
    await pump(tester, summary: '1 day trained · 2830 kg');

    expect(find.text('THE YEAR'), findsOneWidget);
    expect(find.text('1 day trained · 2830 kg'), findsOneWidget);
  });

  testWidgets('names three of the seven days, and the month', (tester) async {
    await pump(tester);

    expect(find.text('M'), findsOneWidget);
    expect(find.text('W'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
    expect(find.text('Aug'), findsOneWidget);
  });

  testWidgets('carries a two-entry key in the app\'s own word', (tester) async {
    await pump(tester);

    expect(find.text('Trained'), findsOneWidget);
    expect(find.text('Rest'), findsOneWidget);
  });

  testWidgets('a tapped day says what it held', (tester) async {
    await pump(tester);

    await tester.tap(find.bySemanticsLabel('5/8: 2830 kg'));
    await tester.pumpAndSettle();
    expect(find.text('5 Aug 2026 · 2830 kg'), findsOneWidget);
    // The key gives way to the readout.
    expect(find.text('Trained'), findsNothing);

    await tester.tap(find.bySemanticsLabel('6/8: rest day'));
    await tester.pumpAndSettle();
    expect(find.text('6 Aug 2026 · rest day'), findsOneWidget);
  });

  testWidgets('a day to come cannot be picked', (tester) async {
    await pump(tester);

    await tester.tap(
      find.bySemanticsLabel('14/8: rest day'),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('14 Aug'), findsNothing);
    expect(find.text('Trained'), findsOneWidget);
  });
}
