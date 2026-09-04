import 'package:mgk_run/src/features/coaching/data/plan_client.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';

/// A scripted, offline [PlanClient] for the web preview. Generation isn't wired
/// through it (the preview builds plans deterministically), but adaptation is:
/// it returns a small valid revision so the adjust flow can be exercised with no
/// key. The request text is ignored — the point is the diff → approve → apply UI.
class FakePlanClient implements PlanClient {
  @override
  Future<TrainingWeek?> proposeAdaptation({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final sessions = week.sessions.toList();
    final easy = <int>[
      for (var i = 0; i < sessions.length; i++)
        if (sessions[i].kind == SessionKind.easy) i,
    ];
    if (easy.length < 2) return null;
    // Shift 1 km between two easy days: total unchanged, still valid.
    sessions[easy[0]] = PlannedSession(
      weekday: sessions[easy[0]].weekday,
      kind: SessionKind.easy,
      distanceMeters: sessions[easy[0]].distanceMeters - 1000,
    );
    sessions[easy[1]] = PlannedSession(
      weekday: sessions[easy[1]].weekday,
      kind: SessionKind.easy,
      distanceMeters: sessions[easy[1]].distanceMeters + 1000,
    );
    return TrainingWeek(skeletonIndex: week.skeletonIndex, sessions: sessions);
  }

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
