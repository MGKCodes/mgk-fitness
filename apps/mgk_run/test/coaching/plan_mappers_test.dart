import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/plan_mappers.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/week_progress.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

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

  group('what already happened goes up as four instructions', () {
    // 2026-07-27 is a Monday. Monday run as prescribed, Tuesday missed, 12 km
    // on the Wednesday the plan asked nothing of, Sunday still to come.
    final monday = DateTime(2026, 7, 27);
    final week = const TrainingWeek(
      skeletonIndex: 6,
      sessions: <PlannedSession>[
        PlannedSession(
          weekday: DateTime.monday,
          kind: SessionKind.easy,
          distanceMeters: 8000,
        ),
        PlannedSession(
          weekday: DateTime.tuesday,
          kind: SessionKind.threshold,
          distanceMeters: 10000,
        ),
        PlannedSession(
          weekday: DateTime.sunday,
          kind: SessionKind.long,
          distanceMeters: 17000,
        ),
      ],
    );
    final soFar = weekAsRun(
      week: week,
      weekStart: monday,
      now: monday.add(const Duration(days: 3)),
      runs: <RunSummary>[
        RunSummary(
          startedAt: monday,
          duration: const Duration(minutes: 41),
          distanceMeters: 8200,
        ),
        RunSummary(
          startedAt: monday.add(const Duration(days: 2)),
          duration: const Duration(minutes: 61),
          distanceMeters: 12000,
        ),
      ],
      since: monday,
    );
    final json = weekAsRunToJson(soFar);

    test(
      'a completed session carries both what was asked and what was run',
      () {
        // A run completes the day at any distance, so the two legitimately
        // differ — and the model should see both rather than assume the
        // prescription was met to the metre.
        expect(json['done'], <Map<String, dynamic>>[
          <String, dynamic>{
            'weekday': DateTime.monday,
            'kind': 'easy',
            'distance_meters': 8000.0,
            'ran_meters': 8200.0,
          },
        ]);
      },
    );

    test('a run the plan never asked for is its own list', () {
      // The case the whole payload exists for. It is not a completed session,
      // and calling it one would have the plan claim a run it never wrote.
      expect(json['unplanned'], <Map<String, dynamic>>[
        <String, dynamic>{'weekday': DateTime.wednesday, 'ran_meters': 12000.0},
      ]);
    });

    test('what went and what is left are kept apart', () {
      expect((json['missed']! as List<dynamic>).single, <String, dynamic>{
        'weekday': DateTime.tuesday,
        'kind': 'threshold',
        'distance_meters': 10000.0,
      });
      expect((json['remaining']! as List<dynamic>).single, <String, dynamic>{
        'weekday': DateTime.sunday,
        'kind': 'long',
        'distance_meters': 17000.0,
      });
    });

    test('and the week total saves the model adding the lists up', () {
      expect(json['ran_meters'], 20200.0);
    });
  });
}
