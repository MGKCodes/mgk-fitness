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
}
