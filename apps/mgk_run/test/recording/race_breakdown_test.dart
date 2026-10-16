import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/recording/domain/race_breakdown.dart';
import 'package:mgk_run/src/features/recording/domain/run_split.dart';

/// The race measured against the course, not against the phone.
///
/// The fixture is the half marathon that started this (Sunday 11 October
/// 2026): the phone's splits as its summary showed them, to the second, and the
/// chip's checkpoints from the results page. The phone read 21.69 km for a
/// 21.0975 km course, and the question every test here asks in one form or
/// another is whether placing checkpoints proportionally along that over-read
/// trace lands near the mats.
void main() {
  /// Seconds per whole kilometre, then the 0.6858 km partial at 6:19 /km.
  const perKm = <int>[
    323, 307, 309, 302, 292, 306, 339, 320, 326, 311, //
    347, 325, 356, 346, 338, 356, 346, 349, 353, 355, 371,
  ];
  final sunday = <RunSplit>[
    for (var i = 0; i < perKm.length; i++)
      RunSplit(
        index: i + 1,
        distanceMeters: 1000,
        duration: Duration(seconds: perKm[i]),
      ),
    const RunSplit(
      index: 22,
      distanceMeters: 685.8,
      duration: Duration(seconds: 260),
    ),
  ];
  const half = 21097.5;

  /// The chip's section paces, from the results page, in seconds per km:
  /// 26:32 to 5K, 27:26 to 10K, 29:39 to 15K, 36:53 to the finish.
  const chipPaces = <double>[1592 / 5, 1646 / 5, 1779 / 5, 2213 / 6.0975];

  test('a half is cut at 5K, 10K, 15K and the finish', () {
    final b = raceBreakdownFor(sunday, half)!;

    expect(b.sections.map((s) => s.toMeters), <double>[
      5000,
      10000,
      15000,
      half,
    ]);
    // The last 1.1 km is folded into "15K to the finish", as every results
    // page does, rather than shown as a sprint of its own.
    expect(b.sections.last.isFinish, isTrue);
    expect(b.sections.last.meters, closeTo(6097.5, 0.01));
  });

  test("each section's pace is within five seconds a km of the chip's", () {
    final b = raceBreakdownFor(sunday, half)!;

    for (var i = 0; i < chipPaces.length; i++) {
      expect(
        b.sections[i].paceSecondsPerKm,
        closeTo(chipPaces[i], 5),
        reason: 'section ${i + 1}',
      );
    }
  });

  test('the sections add up to the whole phone time, gaps already out', () {
    final b = raceBreakdownFor(sunday, half)!;
    final total = b.sections.fold<Duration>(
      Duration.zero,
      (t, s) => t + s.duration,
    );
    final phone = sunday.fold<Duration>(
      Duration.zero,
      (t, s) => t + s.duration,
    );

    expect((total - phone).inMilliseconds.abs(), lessThan(5));
  });

  test('the halves show the fade the chip shows', () {
    final b = raceBreakdownFor(sunday, half)!;

    // About 5:25 then 6:01 a km: a positive split of roughly 11%.
    expect(b.firstHalf.paceSecondsPerKm, closeTo(325, 3));
    expect(b.secondHalf.paceSecondsPerKm, closeTo(361, 3));
    expect(b.fade, closeTo(0.11, 0.01));
  });

  test('a 5K is cut every kilometre and a 10K every two', () {
    final five = <RunSplit>[
      for (var i = 1; i <= 5; i++)
        RunSplit(
          index: i,
          distanceMeters: 1000,
          duration: const Duration(minutes: 5),
        ),
    ];
    expect(raceBreakdownFor(five, 5000)!.sections, hasLength(5));

    final ten = <RunSplit>[
      for (var i = 1; i <= 10; i++)
        RunSplit(
          index: i,
          distanceMeters: 1000,
          duration: const Duration(minutes: 5),
        ),
    ];
    expect(raceBreakdownFor(ten, 10000)!.sections, hasLength(5));
  });

  test('a marathon keeps 40K to the finish as its own section', () {
    final marathon = <RunSplit>[
      for (var i = 1; i <= 42; i++)
        RunSplit(
          index: i,
          distanceMeters: 1000,
          duration: const Duration(minutes: 5),
        ),
      const RunSplit(
        index: 43,
        distanceMeters: 195,
        duration: Duration(seconds: 58),
      ),
    ];
    final b = raceBreakdownFor(marathon, 42195)!;

    expect(b.sections, hasLength(9));
    expect(b.sections[7].toMeters, 40000);
    expect(b.sections.last.fromMeters, 40000);
  });

  test('a recording far from the course has no breakdown', () {
    // A phone left running on the walk home: the "half" is 25 km.
    final long = <RunSplit>[
      for (var i = 1; i <= 25; i++)
        RunSplit(
          index: i,
          distanceMeters: 1000,
          duration: const Duration(minutes: 5),
        ),
    ];
    expect(raceBreakdownFor(long, half), isNull);

    // And one that lost most of the race.
    expect(raceBreakdownFor(long.take(15).toList(), half), isNull);
  });

  test('no splits, no breakdown', () {
    expect(raceBreakdownFor(const <RunSplit>[], half), isNull);
  });

  test('splits restored out of order are put back in order', () {
    final b = raceBreakdownFor(sunday.reversed.toList(), half)!;
    expect(b.sections.first.paceSecondsPerKm, closeTo(chipPaces.first, 5));
  });
}
