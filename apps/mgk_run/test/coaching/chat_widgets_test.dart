// Regression for EDGE-23: dayLabel (and, by the same fix, _when in the same
// file, coach_brief.dart's _relativeDay and goal_draft.dart's day count) used
// a plain `DateTime(...).difference(...).inDays` between two local
// midnights. A daylight-saving change shrinks or stretches one of those
// midnight-to-midnight spans to 23 or 25 hours, which truncates a genuine
// one-day gap to zero — a divider dated the evening before spring-forward
// read as "Today" instead of "Yesterday" once `now` crossed into the next
// day. See the throwaway reproduction under
// .claude/worktrees/review-edge/apps/mgk_run/test/zz_edge_review/london_dst_test.dart,
// which runs (like this file) natively in the host's Europe/London zone.
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/presentation/chat_widgets.dart';

/// These dates only prove anything on a host whose clocks change on the UK's
/// dates: UTC+0 in January, UTC+1 in July. Anywhere else -- Codemagic runs in
/// UTC -- the DST groups are skipped rather than failed, because with no clock
/// change the old code passes too and the test would prove nothing.
///
/// Read from offsets, not `timeZoneName`: Windows calls it "GMT Summer Time"
/// and macOS "BST", and a guard on the name failed the Android build on
/// 2026-09-29 for a reason that had nothing to do with the app.
final bool _ukClocks =
    DateTime(2026, 1, 1).timeZoneOffset == Duration.zero &&
    DateTime(2026, 7, 1).timeZoneOffset == const Duration(hours: 1);

final Object _dstSkip = _ukClocks
    ? false
    : 'needs a host on UK clocks (Europe/London); this one is not';

void main() {
  group('dayLabel across the spring change (29 Mar 2026)', skip: _dstSkip, () {
    test('an evening the day before spring-forward reads as yesterday', () {
      // Sun 29 Mar 18:00 is still GMT (the change is at 01:00 that same
      // day); Mon 30 Mar 10:00 is already BST. The two local midnights are
      // 23 hours apart, not 24.
      final label = dayLabel(
        DateTime(2026, 3, 29, 18),
        DateTime(2026, 3, 30, 10),
      );
      expect(label, 'Yesterday');
    });

    test('a week-old divider still reads its actual date', () {
      final label = dayLabel(
        DateTime(2026, 3, 24, 9),
        DateTime(2026, 3, 31, 9),
      );
      expect(label, '24 Mar');
    });
  });

  group(
    'dayLabel across the autumn change (25 Oct 2026), for symmetry',
    skip: _dstSkip,
    () {
      test(
        'the day the clocks go back still reads as yesterday, not today',
        () {
          final label = dayLabel(
            DateTime(2026, 10, 25, 20),
            DateTime(2026, 10, 26, 8),
          );
          expect(label, 'Yesterday');
        },
      );
    },
  );

  test('an ordinary week, nowhere near either change, is unaffected', () {
    expect(
      dayLabel(DateTime(2026, 6, 1, 20), DateTime(2026, 6, 2, 8)),
      'Yesterday',
    );
    expect(dayLabel(DateTime(2026, 6, 1), DateTime(2026, 6, 1, 23)), 'Today');
  });
}
