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

void main() {
  setUpAll(() {
    expect(
      DateTime(2026, 7, 1).timeZoneName,
      contains('Summer'),
      reason: 'these dates only prove anything if the host is Europe/London',
    );
  });

  group('dayLabel across the spring change (29 Mar 2026)', () {
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

  group('dayLabel across the autumn change (25 Oct 2026), for symmetry', () {
    test('the day the clocks go back still reads as yesterday, not today', () {
      final label = dayLabel(
        DateTime(2026, 10, 25, 20),
        DateTime(2026, 10, 26, 8),
      );
      expect(label, 'Yesterday');
    });
  });

  test('an ordinary week, nowhere near either change, is unaffected', () {
    expect(
      dayLabel(DateTime(2026, 6, 1, 20), DateTime(2026, 6, 2, 8)),
      'Yesterday',
    );
    expect(dayLabel(DateTime(2026, 6, 1), DateTime(2026, 6, 1, 23)), 'Today');
  });
}
