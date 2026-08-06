import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/adaptation_service.dart';
import 'package:mgk_run/src/features/coaching/data/plan_client.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_adjust_sheet.dart';

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
  );
  final slot = buildSkeleton(profile, now: now, weeks: 12).weeks[5];
  final base = buildFallbackWeek(slot, profile);

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

  Future<TrainingWeek?> openSheet(
    WidgetTester tester,
    TrainingWeek? revised,
  ) async {
    TrainingWeek? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showModalBottomSheet<TrainingWeek>(
                    context: context,
                    builder: (_) => WeekAdjustSheet(
                      adaptation: AdaptationService(
                        client: _RevClient(revised),
                      ),
                      week: base,
                      slot: slot,
                      profile: profile,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('ask -> diff -> apply pops the revised week', (tester) async {
    TrainingWeek? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await showModalBottomSheet<TrainingWeek>(
                    context: context,
                    builder: (_) => WeekAdjustSheet(
                      adaptation: AdaptationService(
                        client: _RevClient(validRevision()),
                      ),
                      week: base,
                      slot: slot,
                      profile: profile,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'shorter tuesday');
    await tester.tap(find.text('Ask the coach'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    expect(find.text('Apply'), findsOneWidget);
    expect(find.textContaining('→'), findsWidgets); // diff rows

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(popped, isNotNull);
  });

  testWidgets('a failed adaptation shows a retry message', (tester) async {
    await openSheet(tester, null); // client returns null -> no proposal

    await tester.enterText(find.byType(TextField), 'do something impossible');
    await tester.tap(find.text('Ask the coach'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    expect(find.textContaining("couldn't adjust"), findsOneWidget);
    expect(find.text('Apply'), findsNothing);
  });
}
