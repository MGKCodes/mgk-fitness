/// Whether this install has met the coach's first lines.
///
/// **A fact about the phone, not the account.** It has to answer before there
/// is an account, which for a new lifter is always, and a lifter who signs in
/// on a second phone is new to *that* phone's app even if not to the account.
/// Run keeps the same fact the same way (`IntroStore` in `mgk_run`), beside a
/// flag on the account that Lift has no need of: Lift's intro asks nothing,
/// so meeting it twice on two phones costs six lines read again.
///
/// **It fails towards seen**, the opposite of Run's. Run's intro asks for the
/// permissions a run tracker needs, so skipping it wrongly costs a run with no
/// route, and Run reads a broken store as "not yet". Lift's asks for nothing,
/// so skipping it costs a lifter six lines they can live without, while
/// showing it on every launch because a store cannot be written would put a
/// welcome screen between somebody and their session every time they open the
/// app. The one failure a gate in front of the app must never have is a loop.
///
/// An interface, as `CoachPreferenceStore` is, so the gate is testable without
/// a platform and the preview harness can run it on the web.
abstract interface class IntroStore {
  /// Whether the intro has been seen, or skipped for somebody who already used
  /// the app before it existed.
  ///
  /// Must **not** throw. A store that cannot be read answers true.
  Future<bool> hasSeen();

  /// Records that it has been. Must not throw; a write that fails is a write
  /// the next launch tries again, after the welcome has been shown once more.
  Future<void> markSeen();
}

/// Keeps the answer for the session only. What tests and the preview want.
class InMemoryIntroStore implements IntroStore {
  InMemoryIntroStore({this.seen = false});

  bool seen;

  /// How many times [markSeen] was called, for a test to check it was, once.
  int marks = 0;

  @override
  Future<bool> hasSeen() async => seen;

  @override
  Future<void> markSeen() async {
    seen = true;
    marks++;
  }
}
