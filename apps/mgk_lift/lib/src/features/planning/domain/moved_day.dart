/// *Do it today* (R8, O4): another day's session, brought forward to today.
///
/// **A choice on this phone, not a plan edit.** A plan's days are derived from
/// its weekdays rather than stored as dated sessions, and nothing in the app or
/// the coach can move one (see the plan's *Found while planning*). So this is
/// the one-day answer: the lifter picks Thursday's session on Plan, Track shows
/// it as today's, "moved from Thursday", and the plan itself is untouched.
///
/// It lasts until that session is finished or the day ends, whichever is
/// first, so a choice made on Monday never greets anybody on Tuesday.
abstract interface class MovedDayStore {
  /// The day of the split brought forward to [today], or null. Must not throw.
  Future<String?> read(DateTime today);

  /// Must not throw.
  Future<void> write(String day, DateTime today);

  /// Must not throw.
  Future<void> clear();
}

/// Forgets on restart. For tests and the preview harness.
class InMemoryMovedDay implements MovedDayStore {
  InMemoryMovedDay([this._day, this._on]);

  String? _day;
  DateTime? _on;

  @override
  Future<String?> read(DateTime today) async =>
      _on != null && _sameDay(_on!, today) ? _day : null;

  @override
  Future<void> write(String day, DateTime today) async {
    _day = day;
    _on = today;
  }

  @override
  Future<void> clear() async {
    _day = null;
    _on = null;
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
