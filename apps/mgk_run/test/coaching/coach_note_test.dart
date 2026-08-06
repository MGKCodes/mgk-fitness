import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_note.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

RunSummary run({
  required DateTime at,
  required double meters,
  double? paceSecondsPerKm,
  Duration duration = const Duration(minutes: 30),
}) => RunSummary(
  startedAt: at,
  duration: duration,
  distanceMeters: meters,
  avgPaceSecondsPerKm: paceSecondsPerKm,
);

void main() {
  final now = DateTime(2026, 7, 26);

  test('nothing to say about no runs', () {
    expect(CoachNote.forRuns(const <RunSummary>[], now: now), isNull);
  });

  test('a first run is acknowledged as one', () {
    final note = CoachNote.forRuns(<RunSummary>[
      run(at: now, meters: 5000),
    ], now: now);
    expect(note?.kind, CoachNoteKind.milestone);
    expect(note?.detail, contains('first'));
  });

  test('a pace record is the loudest thing the coach can say', () {
    final note = CoachNote.forRuns(<RunSummary>[
      run(
        at: now.subtract(const Duration(days: 7)),
        meters: 5000,
        paceSecondsPerKm: 330,
      ),
      run(at: now, meters: 5000, paceSecondsPerKm: 300),
    ], now: now);
    expect(note?.kind, CoachNoteKind.record);
    expect(note?.headline, contains('Fastest'));
  });

  // A sprint for a bus must not stand as a lifetime best.
  test('a very short run cannot set a pace record', () {
    final note = CoachNote.forRuns(<RunSummary>[
      run(
        at: now.subtract(const Duration(days: 7)),
        meters: 5000,
        paceSecondsPerKm: 330,
      ),
      run(at: now, meters: 200, paceSecondsPerKm: 200),
    ], now: now);
    expect(note?.headline, isNot(contains('Fastest')));
  });

  test('a distance record is recognised', () {
    final note = CoachNote.forRuns(<RunSummary>[
      run(
        at: now.subtract(const Duration(days: 6)),
        meters: 5000,
        paceSecondsPerKm: 300,
      ),
      run(at: now, meters: 12000, paceSecondsPerKm: 330),
    ], now: now);
    expect(note?.kind, CoachNoteKind.record);
    expect(note?.headline, contains('Longest'));
  });

  // These three used to assert "Strong month", "You're turning up" and "Been a
  // while". Home draws all three now — the volume chart is the month, and the
  // consistency grid is both turning up and the gap, under a heading that read
  // *Turning up* directly beneath a note saying the same words (ADR-0017). What
  // is left is what a chart cannot show, so silence is the correct answer where
  // there is no first and no record.
  test('says nothing where the charts already say it', () {
    // Same distance and pace throughout, so nothing is a best — four runs that
    // once produced a consistency note.
    final runs = <RunSummary>[
      for (var d = 1; d <= 4; d++)
        run(
          at: now.subtract(Duration(days: d)),
          meters: 5000,
          paceSecondsPerKm: 300,
        ),
    ];
    expect(
      CoachNote.forRuns(runs, now: now),
      isNull,
      reason: 'the grid above it already shows four runs in a week',
    );
  });

  test('a long absence belongs to the grid, not a nudge', () {
    final note = CoachNote.forRuns(<RunSummary>[
      run(
        at: now.subtract(const Duration(days: 40)),
        meters: 9000,
        paceSecondsPerKm: 300,
      ),
      run(
        at: now.subtract(const Duration(days: 30)),
        meters: 5000,
        paceSecondsPerKm: 320,
      ),
    ], now: now);
    expect(note, isNull);
  });

  test('a high-volume month is no longer remarked on', () {
    final runs = <RunSummary>[
      for (var d = 1; d <= 8; d++)
        run(
          at: now.subtract(Duration(days: d)),
          meters: 8000,
          paceSecondsPerKm: 300,
        ),
    ];
    expect(CoachNote.forRuns(runs, now: now), isNull);
  });

  // The point of deriving these rather than generating them: every claim has to
  // be checkable against the runs behind it.
  test('never claims a record the runs do not support', () {
    final runs = <RunSummary>[
      run(
        at: now.subtract(const Duration(days: 3)),
        meters: 10000,
        paceSecondsPerKm: 280,
      ),
      run(
        at: now.subtract(const Duration(days: 1)),
        meters: 5000,
        paceSecondsPerKm: 340,
      ),
    ];
    final note = CoachNote.forRuns(runs, now: now);
    expect(note?.kind, isNot(CoachNoteKind.record));
  });

  // Regression: CoachNote claimed "Longest one yet" on a strict >, while
  // RunNote required 5% and 200 m. So the home page congratulated a runner on
  // a metre that the run summary, looking at the same run, refused to count.
  test('a metre further is not a record on either surface', () {
    final note = CoachNote.forRuns(<RunSummary>[
      run(
        at: now.subtract(const Duration(days: 7)),
        meters: 10000,
        paceSecondsPerKm: 300,
      ),
      run(at: now, meters: 10001, paceSecondsPerKm: 320),
    ], now: now);
    expect(note?.headline, isNot(contains('Longest')));
  });

  test('a genuine distance record still lands', () {
    final note = CoachNote.forRuns(<RunSummary>[
      run(
        at: now.subtract(const Duration(days: 7)),
        meters: 10000,
        paceSecondsPerKm: 300,
      ),
      run(at: now, meters: 14000, paceSecondsPerKm: 330),
    ], now: now);
    expect(note?.headline, contains('Longest'));
  });

  // Rule 4: metric is stored, the unit layer converts at display. This detail
  // hardcoded "km" and so lied to a runner reading in miles.
}
