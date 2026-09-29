import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/tracking/domain/rest_timer.dart';

void main() {
  final start = DateTime(2026, 8, 7, 18, 30);

  RestTimer timer([Duration d = const Duration(seconds: 90)]) =>
      RestTimer(startedAt: start, duration: d);

  group('counting down', () {
    test('remaining is the gap between the clock and the end', () {
      expect(
        timer().remainingAt(start.add(const Duration(seconds: 30))).inSeconds,
        60,
      );
    });

    test('a phone in a pocket keeps the right time', () {
      // The whole reason this is derived from a timestamp. A backgrounded app
      // has no ticker, so a counter that decrements on a Timer.periodic comes
      // back reading whatever it reached before Android suspended it.
      // Two minutes away from a ninety-second rest: over, not "58 left".
      final away = start.add(const Duration(minutes: 2));
      expect(timer().isDoneAt(away), isTrue);
      expect(timer().remainingAt(away), Duration.zero);
    });

    test('remaining never goes negative', () {
      final late = start.add(const Duration(minutes: 10));
      expect(timer().remainingAt(late), Duration.zero);
    });

    test('progress runs 0 to 1 and stops there', () {
      expect(timer().progressAt(start), 0);
      expect(timer().progressAt(start.add(const Duration(seconds: 45))), 0.5);
      expect(timer().progressAt(start.add(const Duration(minutes: 5))), 1);
    });

    test('a zero-length rest is finished rather than dividing by zero', () {
      final t = timer(Duration.zero);
      expect(t.progressAt(start), 1);
      expect(t.isDoneAt(start), isTrue);
    });
  });

  group('adjusting', () {
    test('adding time extends the same rest, it does not restart it', () {
      // startedAt is untouched, so the thirty seconds land on the end rather
      // than giving back the time already rested.
      final at = start.add(const Duration(seconds: 30));
      final longer = timer().extendedBy(const Duration(seconds: 30), at);

      expect(longer.startedAt, start);
      expect(longer.remainingAt(at).inSeconds, 90);
    });

    test('taking time off can end the rest', () {
      final at = start.add(const Duration(seconds: 70));
      final shorter = timer().extendedBy(const Duration(seconds: -30), at);
      expect(shorter.isDoneAt(at), isTrue);
    });

    test('taking time off cannot revive a rest already finished', () {
      // Without the floor at elapsed, subtracting from a 90s timer 100s in
      // gives a 60s duration — which reads as "done" but would come back as
      // unfinished the moment anything recalculated it.
      final at = start.add(const Duration(seconds: 100));
      final shorter = timer().extendedBy(const Duration(seconds: -30), at);
      expect(shorter.isDoneAt(at), isTrue);
      expect(shorter.remainingAt(at), Duration.zero);
    });

    test('duration never goes negative', () {
      final shorter = timer(
        const Duration(seconds: 10),
      ).extendedBy(const Duration(seconds: -30), start);
      expect(shorter.duration.isNegative, isFalse);
    });
  });

  group('past the end', () {
    final start = DateTime(2026, 9, 29, 18);
    final rest = RestTimer(
      startedAt: start,
      duration: const Duration(seconds: 90),
    );

    test('ends at a fixed instant, which is what the alert is set for', () {
      expect(rest.endsAt, start.add(const Duration(seconds: 90)));
      // An adjustment moves it; the alert is rescheduled from the new one.
      final longer = rest.extendedBy(const Duration(seconds: 30), start);
      expect(longer.endsAt, start.add(const Duration(minutes: 2)));
    });

    test('counts up once over, and is zero until then', () {
      expect(
        rest.overtimeAt(start.add(const Duration(seconds: 60))),
        Duration.zero,
      );
      expect(rest.overtimeAt(rest.endsAt), Duration.zero);
      expect(
        rest.overtimeAt(start.add(const Duration(seconds: 130))),
        const Duration(seconds: 40),
      );
    });
  });

  group('formatting', () {
    test('minutes and seconds, zero padded', () {
      expect(RestTimer.format(const Duration(seconds: 90)), '1:30');
      expect(RestTimer.format(const Duration(seconds: 7)), '0:07');
      expect(RestTimer.format(Duration.zero), '0:00');
    });

    test('past an hour it keeps counting minutes rather than wrapping', () {
      // Nobody rests this long, but wrapping to 1:00 would read as one minute.
      expect(RestTimer.format(const Duration(minutes: 61)), '61:00');
    });
  });
}
