import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/week_adaptation.dart';

void main() {
  TrainingWeek week(List<PlannedSession> sessions) =>
      TrainingWeek(skeletonIndex: 1, sessions: sessions);

  test('diffWeek reports added, removed, and modified days', () {
    final before = week(const <PlannedSession>[
      PlannedSession(
        weekday: DateTime.monday,
        kind: SessionKind.easy,
        distanceMeters: 8000,
      ),
      PlannedSession(
        weekday: DateTime.tuesday,
        kind: SessionKind.threshold,
        distanceMeters: 9000,
      ),
      PlannedSession(
        weekday: DateTime.sunday,
        kind: SessionKind.long,
        distanceMeters: 20000,
      ),
    ]);
    final after = week(const <PlannedSession>[
      // Monday removed (now rest); Tuesday distance changed; Wednesday added;
      // Sunday unchanged.
      PlannedSession(
        weekday: DateTime.tuesday,
        kind: SessionKind.threshold,
        distanceMeters: 10000,
      ),
      PlannedSession(
        weekday: DateTime.wednesday,
        kind: SessionKind.easy,
        distanceMeters: 8000,
      ),
      PlannedSession(
        weekday: DateTime.sunday,
        kind: SessionKind.long,
        distanceMeters: 20000,
      ),
    ]);

    final changes = diffWeek(before, after);
    final byDay = <int, SessionChange>{for (final c in changes) c.weekday: c};

    expect(byDay.keys.toSet(), <int>{
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
    });
    expect(byDay[DateTime.monday]!.isRemoved, isTrue);
    expect(byDay[DateTime.tuesday]!.isModified, isTrue);
    expect(byDay[DateTime.wednesday]!.isAdded, isTrue);
  });

  test('identical weeks produce no changes', () {
    final w = week(const <PlannedSession>[
      PlannedSession(
        weekday: DateTime.monday,
        kind: SessionKind.easy,
        distanceMeters: 8000,
      ),
    ]);
    expect(diffWeek(w, w), isEmpty);
  });
}
