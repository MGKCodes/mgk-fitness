import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_run/src/features/coaching/data/adaptation_service.dart';
import 'package:mgk_run/src/features/coaching/data/plan_client.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_detail_screen.dart';

/// A client whose adaptation always succeeds with [revised].
class _RevClient implements PlanClient {
  _RevClient(this.revised);
  final TrainingWeek? revised;

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
  }) async => null;
}

void main() {
  final now = DateTime(2026, 7, 25);
  final profile = RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 1),
    currentWeeklyMeters: 45000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );
  final slot = buildSkeleton(profile, now: now, weeks: 12).weeks[5];
  final base = buildFallbackWeek(slot, profile);
  final paces = TrainingPaces.fromRace(
    Distance.meters(profile.timeTrialDistanceMeters!),
    profile.timeTrialDuration!,
  );

  /// Moves 500 m between two easy days — a revision the validator accepts.
  TrainingWeek validRevision() {
    final sessions = base.sessions.toList();
    final easy = <int>[
      for (var i = 0; i < sessions.length; i++)
        if (sessions[i].kind == SessionKind.easy) i,
    ];
    sessions[easy[0]] = PlannedSession(
      weekday: sessions[easy[0]].weekday,
      kind: SessionKind.easy,
      distanceMeters: sessions[easy[0]].distanceMeters - 500,
    );
    sessions[easy[1]] = PlannedSession(
      weekday: sessions[easy[1]].weekday,
      kind: SessionKind.easy,
      distanceMeters: sessions[easy[1]].distanceMeters + 500,
    );
    return TrainingWeek(skeletonIndex: slot.index, sessions: sessions);
  }

  /// Drives the screen's adjust flow through to tapping Apply.
  Future<void> adjust(
    WidgetTester tester, {
    required Future<void> Function(TrainingWeek)? onRevised,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeekDetailScreen(
          week: base,
          slot: slot,
          paces: paces,
          profile: profile,
          adaptation: AdaptationService(client: _RevClient(validRevision())),
          onRevised: onRevised,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'shorter tuesday');
    await tester.tap(find.text('Ask the coach'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
  }

  // Regression: the screen used to keep an approved revision in its own state
  // and pop no result, so the change died with the route while the runner was
  // told "Week updated." Nothing caught it because the screen looked correct.
  testWidgets('an approved revision is handed to the caller to persist', (
    tester,
  ) async {
    final saved = <TrainingWeek>[];
    await adjust(tester, onRevised: (w) async => saved.add(w));

    expect(saved, hasLength(1), reason: 'the revision must be persisted');
    expect(saved.single.volumeMeters, closeTo(base.volumeMeters, 1));
    expect(find.text('Week updated.'), findsOneWidget);
  });

  testWidgets('a revision that cannot be saved is not shown as saved', (
    tester,
  ) async {
    await adjust(tester, onRevised: (_) async => throw Exception('disk full'));

    expect(find.text('Week updated.'), findsNothing);
    expect(find.textContaining("Couldn't save"), findsOneWidget);
  });

  testWidgets('with no persistence hook the screen still applies the revision', (
    tester,
  ) async {
    // The static preview and tests pass no hook; the adjust flow must still work.
    await adjust(tester, onRevised: null);
    expect(find.text('Week updated.'), findsOneWidget);
  });

  /// The screen on a phone-sized surface the seven rows do not fit into, which
  /// is the case the focused day exists for.
  Future<void> pumpWeek(WidgetTester tester, {int? focusedWeekday}) async {
    await tester.binding.setSurfaceSize(const Size(400, 460));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: WeekDetailScreen(
          week: base,
          slot: slot,
          paces: paces,
          focusedWeekday: focusedWeekday,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The card behind a day's row.
  AppCard cardFor(WidgetTester tester, String day) => tester.widget<AppCard>(
    find.ancestor(of: find.text(day), matching: find.byType(AppCard)).first,
  );

  testWidgets('the focused day is raised, and only that day', (tester) async {
    await pumpWeek(tester, focusedWeekday: DateTime.thursday);

    // Elevation, not the silver fill that means "today" in the calendar — the
    // two are different facts and must not look like the same one.
    expect(cardFor(tester, 'Thu').color, AppColors.elevated);
    expect(cardFor(tester, 'Thu').color, isNot(AppColors.primary));
    for (final other in <String>['Mon', 'Tue', 'Wed', 'Fri', 'Sat', 'Sun']) {
      expect(cardFor(tester, other).color, isNull, reason: '$other is plain');
    }
  });

  testWidgets('the focused day is scrolled into view', (tester) async {
    await pumpWeek(tester, focusedWeekday: DateTime.sunday);

    final sunday = tester.getRect(find.text('Sun'));
    expect(sunday.top, greaterThanOrEqualTo(0));
    expect(sunday.bottom, lessThanOrEqualTo(460));
  });

  testWidgets(
    'opening the week as a whole focuses nothing and does not scroll',
    (tester) async {
      await pumpWeek(tester);

      for (final day in <String>['Mon', 'Thu', 'Sun']) {
        expect(cardFor(tester, day).color, isNull);
      }
      // Still at the top: nothing was asked for, so nothing moved.
      expect(tester.getRect(find.text('Sun')).top, greaterThan(460));
    },
  );

  testWidgets('an out-of-range weekday costs the emphasis, not the screen', (
    tester,
  ) async {
    await pumpWeek(tester, focusedWeekday: 0);

    expect(find.text('Mon'), findsOneWidget);
    for (final day in <String>['Mon', 'Thu', 'Sun']) {
      expect(cardFor(tester, day).color, isNull);
    }
  });
}
