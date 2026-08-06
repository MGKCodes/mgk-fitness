import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/plan_mappers.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';

void main() {
  final now = DateTime(2026, 7, 25);
  final profile = RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 1),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{7, 1, 4, 2, 6},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  test('runnerProfileToJson encodes metric and sorts weekdays', () {
    final json = runnerProfileToJson(profile);
    expect(json['goal_distance_meters'], 42195);
    expect(json['event_date'], '2026-11-01');
    expect(json['available_weekdays'], <int>[1, 2, 4, 6, 7]);
    expect(json['time_trial_seconds'], 22 * 60);
    expect(json['injury_notes'], isNull); // dropped, not present
    expect(json.containsKey('injury_notes'), isFalse);
  });

  test('a skeleton round-trips through JSON', () {
    final skeleton = buildSkeleton(profile, now: now, weeks: 12);
    final json = <String, dynamic>{
      'weeks': <Map<String, dynamic>>[
        for (final w in skeleton.weeks) skeletonWeekToJson(w),
      ],
    };

    final parsed = planSkeletonFromJson(json);
    expect(parsed, isNotNull);
    expect(parsed!.weeks.length, skeleton.weeks.length);
    for (var i = 0; i < skeleton.weeks.length; i++) {
      final a = skeleton.weeks[i];
      final b = parsed.weeks[i];
      expect(b.index, a.index);
      expect(b.phase, a.phase);
      expect(b.volumeMeters, closeTo(a.volumeMeters, 0.001));
      expect(b.longRunMeters, closeTo(a.longRunMeters, 0.001));
      expect(b.isDeload, a.isDeload);
    }
  });

  test('planSkeletonFromJson returns null on malformed input', () {
    expect(planSkeletonFromJson(<String, dynamic>{}), isNull);
    expect(
      planSkeletonFromJson(<String, dynamic>{'weeks': <dynamic>[]}),
      isNull,
    );
    expect(
      planSkeletonFromJson(<String, dynamic>{
        'weeks': <dynamic>[
          {'phase': 'nonsense', 'volume_meters': 1, 'long_run_meters': 1},
        ],
      }),
      isNull,
    );
  });

  test('trainingWeekFromJson parses sessions incl. marathon_pace', () {
    final week = trainingWeekFromJson(<String, dynamic>{
      'sessions': <dynamic>[
        {'weekday': 1, 'kind': 'threshold', 'distance_meters': 9000},
        {'weekday': 6, 'kind': 'marathon_pace', 'distance_meters': 16000},
        {'weekday': 7, 'kind': 'long', 'distance_meters': 20000},
      ],
    }, skeletonIndex: 6);

    expect(week, isNotNull);
    expect(week!.skeletonIndex, 6);
    expect(week.sessions, hasLength(3));
    expect(week.sessions[1].kind, SessionKind.marathonPace);
    expect(week.provisional, isFalse); // came from the model
  });

  test('trainingWeekFromJson returns null on a bad weekday or kind', () {
    expect(
      trainingWeekFromJson(<String, dynamic>{
        'sessions': <dynamic>[
          {'weekday': 9, 'kind': 'easy', 'distance_meters': 8000},
        ],
      }, skeletonIndex: 1),
      isNull,
    );
    expect(
      trainingWeekFromJson(<String, dynamic>{
        'sessions': <dynamic>[
          {'weekday': 1, 'kind': 'sprint', 'distance_meters': 8000},
        ],
      }, skeletonIndex: 1),
      isNull,
    );
  });

  test('session kind wire strings round-trip', () {
    for (final kind in SessionKind.values) {
      expect(sessionKindFromWire(sessionKindToWire(kind)), kind);
    }
  });
}
