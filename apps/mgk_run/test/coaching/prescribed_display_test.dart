import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_run/src/features/coaching/data/adaptation_service.dart';
import 'package:mgk_run/src/features/coaching/data/plan_client.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/session_status.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/week_adaptation.dart';
import 'package:mgk_run/src/features/coaching/domain/week_progress.dart';
import 'package:mgk_run/src/features/coaching/presentation/chat_entry.dart';
import 'package:mgk_run/src/features/coaching/presentation/chat_widgets.dart';
import 'package:mgk_run/src/features/coaching/presentation/session_brief_sheet.dart';
import 'package:mgk_run/src/features/coaching/presentation/today_card.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_adjust_sheet.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_calendar.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_detail_screen.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_list.dart';
import 'package:mgk_run/src/features/home/presentation/home_tab.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_run/src/features/recording/presentation/run_start_screen.dart';

/// **No surface renders a prescribed distance with a decimal in it.**
///
/// The bug this exists for: `formatPrescribed` said "4 km" and nine other call
/// sites said "4.1 km", because each one reached past it for
/// `Distance.meters(...).format(unit, fractionDigits: 1)`. Plan and Home
/// disagreed about the same Tuesday, eight pixels and one tab apart.
///
/// So this is written against the *rendered text* rather than against the
/// formatter. A tenth call site that formats a session by hand is a new bug of
/// exactly the old shape, and a test on `formatPrescribed` would not see it —
/// it would still be returning "4 km" to the three widgets that call it.
///
/// Both units, because rounding to a whole kilometre is not rounding to a whole
/// mile: a session stored as 7,000 m is round in metric and 4.35 in imperial,
/// so a surface can be correct in one and wrong in the other.
///
/// Deliberately fed distances that are **not** on the prescribed grid. Sessions
/// are generated onto it (`plan_builder.dart`), but a week proposed by the
/// model or restored from an older plan arrives however it arrives, and the
/// display is what has to hold the line.
void main() {
  /// "6.2 km", "3.9 mi" — a distance with a decimal point in it, in either
  /// unit. A pace ("5:12 /km") does not match, which is the point of anchoring
  /// on the decimal separator rather than on the suffix.
  final decimalDistance = RegExp(r'\d+[.,]\d+\s*(km|mi)\b');

  void expectNoDecimals(WidgetTester tester, String where) {
    final rendered = <String>[
      for (final text in tester.widgetList<Text>(
        find.byType(Text, skipOffstage: false),
      ))
        text.data ?? text.textSpan?.toPlainText() ?? '',
    ];
    final offenders = rendered
        .where(decimalDistance.hasMatch)
        .toList(growable: false);
    expect(
      offenders,
      isEmpty,
      reason:
          '$where shows a prescribed distance to a decimal: $offenders. '
          'Use formatPrescribed / prescribedValue rather than '
          'Distance.format(unit, fractionDigits: 1).',
    );
  }

  // None of these sit on the whole-kilometre grid, and none of them convert to
  // a whole number of miles either.
  const monday = PlannedSession(
    weekday: DateTime.monday,
    kind: SessionKind.easy,
    distanceMeters: 6249,
  );
  const wednesday = PlannedSession(
    weekday: DateTime.wednesday,
    kind: SessionKind.threshold,
    distanceMeters: 8900,
  );
  const friday = PlannedSession(
    weekday: DateTime.friday,
    kind: SessionKind.easy,
    distanceMeters: 4137,
  );
  const sunday = PlannedSession(
    weekday: DateTime.sunday,
    kind: SessionKind.long,
    distanceMeters: 12480,
  );

  const week = TrainingWeek(
    skeletonIndex: 3,
    sessions: <PlannedSession>[monday, wednesday, friday, sunday],
  );
  const slot = SkeletonWeek(
    index: 3,
    phase: Phase.build,
    volumeMeters: 31766,
    longRunMeters: 12480,
  );
  final weekStart = DateTime(2026, 8, 24); // a Monday

  final paces = TrainingPaces.fromRace(
    Distance.meters(5000),
    const Duration(minutes: 22),
  );

  Future<void> pump(WidgetTester tester, Widget body) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));

  for (final unit in UnitSystem.values) {
    final name = unit.isMetric ? 'metric' : 'imperial';

    group('in $name', () {
      // Board R24: "6.00 km · easy" on the start screen, one tap after Home
      // said "6 km".
      testWidgets('the start screen', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: RunStartScreen(
              onStart: () {},
              plannedSession: monday,
              unit: unit,
            ),
          ),
        );
        await tester.pump();
        expectNoDecimals(tester, 'The start screen');
        if (unit.isMetric) {
          expect(find.text('6 km · easy run'), findsOneWidget);
        }
      });

      testWidgets("the Plan tab's week list", (tester) async {
        await pump(
          tester,
          WeekList(week: week, weekStart: weekStart, paces: paces, unit: unit),
        );
        expectNoDecimals(tester, 'WeekList');
      });

      testWidgets('the week calendar', (tester) async {
        await pump(
          tester,
          WeekCalendar(week: week, weekStart: weekStart, unit: unit),
        );
        expectNoDecimals(tester, 'WeekCalendar');
      });

      testWidgets("today's card", (tester) async {
        await pump(
          tester,
          TodayCard(
            session: wednesday,
            phase: Phase.build,
            status: SessionStatus.planned,
            paces: paces,
            unit: unit,
          ),
        );
        expectNoDecimals(tester, 'TodayCard');
      });

      testWidgets('the session brief', (tester) async {
        await pump(
          tester,
          SessionBriefSheet(
            session: sunday,
            date: weekStart.add(const Duration(days: 6)),
            paces: paces,
            unit: unit,
          ),
        );
        expectNoDecimals(tester, 'SessionBriefSheet');
      });

      testWidgets('the week detail screen', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: WeekDetailScreen(
              week: week,
              slot: slot,
              paces: paces,
              unit: unit,
            ),
          ),
        );
        expectNoDecimals(tester, 'WeekDetailScreen');
      });

      // The figure over the button, the button itself, and the "Next · easy
      // 6 km on Friday" line under a rest day. All three were on decimals, and
      // the first two disagreeing with each other is what got noticed.
      testWidgets("Home's session figure, Start button and next-run line", (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: HomeTab(
              onRecord: () {},
              onOpenPlan: () {},
              today: const TodayView(
                slot: slot,
                session: wednesday,
                status: SessionStatus.planned,
                heading: 'Week 3',
              ),
              thisWeek: week,
              unit: unit,
            ),
          ),
        );
        await tester.pump();
        expectNoDecimals(tester, 'HomeTab');
      });

      // Not a widget, but the same rule and the same failure mode: this
      // sentence is shown on Home *and* handed to the coach as the runner's own
      // words, so a decimal in it comes back out of the model's mouth.
      test('the missed-session prompt', () {
        final prompt = missedPromptFor(
          week: week,
          weekStart: weekStart,
          now: weekStart.add(const Duration(days: 7)),
          runs: const <RunSummary>[],
          unit: unit,
        );
        final lines = <String>[
          prompt!.headline,
          prompt.logOpener,
          prompt.adjustOpener,
        ];
        expect(lines.where(decimalDistance.hasMatch), isEmpty);
      });

      testWidgets("the coach's proposal card", (tester) async {
        await pump(
          tester,
          ProposalCard(
            proposal: const ChatProposal(
              week: week,
              changes: <SessionChange>[
                SessionChange(
                  weekday: DateTime.monday,
                  before: monday,
                  after: friday,
                ),
              ],
            ),
            unit: unit,
          ),
        );
        expectNoDecimals(tester, 'ProposalCard');
      });

      testWidgets('the adjust-week diff', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showModalBottomSheet<TrainingWeek>(
                      context: context,
                      builder: (_) => WeekAdjustSheet(
                        adaptation: AdaptationService(
                          client: _RevisingClient(_shifted),
                        ),
                        week: week,
                        slot: slot,
                        profile: _profile,
                        unit: unit,
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'shorter monday');
        await tester.tap(find.text('Ask the coach'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pumpAndSettle();

        // The diff has to actually be on screen, or this proves nothing.
        expect(find.text('Apply'), findsOneWidget);
        expectNoDecimals(tester, 'WeekAdjustSheet');
      });
    });
  }
}

final RunnerProfile _profile = RunnerProfile(
  goalDistanceMeters: 42195,
  eventDate: DateTime(2026, 11, 1),
  currentWeeklyMeters: 31766,
  longestRecentMeters: 12480,
  daysPerWeek: 4,
  availableWeekdays: const <int>{1, 3, 5, 7},
);

/// A kilometre and a bit moved between two easy days: off the grid on purpose,
/// and the week still adds up, so the validator lets it through.
final TrainingWeek _shifted = TrainingWeek(
  skeletonIndex: 3,
  sessions: const <PlannedSession>[
    PlannedSession(
      weekday: DateTime.monday,
      kind: SessionKind.easy,
      distanceMeters: 5000,
    ),
    PlannedSession(
      weekday: DateTime.wednesday,
      kind: SessionKind.threshold,
      distanceMeters: 8900,
    ),
    PlannedSession(
      weekday: DateTime.friday,
      kind: SessionKind.easy,
      distanceMeters: 5386,
    ),
    PlannedSession(
      weekday: DateTime.sunday,
      kind: SessionKind.long,
      distanceMeters: 12480,
    ),
  ],
);

class _RevisingClient implements PlanClient {
  const _RevisingClient(this.revised);

  final TrainingWeek revised;

  @override
  Future<TrainingWeek?> proposeAdaptation({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
  }) async => revised;

  @override
  Future<PlanSkeleton?> proposeSkeleton({
    required RunnerProfile profile,
    List<String> violations = const <String>[],
  }) async => null;

  @override
  Future<TrainingWeek?> proposeWeek({
    required SkeletonWeek slot,
    required RunnerProfile profile,
    List<String> violations = const <String>[],
    int? raceWeekday,
  }) async => null;
}
