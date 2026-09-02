import 'package:test/test.dart';
import 'package:mgk_units/mgk_units.dart';

void main() {
  group('DurationFormat.hoursMinutesSeconds', () {
    test('formats sub-hour durations as M:SS', () {
      expect(
        const Duration(minutes: 5, seconds: 3).hoursMinutesSeconds,
        '5:03',
      );
      expect(const Duration(seconds: 9).hoursMinutesSeconds, '0:09');
    });

    test('formats hour-plus durations as H:MM:SS', () {
      expect(
        const Duration(hours: 1, minutes: 2, seconds: 5).hoursMinutesSeconds,
        '1:02:05',
      );
      expect(const Duration(hours: 12).hoursMinutesSeconds, '12:00:00');
    });

    test('uses the absolute value of a negative duration', () {
      expect(const Duration(seconds: -75).hoursMinutesSeconds, '1:15');
    });
  });

  group('DurationFormat.totalHours', () {
    test('a career is whole hours', () {
      expect(
        const Duration(hours: 305, minutes: 32, seconds: 23).totalHours,
        '305 h',
      );
      expect(const Duration(hours: 1).totalHours, '1 h');
    });

    test('truncates rather than rounding — a total is a floor', () {
      expect(
        const Duration(hours: 305, minutes: 59, seconds: 59).totalHours,
        '305 h',
      );
    });

    test('under an hour keeps the minutes, which are the whole figure', () {
      expect(const Duration(minutes: 47, seconds: 20).totalHours, '47:20');
      expect(const Duration(seconds: 9).totalHours, '0:09');
      expect(Duration.zero.totalHours, '0:00');
    });
  });
}
