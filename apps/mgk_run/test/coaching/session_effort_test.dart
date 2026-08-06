import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/units/distance.dart';
import 'package:mgk_run/src/core/units/unit_system.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_run/src/features/coaching/domain/session_effort.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';

void main() {
  // 22:00 for 5 km — the demo runner.
  final paces = TrainingPaces.fromRace(
    Distance.meters(5000),
    const Duration(minutes: 22),
  );

  group('pace bands', () {
    test('a band brackets the single pace it replaced', () {
      final pairs = <(PaceBand, double)>[
        (paces.recoveryBand, paces.recovery.secondsPerKilometer),
        (paces.easyBand, paces.easy.secondsPerKilometer),
        (paces.marathonBand, paces.marathon.secondsPerKilometer),
        (paces.thresholdBand, paces.threshold.secondsPerKilometer),
        (paces.intervalBand, paces.interval.secondsPerKilometer),
      ];
      for (final (band, point) in pairs) {
        expect(band.fast.secondsPerKilometer, lessThan(point));
        expect(band.slow.secondsPerKilometer, greaterThan(point));
      }
    });

    test('bands do not overlap, so two efforts are never the same pace', () {
      // Fastest end of a slower zone stays slower than the slowest end of the
      // next one up. An easy run that overlaps threshold is not an easy run.
      final ladder = <PaceBand>[
        paces.recoveryBand,
        paces.easyBand,
        paces.marathonBand,
        paces.thresholdBand,
        paces.intervalBand,
      ];
      for (var i = 1; i < ladder.length; i++) {
        expect(
          ladder[i].slow.secondsPerKilometer,
          lessThan(ladder[i - 1].fast.secondsPerKilometer),
          reason: 'band $i overlaps the one below it',
        );
      }
    });

    test('formats as a range with one unit suffix', () {
      final text = paces.easyBand.format(UnitSystem.metric);
      expect(text, contains('–'));
      expect(text, endsWith('/km'));
      expect(
        '/km'.allMatches(text).length,
        1,
        reason: 'the suffix belongs to the range, not to each end of it',
      );
    });

    test('converts at display, like every other distance', () {
      expect(paces.easyBand.format(UnitSystem.imperial), endsWith('/mi'));
    });
  });

  group('effort', () {
    test('every kind has one, including rest and strength', () {
      for (final kind in SessionKind.values) {
        final effort = effortFor(kind);
        expect(effort.label, isNotEmpty, reason: kind.name);
        expect(effort.cue, isNotEmpty, reason: kind.name);
        expect(effort.feel, isNotEmpty, reason: kind.name);
        expect(effort.purpose, isNotEmpty, reason: kind.name);
      }
    });

    test('effort rises with the kind', () {
      expect(
        effortFor(SessionKind.recovery).rpeHigh,
        lessThan(effortFor(SessionKind.easy).rpeHigh),
      );
      expect(
        effortFor(SessionKind.easy).rpeHigh,
        lessThan(effortFor(SessionKind.threshold).rpeHigh),
      );
      expect(
        effortFor(SessionKind.threshold).rpeHigh,
        lessThan(effortFor(SessionKind.interval).rpeHigh),
      );
    });

    test('the sessions with no pace have no band', () {
      expect(bandFor(SessionKind.rest, paces), isNull);
      expect(bandFor(SessionKind.strength, paces), isNull);
    });

    test('a long run is an easy run that goes on longer', () {
      // Same effort, same band — the difference is the distance, and a long run
      // given its own faster band is the classic way to ruin one.
      expect(
        bandFor(SessionKind.long, paces)!.fast,
        bandFor(SessionKind.easy, paces)!.fast,
      );
    });
  });

  // A row reading "Easy / easy" spends a line of type saying nothing. The cue
  // has to tell a runner something the session's own name does not.
  test('no cue merely repeats the session it sits under', () {
    for (final kind in SessionKind.values) {
      final effort = effortFor(kind);
      expect(
        effort.cue.toLowerCase(),
        isNot(effort.label.toLowerCase()),
        reason: kind.name,
      );
    }
  });
}
