import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_validator.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';

SkeletonWeek _sw(
  int i,
  Phase phase,
  double volume,
  double longRun, {
  bool deload = false,
}) => SkeletonWeek(
  index: i,
  phase: phase,
  volumeMeters: volume,
  longRunMeters: longRun,
  isDeload: deload,
);

PlanSkeleton _validSkeleton() => PlanSkeleton(
  weeks: <SkeletonWeek>[
    _sw(1, Phase.base, 40000, 12000),
    _sw(2, Phase.base, 43000, 13000),
    _sw(3, Phase.base, 46000, 15000),
    _sw(4, Phase.base, 32000, 11000, deload: true),
    _sw(5, Phase.build, 47000, 15000),
    _sw(6, Phase.build, 50000, 16000),
    _sw(7, Phase.build, 53000, 18000),
    _sw(8, Phase.build, 37000, 12000, deload: true),
    _sw(9, Phase.peak, 54000, 18000),
    _sw(10, Phase.peak, 58000, 20000),
    _sw(11, Phase.taper, 45000, 16000),
    _sw(12, Phase.taper, 32000, 12000),
  ],
);

final _profile = RunnerProfile(
  goalDistanceMeters: 42195,
  eventDate: DateTime(2026, 12, 1),
  currentWeeklyMeters: 40000,
  longestRecentMeters: 18000,
  daysPerWeek: 5,
  availableWeekdays: <int>{
    DateTime.monday,
    DateTime.tuesday,
    DateTime.thursday,
    DateTime.saturday,
    DateTime.sunday,
  },
);

PlanSkeleton _skeletonWith(int index, SkeletonWeek replacement) {
  final weeks = _validSkeleton().weeks.toList();
  weeks[index] = replacement;
  return PlanSkeleton(weeks: weeks);
}

void main() {
  group('validateSkeleton', () {
    test('a well-formed skeleton passes', () {
      final result = validateSkeleton(_validSkeleton(), _profile);
      expect(result.isValid, isTrue, reason: result.violations.toString());
    });

    test('catches week 1 far from current volume', () {
      final result = validateSkeleton(
        _skeletonWith(0, _sw(1, Phase.base, 60000, 12000)),
        _profile,
      );
      expect(result.has('week1_volume'), isTrue);
    });

    test('catches a volume ramp over 10%', () {
      final result = validateSkeleton(
        _skeletonWith(5, _sw(6, Phase.build, 62000, 16000)),
        _profile,
      );
      expect(result.has('volume_ramp'), isTrue);
    });

    test('catches a deload that barely drops', () {
      final result = validateSkeleton(
        _skeletonWith(3, _sw(4, Phase.base, 44000, 11000, deload: true)),
        _profile,
      );
      expect(result.has('deload_volume'), isTrue);
    });

    test('catches a missing taper', () {
      final result = validateSkeleton(
        _skeletonWith(11, _sw(12, Phase.peak, 32000, 12000)),
        _profile,
      );
      expect(result.has('taper_missing'), isTrue);
    });

    test('catches a long run over the ceiling', () {
      final result = validateSkeleton(
        _skeletonWith(9, _sw(10, Phase.peak, 58000, 40000)),
        _profile,
      );
      expect(result.has('long_run_ceiling'), isTrue);
    });
  });

  group('validateWeek', () {
    const slot = SkeletonWeek(
      index: 6,
      phase: Phase.build,
      volumeMeters: 50000,
      longRunMeters: 16000,
    );

    TrainingWeek week(List<PlannedSession> sessions) =>
        TrainingWeek(skeletonIndex: 6, sessions: sessions);

    test('a well-formed week passes', () {
      final result = validateWeek(
        week(const <PlannedSession>[
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
            weekday: DateTime.thursday,
            kind: SessionKind.interval,
            distanceMeters: 9000,
          ),
          PlannedSession(
            weekday: DateTime.saturday,
            kind: SessionKind.long,
            distanceMeters: 16000,
          ),
          PlannedSession(
            weekday: DateTime.sunday,
            kind: SessionKind.easy,
            distanceMeters: 7000,
          ),
        ]),
        slot,
        _profile,
      );
      expect(result.isValid, isTrue, reason: result.violations.toString());
    });

    test('catches a session on an unavailable day', () {
      final result = validateWeek(
        week(const <PlannedSession>[
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
            weekday: DateTime.thursday,
            kind: SessionKind.interval,
            distanceMeters: 9000,
          ),
          PlannedSession(
            weekday: DateTime.saturday,
            kind: SessionKind.long,
            distanceMeters: 16000,
          ),
          PlannedSession(
            weekday: DateTime.wednesday,
            kind: SessionKind.easy,
            distanceMeters: 7000,
          ),
        ]),
        slot,
        _profile,
      );
      expect(result.has('unavailable_day'), isTrue);
    });

    test('catches two hard sessions on consecutive days', () {
      final result = validateWeek(
        week(const <PlannedSession>[
          PlannedSession(
            weekday: DateTime.monday,
            kind: SessionKind.threshold,
            distanceMeters: 10000,
          ),
          PlannedSession(
            weekday: DateTime.tuesday,
            kind: SessionKind.interval,
            distanceMeters: 9000,
          ),
          PlannedSession(
            weekday: DateTime.thursday,
            kind: SessionKind.easy,
            distanceMeters: 8000,
          ),
          PlannedSession(
            weekday: DateTime.saturday,
            kind: SessionKind.long,
            distanceMeters: 16000,
          ),
          PlannedSession(
            weekday: DateTime.sunday,
            kind: SessionKind.easy,
            distanceMeters: 7000,
          ),
        ]),
        slot,
        _profile,
      );
      expect(result.has('back_to_back_hard'), isTrue);
    });

    test('catches a week volume far from its slot', () {
      final result = validateWeek(
        week(const <PlannedSession>[
          PlannedSession(
            weekday: DateTime.monday,
            kind: SessionKind.easy,
            distanceMeters: 14000,
          ),
          PlannedSession(
            weekday: DateTime.tuesday,
            kind: SessionKind.threshold,
            distanceMeters: 14000,
          ),
          PlannedSession(
            weekday: DateTime.thursday,
            kind: SessionKind.interval,
            distanceMeters: 12000,
          ),
          PlannedSession(
            weekday: DateTime.saturday,
            kind: SessionKind.long,
            distanceMeters: 20000,
          ),
          PlannedSession(
            weekday: DateTime.sunday,
            kind: SessionKind.easy,
            distanceMeters: 10000,
          ),
        ]),
        slot,
        _profile,
      );
      expect(result.has('week_volume'), isTrue);
    });

    // Regression: the long run used to be bounded only as a fraction of the
    // week and by an absolute ceiling, never against the slot's own declared
    // long run. A week could therefore satisfy every bound and still contradict
    // the number the plan arc had already shown for that week — which is how a
    // 35%-vs-38% split between the skeleton and the filler went unnoticed.
    test('catches a long run that drifts from the slot it was built for', () {
      final result = validateWeek(
        week(const <PlannedSession>[
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
            weekday: DateTime.thursday,
            kind: SessionKind.interval,
            distanceMeters: 9000,
          ),
          // 8.75% over the slot's 16 000 m — the old 0.38/0.35 discrepancy.
          PlannedSession(
            weekday: DateTime.saturday,
            kind: SessionKind.long,
            distanceMeters: 17400,
          ),
          PlannedSession(
            weekday: DateTime.sunday,
            kind: SessionKind.easy,
            distanceMeters: 5600,
          ),
        ]),
        slot,
        _profile,
      );
      expect(result.has('long_run_slot'), isTrue);
      // The point of the check: the old bounds are all still satisfied here, so
      // nothing else would have flagged it.
      expect(result.has('long_run_fraction'), isFalse);
      expect(result.has('long_run_ceiling'), isFalse);
      expect(result.has('week_volume'), isFalse);
    });

    // The two date rules below are opt-in through `weekStart` (see the
    // function's own doc) and, until EDGE-17, nothing outside this file ever
    // supplied it — plan_service.dart and adaptation_service.dart both call
    // validateWeek without a calendar, so a session on race day or on a day
    // already gone passed every check that could see it. These pin the rules
    // themselves; plan_repository_test.dart and adaptation_service_test.dart
    // cover the wiring.
    test(
      'catches a session on race day once weekStart and the race are given',
      () {
        // This slot's week: Monday 23 -> Sunday 29 March 2026 -- the spring
        // UK clock change itself falls on the Sunday, this week's last day.
        final raceProfile = _profile.copyWith(eventDate: DateTime(2026, 3, 29));
        final result = validateWeek(
          week(const <PlannedSession>[
            PlannedSession(
              weekday: DateTime.monday,
              kind: SessionKind.easy,
              distanceMeters: 8000,
            ),
            PlannedSession(
              weekday: DateTime.sunday,
              kind: SessionKind.long,
              distanceMeters: 16000,
            ),
          ]),
          slot,
          raceProfile,
          weekStart: DateTime(2026, 3, 23),
        );
        expect(result.has('session_on_race_day'), isTrue);
      },
    );

    test(
      "session_in_the_past's day count is DST-safe, not a plain Duration",
      () {
        // weekStart Monday 16 March; `now` a fortnight later, on the other
        // side of the spring change (29 March). `today.difference(on).inDays`
        // — a plain Duration subtraction between two local midnights — reads
        // the 23-hour changeover day as one day short and would say "13
        // day(s) ago" here; `daysBetweenDates` (UTC-normalised) says 14,
        // which is what a calendar says.
        final result = validateWeek(
          week(const <PlannedSession>[
            PlannedSession(
              weekday: DateTime.monday,
              kind: SessionKind.easy,
              distanceMeters: 8000,
            ),
          ]),
          slot,
          _profile,
          weekStart: DateTime(2026, 3, 16),
          now: DateTime(2026, 3, 30),
        );
        expect(result.has('session_in_the_past'), isTrue);
        final message = result.violations
            .firstWhere((v) => v.code == 'session_in_the_past')
            .message;
        expect(message, contains('14 day'));
      },
    );
  });
}
