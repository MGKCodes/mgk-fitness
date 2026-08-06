import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/history/domain/run_draft.dart';

void main() {
  final now = DateTime(2026, 7, 28, 12);

  RunDraft good({
    DateTime? startedAt,
    Duration duration = const Duration(minutes: 26),
    double distance = 5000,
    String type = kTypeTreadmill,
    int? avgHr,
    int? rpe,
  }) => RunDraft(
    startedAt: startedAt ?? now.subtract(const Duration(hours: 3)),
    duration: duration,
    distanceMeters: distance,
    type: type,
    avgHr: avgHr,
    rpe: rpe,
  );

  Set<String> fieldsOf(RunDraft d) => d.issues(now).map((i) => i.field).toSet();

  test('a plain treadmill 5k is valid', () {
    expect(good().isValid(now), isTrue);
  });

  test('pace is derived, never stored twice', () {
    // 5 km in 26 minutes is 312 s/km. The column is written from this so a run
    // and its pace cannot disagree after an edit.
    expect(good().avgPaceSecondsPerKm, closeTo(312, 0.5));
  });

  test('pace is null until both sides exist', () {
    expect(const RunDraft(distanceMeters: 5000).avgPaceSecondsPerKm, isNull);
    expect(
      const RunDraft(duration: Duration(minutes: 26)).avgPaceSecondsPerKm,
      isNull,
    );
    // Zero distance would divide by zero rather than be "infinitely fast".
    expect(
      const RunDraft(
        distanceMeters: 0,
        duration: Duration(minutes: 26),
      ).avgPaceSecondsPerKm,
      isNull,
    );
  });

  // ---- what an empty draft asks for ----------------------------------------

  test('an empty draft names every missing field, not just the first', () {
    // The form puts each message under its own input, so it needs all of them.
    expect(
      const RunDraft().issues(now).map((i) => i.field),
      containsAll(<String>['started_at', 'distance', 'duration']),
    );
  });

  // ---- the mistakes this actually exists to catch --------------------------

  test('kilometres typed as metres is caught', () {
    // "I ran 30" meaning 30 km, entered as 30 metres, or the reverse. The
    // reverse is the dangerous one: it silently inflates a training log.
    expect(fieldsOf(good(distance: 3000000)), contains('distance'));
  });

  test('a run faster than a world record is refused', () {
    // 5 km in 2 minutes. A model that misheard "26" as "2" produces exactly
    // this, and nobody typed it so nobody would notice.
    expect(
      fieldsOf(good(duration: const Duration(minutes: 2))),
      contains('distance'),
    );
  });

  test('slower than 30 min/km is refused', () {
    expect(
      fieldsOf(good(duration: const Duration(hours: 3))),
      contains('duration'),
    );
  });

  test('one bad field produces one message, not two saying the same thing', () {
    // Zero distance makes the pace check meaningless; reporting both would tell
    // the runner their pace is wrong when what is wrong is the distance.
    final issues = good(distance: 0).issues(now);
    expect(issues.where((i) => i.field == 'distance'), hasLength(1));
    expect(issues.any((i) => i.field == 'duration'), isFalse);
  });

  // ---- time ----------------------------------------------------------------

  test('a run in the future is refused, with slack for a fast clock', () {
    expect(
      fieldsOf(good(startedAt: now.add(const Duration(hours: 2)))),
      contains('started_at'),
    );
    // Two minutes ahead is a device clock, not a claim about tomorrow.
    expect(
      good(startedAt: now.add(const Duration(minutes: 2))).isValid(now),
      isTrue,
    );
  });

  test('a run from six years ago is refused', () {
    expect(
      fieldsOf(good(startedAt: DateTime(2020, 1, 1))),
      contains('started_at'),
    );
  });

  // ---- the loose bounds are loose on purpose -------------------------------

  test('a slow walk-run and a long ultra are both allowed', () {
    // The validator checks plausibility, not whether this counts as running.
    expect(
      good(distance: 1000, duration: const Duration(minutes: 12)).isValid(now),
      isTrue,
    );
    expect(
      good(distance: 100000, duration: const Duration(hours: 14)).isValid(now),
      isTrue,
    );
  });

  // ---- the optional fields -------------------------------------------------

  test('heart rate and effort are checked only when given', () {
    expect(good().isValid(now), isTrue);
    expect(fieldsOf(good(avgHr: 15)), contains('avg_hr'));
    expect(fieldsOf(good(avgHr: 300)), contains('avg_hr'));
    expect(good(avgHr: 150).isValid(now), isTrue);

    expect(fieldsOf(good(rpe: 0)), contains('rpe'));
    expect(fieldsOf(good(rpe: 11)), contains('rpe'));
    expect(good(rpe: 7).isValid(now), isTrue);
  });

  test('an unknown kind of run is refused', () {
    expect(fieldsOf(good(type: 'cycling')), contains('type'));
    for (final t in kRunTypes) {
      expect(good(type: t).isValid(now), isTrue, reason: t);
    }
  });

  test('copyWith changes one field and keeps the rest', () {
    final d = good().copyWith(distanceMeters: 10000);
    expect(d.distanceMeters, 10000);
    expect(d.duration, const Duration(minutes: 26));
    expect(d.type, kTypeTreadmill);
  });
}
