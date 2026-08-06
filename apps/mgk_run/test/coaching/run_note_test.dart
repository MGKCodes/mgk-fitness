import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/units/unit_system.dart';
import 'package:mgk_run/src/features/coaching/domain/run_note.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/recording/domain/run_split.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// A run, described by the things the note actually reads.
RunSummary run({
  required DateTime at,
  required double meters,
  double? paceSecondsPerKm,
  Duration duration = const Duration(minutes: 30),
  double? elevationGainMeters,
  int? avgHr,
  String type = 'outdoor',
  List<RunSplit> splits = const <RunSplit>[],
}) => RunSummary(
  startedAt: at,
  duration: duration,
  distanceMeters: meters,
  avgPaceSecondsPerKm: paceSecondsPerKm,
  elevationGainMeters: elevationGainMeters,
  avgHr: avgHr,
  type: type,
  splits: splits,
);

/// Kilometre splits from a list of per-kilometre times, with an optional
/// trailing part-kilometre.
List<RunSplit> splits(
  List<int> seconds, {
  double? tailMeters,
  int? tailSeconds,
}) => <RunSplit>[
  for (var i = 0; i < seconds.length; i++)
    RunSplit(
      index: i + 1,
      distanceMeters: 1000,
      duration: Duration(seconds: seconds[i]),
    ),
  if (tailMeters != null && tailSeconds != null)
    RunSplit(
      index: seconds.length + 1,
      distanceMeters: tailMeters,
      duration: Duration(seconds: tailSeconds),
    ),
];

void main() {
  final day = DateTime(2026, 7, 26, 8);
  DateTime daysBefore(int n) => day.subtract(Duration(days: n));

  /// A few unremarkable 5 km runs at an unremarkable pace, in the weeks before.
  List<RunSummary> steadyHistory({
    double meters = 5000,
    double pace = 330,
    int count = 4,
    int? avgHr,
    double? elevationGainMeters,
  }) => <RunSummary>[
    for (var i = 1; i <= count; i++)
      run(
        at: daysBefore(i * 3),
        meters: meters,
        paceSecondsPerKm: pace,
        avgHr: avgHr,
        elevationGainMeters: elevationGainMeters,
      ),
  ];

  group('silence', () {
    test('a run with no context and nothing to say gets no note', () {
      expect(RunNote.forRun(run(at: day, meters: 5000)), isNull);
    });

    test('a zero-distance run is not a divide-by-zero', () {
      expect(
        RunNote.forRun(run(at: day, meters: 0), history: steadyHistory()),
        isNull,
      );
    });

    test('an unremarkable run among unremarkable runs gets no note', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5100, paceSecondsPerKm: 328),
        history: steadyHistory(),
      );
      expect(note, isNull);
    });

    // Absence is normal: a denied HealthKit read looks exactly like a runner
    // who has never worn a strap.
    test('absent heart rate and elevation remove candidates, never error', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5000, paceSecondsPerKm: 330),
        history: steadyHistory(avgHr: 150, elevationGainMeters: 40),
      );
      expect(note, isNull);
    });
  });

  group('distance record', () {
    test('a clear personal best in distance is the loudest thing said', () {
      final note = RunNote.forRun(
        run(at: day, meters: 12000, paceSecondsPerKm: 340),
        history: steadyHistory(),
      );
      expect(note?.kind, RunNoteKind.record);
      expect(note?.headline, contains('Furthest'));
      expect(note?.detail, contains('12.00 km'));
    });

    // The failure this design exists to prevent.
    test('5.2 km after a 5.0 km is not a record at anything', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5200, paceSecondsPerKm: 340),
        history: steadyHistory(),
      );
      expect(note?.headline, isNot(contains('Furthest')));
    });

    test('a 199 m margin over a short prior longest is not a record', () {
      final note = RunNote.forRun(
        run(at: day, meters: 1199, paceSecondsPerKm: 340),
        history: steadyHistory(meters: 1000),
      );
      expect(note?.headline, isNot(contains('Furthest')));
    });

    test('a sub-kilometre effort cannot be a distance record', () {
      final note = RunNote.forRun(
        run(at: day, meters: 800, paceSecondsPerKm: 200),
        history: steadyHistory(meters: 400),
      );
      // It may well be further than they have been going — it is not a record.
      expect(note?.kind, isNot(RunNoteKind.record));
    });

    // A record is a claim about now, so a run that has since been beaten does
    // not still hold one.
    test('a record already beaten by a later run is not claimed', () {
      final note = RunNote.forRun(
        run(at: daysBefore(10), meters: 12000, paceSecondsPerKm: 340),
        history: <RunSummary>[
          ...steadyHistory(),
          run(at: day, meters: 20000, paceSecondsPerKm: 340),
        ],
      );
      expect(note?.headline, isNot(contains('Furthest')));
    });

    test('a manual entry cannot take a record, but still sets the bar', () {
      final typedIn = run(
        at: daysBefore(2),
        meters: 20000,
        paceSecondsPerKm: 340,
        type: 'manual',
      );
      expect(
        RunNote.forRun(typedIn, history: steadyHistory())?.kind,
        isNot(RunNoteKind.record),
      );

      // The same distance, measured, after that manual entry: no longer a best.
      final measured = run(at: day, meters: 20000, paceSecondsPerKm: 340);
      final note = RunNote.forRun(
        measured,
        history: <RunSummary>[...steadyHistory(), typedIn],
      );
      expect(note?.headline, isNot(contains('Furthest')));
    });

    test('the run itself in the passed history is not a rival', () {
      final today = run(at: day, meters: 12000, paceSecondsPerKm: 340);
      final note = RunNote.forRun(
        today,
        history: <RunSummary>[today, ...steadyHistory()],
      );
      expect(note?.headline, contains('Furthest'));
    });
  });

  group('pace record', () {
    test('a clear best over a comparable distance is recognised', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5000, paceSecondsPerKm: 300),
        history: steadyHistory(),
      );
      expect(note?.kind, RunNoteKind.record);
      expect(note?.headline, contains('Quickest'));
      expect(note?.detail, contains('5:00 /km'));
    });

    // A sprint for a bus must not stand as a lifetime best.
    test('a 600 m effort cannot take the pace record', () {
      final note = RunNote.forRun(
        run(at: day, meters: 600, paceSecondsPerKm: 200),
        history: steadyHistory(),
      );
      expect(note, isNull);
    });

    test('a second per kilometre quicker is rounding, not a record', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5000, paceSecondsPerKm: 329),
        history: steadyHistory(),
      );
      expect(note?.headline, isNot(contains('Quickest')));
    });

    test('a fast 3 km is not compared against 10 km runs', () {
      final note = RunNote.forRun(
        run(at: day, meters: 3000, paceSecondsPerKm: 290),
        history: steadyHistory(meters: 10000, pace: 330),
      );
      expect(note?.headline, isNot(contains('Quickest')));
    });

    test('one comparable run is not "every run at this distance"', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5000, paceSecondsPerKm: 300),
        history: <RunSummary>[
          run(at: daysBefore(4), meters: 5000, paceSecondsPerKm: 330),
          run(at: daysBefore(8), meters: 15000, paceSecondsPerKm: 380),
        ],
      );
      expect(note?.headline, isNot(contains('Quickest')));
    });

    test('a distance record outranks a pace record', () {
      final note = RunNote.forRun(
        run(at: day, meters: 12000, paceSecondsPerKm: 250),
        history: <RunSummary>[
          ...steadyHistory(),
          run(at: daysBefore(20), meters: 10000, paceSecondsPerKm: 400),
          run(at: daysBefore(24), meters: 10500, paceSecondsPerKm: 400),
        ],
      );
      expect(note?.headline, contains('Furthest'));
    });
  });

  group('against the session prescribed', () {
    const easy8k = PlannedSession(
      weekday: DateTime.sunday,
      kind: SessionKind.easy,
      distanceMeters: 8000,
    );

    test('the session, run as prescribed', () {
      final note = RunNote.forRun(
        run(at: day, meters: 8200, paceSecondsPerKm: 330),
        planned: easy8k,
      );
      expect(note?.kind, RunNoteKind.plan);
      expect(note?.headline, contains('the session'));
      expect(note?.detail, contains('8.00 km'));
    });

    test('well short of the session is said plainly, without scolding', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5000, paceSecondsPerKm: 330),
        planned: easy8k,
      );
      expect(note?.headline, contains('Short of the session'));
      expect(note?.detail, contains('changes very little'));
    });

    test('well over an easy session is flagged as exactly that', () {
      final note = RunNote.forRun(
        run(at: day, meters: 12000, paceSecondsPerKm: 330),
        planned: easy8k,
      );
      expect(note?.headline, contains('More than the session'));
      expect(note?.detail, contains('Easy days'));
    });

    test('15% over is neither the session nor a deviation worth naming', () {
      final note = RunNote.forRun(
        run(at: day, meters: 9200, paceSecondsPerKm: 330),
        planned: easy8k,
      );
      expect(note, isNull);
    });

    test('a rest day prescribes nothing to compare against', () {
      final note = RunNote.forRun(
        run(at: day, meters: 8000, paceSecondsPerKm: 330),
        planned: const PlannedSession(
          weekday: DateTime.sunday,
          kind: SessionKind.rest,
        ),
      );
      expect(note, isNull);
    });

    test('a session with no distance prescribes nothing either', () {
      final note = RunNote.forRun(
        run(at: day, meters: 8000, paceSecondsPerKm: 330),
        planned: const PlannedSession(
          weekday: DateTime.sunday,
          kind: SessionKind.interval,
        ),
      );
      expect(note, isNull);
    });

    test('missing the session outranks how it was paced', () {
      final note = RunNote.forRun(
        run(
          at: day,
          meters: 5000,
          paceSecondsPerKm: 330,
          splits: splits(<int>[340, 340, 320, 320, 320]),
        ),
        planned: easy8k,
      );
      expect(note?.headline, contains('Short of the session'));
    });

    test('how it was paced outranks hitting the session', () {
      final note = RunNote.forRun(
        run(
          at: day,
          meters: 8000,
          paceSecondsPerKm: 330,
          splits: splits(<int>[345, 340, 320, 315]),
        ),
        planned: easy8k,
      );
      expect(note?.kind, RunNoteKind.pacing);
    });
  });

  group('how the run was paced', () {
    test('a negative split is recognised', () {
      final note = RunNote.forRun(
        run(
          at: day,
          meters: 6000,
          paceSecondsPerKm: 330,
          splits: splits(<int>[345, 340, 335, 320, 315, 310]),
        ),
      );
      expect(note?.kind, RunNoteKind.pacing);
      expect(note?.headline, contains('finished faster'));
      expect(note?.detail, contains('First half'));
    });

    test('a fade is recognised', () {
      final note = RunNote.forRun(
        run(
          at: day,
          meters: 6000,
          paceSecondsPerKm: 330,
          splits: splits(<int>[310, 315, 320, 335, 340, 345]),
        ),
      );
      expect(note?.headline, contains('faded'));
    });

    // "A run with two splits does not have a meaningful pacing story."
    test('two splits are not a pacing story', () {
      final note = RunNote.forRun(
        run(
          at: day,
          meters: 2000,
          paceSecondsPerKm: 330,
          splits: splits(<int>[350, 310]),
        ),
      );
      expect(note, isNull);
    });

    test('three splits are not one either', () {
      final note = RunNote.forRun(
        run(
          at: day,
          meters: 3000,
          paceSecondsPerKm: 330,
          splits: splits(<int>[350, 330, 310]),
        ),
      );
      expect(note, isNull);
    });

    test('an evenly run run says nothing about its pacing', () {
      final note = RunNote.forRun(
        run(
          at: day,
          meters: 5000,
          paceSecondsPerKm: 330,
          splits: splits(<int>[330, 332, 329, 331, 330]),
        ),
      );
      expect(note, isNull);
    });

    // A 200 m tail run at walking pace is not a fade — it is a short split.
    test('a trailing part-kilometre cannot invent a fade', () {
      final note = RunNote.forRun(
        run(
          at: day,
          meters: 4200,
          paceSecondsPerKm: 330,
          splits: splits(
            <int>[330, 331, 330, 329],
            tailMeters: 200,
            tailSeconds: 110,
          ),
        ),
      );
      expect(note, isNull);
    });

    test('an odd number of splits drops the middle one', () {
      // Halves are 1-2 and 4-5; the slow third kilometre must not count twice.
      final note = RunNote.forRun(
        run(
          at: day,
          meters: 5000,
          paceSecondsPerKm: 330,
          splits: splits(<int>[340, 338, 400, 322, 320]),
        ),
      );
      expect(note?.headline, contains('finished faster'));
    });
  });

  group('heart rate', () {
    test('the same pace at a lower heart rate is worth saying', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5000, paceSecondsPerKm: 330, avgHr: 143),
        history: steadyHistory(avgHr: 152),
      );
      expect(note?.kind, RunNoteKind.effort);
      expect(note?.headline, contains('lower heart rate'));
    });

    test('a slower run at a lower heart rate is just a slower run', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5000, paceSecondsPerKm: 360, avgHr: 140),
        history: steadyHistory(avgHr: 152),
      );
      expect(note?.kind, isNot(RunNoteKind.effort));
    });

    test('two beats lower is not a lower heart rate', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5000, paceSecondsPerKm: 330, avgHr: 150),
        history: steadyHistory(avgHr: 152),
      );
      expect(note?.kind, isNot(RunNoteKind.effort));
    });

    test('no heart rate on the run is silence, not a claim', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5000, paceSecondsPerKm: 330),
        history: steadyHistory(avgHr: 152),
      );
      expect(note?.kind, isNot(RunNoteKind.effort));
    });

    test('no heart rate in the history is silence too', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5000, paceSecondsPerKm: 330, avgHr: 130),
        history: steadyHistory(),
      );
      expect(note?.kind, isNot(RunNoteKind.effort));
    });
  });

  group('terrain', () {
    test('a hilly run against flat recent ones is named', () {
      final note = RunNote.forRun(
        run(
          at: day,
          meters: 5000,
          paceSecondsPerKm: 330,
          elevationGainMeters: 220,
        ),
        history: steadyHistory(elevationGainMeters: 25),
      );
      expect(note?.kind, RunNoteKind.terrain);
      expect(note?.detail, contains('climbing'));
    });

    test('a hilly runner’s usual hilly run is not news', () {
      final note = RunNote.forRun(
        run(
          at: day,
          meters: 5000,
          paceSecondsPerKm: 330,
          elevationGainMeters: 120,
        ),
        history: steadyHistory(elevationGainMeters: 110),
      );
      expect(note?.kind, isNot(RunNoteKind.terrain));
    });

    test('elevation nobody recorded is not a flat route', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5000, paceSecondsPerKm: 330),
        history: steadyHistory(elevationGainMeters: 5),
      );
      expect(note?.kind, isNot(RunNoteKind.terrain));
    });

    test('a hill is never called an easy run', () {
      // Slower than usual, but only because it went up: the pace note would be
      // a false read, so terrain takes it.
      final note = RunNote.forRun(
        run(
          at: day,
          meters: 5000,
          paceSecondsPerKm: 400,
          elevationGainMeters: 200,
        ),
        history: steadyHistory(elevationGainMeters: 20),
      );
      expect(note?.headline, isNot(contains('easier')));
    });

    test('a hill with no history to compare is not called easy either', () {
      final note = RunNote.forRun(
        run(
          at: day,
          meters: 5000,
          paceSecondsPerKm: 400,
          elevationGainMeters: 200,
        ),
        history: steadyHistory(),
      );
      expect(note, isNull);
    });
  });

  group('against recent runs', () {
    test('further than they have been going', () {
      final note = RunNote.forRun(
        // Not a record: an older long run stands well clear of it.
        run(at: day, meters: 8000, paceSecondsPerKm: 340),
        history: <RunSummary>[
          ...steadyHistory(),
          run(at: daysBefore(60), meters: 20000, paceSecondsPerKm: 360),
        ],
      );
      expect(note?.kind, RunNoteKind.context);
      expect(note?.headline, contains('Further than'));
      expect(note?.detail, contains('8.00 km'));
    });

    test('quicker than usual, without claiming a record', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5000, paceSecondsPerKm: 315),
        history: <RunSummary>[
          ...steadyHistory(),
          // An old 5 km that was quicker still, so this is not a best.
          run(at: daysBefore(90), meters: 5000, paceSecondsPerKm: 290),
        ],
      );
      expect(note?.kind, RunNoteKind.context);
      expect(note?.headline, contains('Quicker'));
    });

    test('an easier one', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5000, paceSecondsPerKm: 360),
        history: steadyHistory(),
      );
      expect(note?.kind, RunNoteKind.context);
      expect(note?.headline, contains('easier'));
    });

    test('two runs are not enough to know what usual is', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5000, paceSecondsPerKm: 360),
        history: steadyHistory(count: 2),
      );
      expect(note, isNull);
    });

    test('runs from three months ago are not "recent"', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5000, paceSecondsPerKm: 360),
        history: <RunSummary>[
          for (var i = 1; i <= 4; i++)
            run(at: daysBefore(60 + i), meters: 5000, paceSecondsPerKm: 330),
        ],
      );
      expect(note, isNull);
    });

    test('runs after this one do not define what was usual before it', () {
      final note = RunNote.forRun(
        run(at: daysBefore(30), meters: 5000, paceSecondsPerKm: 360),
        history: steadyHistory(),
      );
      expect(note, isNull);
    });
  });

  group('units', () {
    test('an imperial note formats its figures in miles', () {
      final note = RunNote.forRun(
        run(at: day, meters: 12000, paceSecondsPerKm: 340),
        history: steadyHistory(),
        unit: UnitSystem.imperial,
      );
      expect(note?.detail, contains('mi'));
      expect(note?.detail, isNot(contains('km')));
    });

    test('an imperial pace note reads per mile', () {
      final note = RunNote.forRun(
        run(at: day, meters: 5000, paceSecondsPerKm: 300),
        history: steadyHistory(),
        unit: UnitSystem.imperial,
      );
      expect(note?.detail, contains('/mi'));
    });
  });
}
