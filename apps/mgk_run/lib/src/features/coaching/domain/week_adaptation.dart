import 'training_plan.dart';

/// One weekday's change between two versions of a week — the unit the approval
/// UI shows so the runner sees exactly what an adaptation does before applying
/// it. A null [before]/[after] means that day was/becomes a rest day.
class SessionChange {
  const SessionChange({required this.weekday, this.before, this.after});

  /// `DateTime.monday`..`DateTime.sunday`.
  final int weekday;
  final PlannedSession? before;
  final PlannedSession? after;

  bool get isAdded => before == null && after != null;
  bool get isRemoved => before != null && after == null;
  bool get isModified => before != null && after != null;
}

/// The per-weekday differences between two versions of a week — only the days
/// that actually changed. Deterministic, so the "diff" shown to the runner is
/// derived here rather than trusted from the model.
List<SessionChange> diffWeek(TrainingWeek before, TrainingWeek after) {
  final changes = <SessionChange>[];
  for (var day = DateTime.monday; day <= DateTime.sunday; day++) {
    final b = before.runOn(day);
    final a = after.runOn(day);
    if (_sameSession(b, a)) continue;
    changes.add(SessionChange(weekday: day, before: b, after: a));
  }
  return changes;
}

bool _sameSession(PlannedSession? a, PlannedSession? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  return a.kind == b.kind && (a.distanceMeters - b.distanceMeters).abs() < 1;
}
