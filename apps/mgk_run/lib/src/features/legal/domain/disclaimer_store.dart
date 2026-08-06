/// Where the medical-disclaimer acknowledgement lives.
///
/// This is a **local preference**, not account state: it records that *this
/// install* has shown the disclaimer and had it accepted. It deliberately does
/// not go to Supabase — nothing about it needs to be shared across devices, and
/// a legal notice is cheap to re-show on a new device but expensive to get
/// wrong.
///
/// An interface (not a concrete class) so screens are testable and the preview
/// harness runs on web, where the file-backed implementation cannot.
abstract interface class DisclaimerStore {
  /// Whether the user has already acknowledged the medical disclaimer.
  ///
  /// Must **not** throw. A store that cannot read its backing state returns
  /// `false` — the fail-safe direction is to show the disclaimer again, never to
  /// skip it.
  Future<bool> isAcknowledged();

  /// Records the acknowledgement. Must not throw; a failed write only means the
  /// user is asked again next launch.
  Future<void> acknowledge();
}

/// A [DisclaimerStore] that forgets on restart. Used by widget tests and by the
/// preview harness, and as the fail-safe fallback when no real store is wired:
/// the gate still appears, only the persistence is missing.
class InMemoryDisclaimerStore implements DisclaimerStore {
  InMemoryDisclaimerStore({bool acknowledged = false})
    : _acknowledged = acknowledged;

  bool _acknowledged;

  /// How many times [acknowledge] was called — handy in tests.
  int acknowledgeCount = 0;

  @override
  Future<bool> isAcknowledged() async => _acknowledged;

  @override
  Future<void> acknowledge() async {
    _acknowledged = true;
    acknowledgeCount++;
  }
}
