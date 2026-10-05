/// Where the medical-disclaimer acknowledgement lives (5 October 2026, as
/// Run's).
///
/// This is a **local preference**, not account state: it records that *this
/// install* has shown the disclaimer and had it accepted. It does not go to
/// Supabase. Nothing about it needs sharing across phones, and a legal notice
/// is cheap to show again on a new phone but expensive to get wrong.
abstract interface class DisclaimerStore {
  /// Whether the lifter has already acknowledged the medical disclaimer.
  ///
  /// Must **not** throw. A store that cannot read its state returns `false`:
  /// the fail-safe direction is to show the disclaimer again, never to skip it.
  Future<bool> isAcknowledged();

  /// Records the acknowledgement. Must not throw; a failed write only means
  /// the lifter is asked again next time.
  Future<void> acknowledge();
}

/// A [DisclaimerStore] that forgets on restart, for tests and the preview
/// harness.
class InMemoryDisclaimerStore implements DisclaimerStore {
  InMemoryDisclaimerStore({bool acknowledged = false})
    : _acknowledged = acknowledged;

  bool _acknowledged;

  /// How many times [acknowledge] was called.
  int acknowledgeCount = 0;

  @override
  Future<bool> isAcknowledged() async => _acknowledged;

  @override
  Future<void> acknowledge() async {
    _acknowledged = true;
    acknowledgeCount++;
  }
}
