import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_run/src/features/recording/domain/route_metrics.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';

/// The demo trace has to run at the pace it says it does.
///
/// It drives every plate on the board and several widget tests, so if the
/// scaling is wrong the evidence is wrong — and wrong in the least visible way,
/// because a plate showing the wrong verdict still looks like a working screen.
///
/// The scaling is not exact by construction: the loop's radius is perturbed by
/// two sine terms and each fix is jittered by ~2 m, so the drawn path is a
/// little longer than the ideal one. A few percent is expected; a band is
/// 31 seconds wide, so a few percent is also affordable.
void main() {
  Duration pacePerKmOf(List<RunPoint> trace) {
    final double meters = processedDistanceMeters(trace);
    final Duration elapsed = trace.last.timestamp.difference(
      trace.first.timestamp,
    );
    return Duration(
      milliseconds: (elapsed.inMilliseconds / (meters / 1000)).round(),
    );
  }

  test('the default loop is the slow one, outside every band', () {
    final Duration pace = pacePerKmOf(demoRunTrace());
    // 9:32/km over the whole loop. Worth pinning precisely, because the
    // obvious guess is wrong: the opening quarter runs nearer 8:45, which is
    // what the plates show, and taking that figure for the whole loop is what
    // made the first attempt at a paced trace ~50 s/km fast.
    expect(pace.inSeconds, closeTo(572, 572 * 0.03));
  });

  for (final Duration asked in <Duration>[
    const Duration(minutes: 5, seconds: 30),
    const Duration(minutes: 6, seconds: 40),
    const Duration(minutes: 7, seconds: 30),
  ]) {
    test('a trace asked for ${asked.inSeconds}s/km runs at about that', () {
      final Duration actual = pacePerKmOf(demoRunTrace(pacePerKm: asked));
      expect(
        actual.inSeconds,
        closeTo(asked.inSeconds, asked.inSeconds * 0.05),
        reason: 'asked ${asked.inSeconds}s/km, got ${actual.inSeconds}s/km',
      );
    });
  }

  test('scaling changes the pace without changing the shape', () {
    final List<RunPoint> slow = demoRunTrace();
    final List<RunPoint> quick = demoRunTrace(
      pacePerKm: const Duration(minutes: 5, seconds: 30),
    );

    // Same number of fixes, same timing — only the ground covered differs, so
    // the route still reads like the same run.
    expect(quick.length, slow.length);
    expect(
      quick.last.timestamp.difference(quick.first.timestamp),
      slow.last.timestamp.difference(slow.first.timestamp),
    );
    expect(
      processedDistanceMeters(quick),
      greaterThan(processedDistanceMeters(slow)),
    );
  });
}
