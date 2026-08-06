import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_statement.dart';
import 'package:mgk_run/src/features/coaching/domain/training_standing.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// The standing is the answer to "how am I doing", and the only benchmark the
/// app has is the runner a month ago. So every claim on it has to be true of
/// their own log: a card that says "building" over a month of nothing is worse
/// than no card at all.
void main() {
  final now = DateTime(2026, 7, 27); // a Monday

  /// [count] runs of [meters], spread every three days starting [startDaysAgo].
  List<RunSummary> block({
    required int count,
    required double meters,
    required int startDaysAgo,
    double paceSecondsPerKm = 300,
  }) => <RunSummary>[
    for (var i = 0; i < count; i++)
      RunSummary(
        startedAt: now.subtract(Duration(days: startDaysAgo + i * 3)),
        duration: Duration(seconds: (meters / 1000 * paceSecondsPerKm).round()),
        distanceMeters: meters,
        avgPaceSecondsPerKm: paceSecondsPerKm,
      ),
  ];

  TrainingStanding read(List<RunSummary> runs) =>
      TrainingStanding.read(runs: runs, now: now);

  test('nothing recorded is an invitation, not a judgement', () {
    final standing = read(const <RunSummary>[]);

    expect(standing.verdict, StandingVerdict.nothingYet);
    expect(standing.headline, 'Nothing recorded yet');
  });

  test('a log with no prior window has no trend to claim', () {
    // Three runs, all inside the last four weeks. One window is not a direction.
    final standing = read(block(count: 3, meters: 5000, startDaysAgo: 2));

    expect(standing.verdict, StandingVerdict.gettingStarted);
    expect(standing.detail, isNot(contains('up from')));
    expect(standing.detail, isNot(contains('down from')));
  });

  test('more than the month before reads as building', () {
    final standing = read(<RunSummary>[
      ...block(count: 8, meters: 8000, startDaysAgo: 2),
      ...block(count: 6, meters: 6000, startDaysAgo: 30),
    ]);

    expect(standing.verdict, StandingVerdict.building);
    // Plain statement, not jargon: a runner should not have to know what a
    // coach means by "building" to read their own page.
    expect(standing.headline, 'Running more than you were');
    expect(standing.detail, contains('up from'));
  });

  test('less than the month before reads as easing, and does not scold', () {
    final standing = read(<RunSummary>[
      ...block(count: 3, meters: 5000, startDaysAgo: 2),
      ...block(count: 9, meters: 8000, startDaysAgo: 30),
    ]);

    expect(standing.verdict, StandingVerdict.easing);
    expect(standing.detail, contains('down from'));
    // A drop is often the plan. The card must not assume it was a failure.
    expect(standing.detail, contains('deliberate'));
  });

  test('the same month twice is not progress', () {
    final standing = read(<RunSummary>[
      ...block(count: 8, meters: 6000, startDaysAgo: 2),
      ...block(count: 8, meters: 6000, startDaysAgo: 30),
    ]);

    expect(standing.verdict, StandingVerdict.holding);
    expect(standing.detail, isNot(contains('up from')));
  });

  test('a small wobble is noise, not a trend', () {
    // 8 x 6 km against 8 x 6.2 km: a real difference, far too small to mean
    // anything about a runner.
    final standing = read(<RunSummary>[
      ...block(count: 8, meters: 6000, startDaysAgo: 2),
      ...block(count: 8, meters: 6200, startDaysAgo: 30),
    ]);

    expect(standing.verdict, StandingVerdict.holding);
  });

  test('a gap outranks everything — it never reads as progress', () {
    // A big month, then three weeks of silence. The trend would say "building".
    final standing = read(block(count: 8, meters: 9000, startDaysAgo: 21));

    expect(standing.verdict, StandingVerdict.returning);
    expect(standing.detail, isNot(contains('more than you were')));
    expect(standing.detail, contains('21 days'));
  });

  test('getting quicker is reported, in their own numbers', () {
    final standing = read(<RunSummary>[
      ...block(
        count: 8,
        meters: 8000,
        startDaysAgo: 2,
        paceSecondsPerKm: 300, // 5:00
      ),
      ...block(
        count: 6,
        meters: 6000,
        startDaysAgo: 30,
        paceSecondsPerKm: 330, // 5:30
      ),
    ]);

    expect(standing.detail, contains('5:00'));
    expect(standing.detail, contains('5:30'));
    expect(standing.detail, contains('quicker'));
  });

  test('a pace difference inside the noise is not reported', () {
    final standing = read(<RunSummary>[
      ...block(count: 8, meters: 8000, startDaysAgo: 2, paceSecondsPerKm: 300),
      ...block(count: 6, meters: 6000, startDaysAgo: 30, paceSecondsPerKm: 302),
    ]);

    expect(standing.detail, isNot(contains('averaging')));
  });

  test('never mentions the plan — that is the Plan tab\'s subject', () {
    final standing = read(<RunSummary>[
      ...block(count: 8, meters: 8000, startDaysAgo: 2),
      ...block(count: 6, meters: 6000, startDaysAgo: 30),
    ]);

    final text = '${standing.headline} ${standing.detail}';
    expect(text, isNot(matches(RegExp(r'[Ww]eek \d+ of \d+'))));
    expect(text, isNot(contains('race day')));
    expect(text.toLowerCase(), isNot(contains('taper')));
    expect(text.toLowerCase(), isNot(contains('phase')));
  });

  test('weeks, not volume — a single big week is not consistency', () {
    final crammed = <RunSummary>[
      for (var i = 0; i < 6; i++)
        RunSummary(
          startedAt: now.subtract(Duration(days: 8 + i)),
          duration: const Duration(minutes: 30),
          distanceMeters: 6000,
          avgPaceSecondsPerKm: 300,
        ),
      ...block(count: 6, meters: 6000, startDaysAgo: 30),
    ];

    expect(read(crammed).detail, contains('One of the last four weeks'));
  });

  test('the run order it is given does not change the answer', () {
    final runs = <RunSummary>[
      ...block(count: 8, meters: 8000, startDaysAgo: 2),
      ...block(count: 6, meters: 6000, startDaysAgo: 30),
    ];

    expect(read(runs.reversed.toList()).detail, read(runs).detail);
  });

  // The computed line is the fallback a generated one is measured against, so
  // it has to clear the same bar. If our own prose fails our own validator, the
  // validator is wrong about something.
  group('the computed line satisfies its own validator', () {
    final cases = <String, List<RunSummary>>{
      'building': <RunSummary>[
        ...block(count: 8, meters: 8000, startDaysAgo: 2),
        ...block(count: 6, meters: 6000, startDaysAgo: 30),
      ],
      'easing': <RunSummary>[
        ...block(count: 3, meters: 5000, startDaysAgo: 2),
        ...block(count: 9, meters: 8000, startDaysAgo: 30),
      ],
      'holding': <RunSummary>[
        ...block(count: 8, meters: 6000, startDaysAgo: 2),
        ...block(count: 8, meters: 6000, startDaysAgo: 30),
      ],
      'returning': block(count: 8, meters: 9000, startDaysAgo: 21),
      'getting started': block(count: 3, meters: 5000, startDaysAgo: 2),
      'nothing yet': const <RunSummary>[],
    };

    cases.forEach((name, runs) {
      test(name, () {
        final standing = read(runs);
        final problems = CoachStatement.check(standing.detail, standing.facts);

        expect(
          problems,
          isEmpty,
          reason: 'the $name line does not pass its own facts: $problems',
        );
      });
    });
  });

  group('the fact sheet', () {
    test('carries the comparison the prose is built on', () {
      final standing = read(<RunSummary>[
        ...block(count: 8, meters: 8000, startDaysAgo: 2),
        ...block(count: 6, meters: 6000, startDaysAgo: 30),
      ]);

      expect(standing.factSheet, contains('64.0'));
      expect(standing.factSheet, contains('36.0'));
      expect(standing.factSheet, contains('up'));
      // The model is told what it may not claim, not left to infer it.
      expect(standing.factSheet, contains('No records were set'));
    });

    test('tells the model there is no direction when there is not', () {
      final standing = read(block(count: 3, meters: 5000, startDaysAgo: 2));

      expect(standing.factSheet, contains('not enough history'));
    });
  });
}
