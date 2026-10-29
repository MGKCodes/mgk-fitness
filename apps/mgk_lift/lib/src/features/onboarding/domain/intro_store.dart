/// Whether this install has met Lift's first open: the welcome, and the
/// walkthrough over the app it leads to (ADR-0006).
///
/// **Named for the first open it was made for**, the coach's lines on a
/// screen of their own, which the walkthrough replaced the same day (29
/// October 2026). The fact is the same one, so the name and the key
/// (`intro.seen`) stayed.
///
/// **A fact about the phone, not the account.** It has to answer before there
/// is an account, which for a new lifter is always, and a lifter who signs in
/// on a second phone is new to *that* phone's app even if not to the account.
/// Run keeps the same fact the same way (`IntroStore` in `mgk_run`), beside a
/// flag on the account that Lift has no need of: Lift's first open asks
/// nothing, so meeting it twice on two phones costs a walkthrough played
/// twice.
///
/// **It fails towards seen**, the opposite of Run's. Run's intro asks for the
/// permissions a run tracker needs, so skipping it wrongly costs a run with no
/// route, and Run reads a broken store as "not yet". Lift's asks for nothing,
/// so skipping it costs a lifter a walkthrough they can still play from
/// Settings, while
/// showing it on every launch because a store cannot be written would put a
/// welcome screen between somebody and their session every time they open the
/// app. The one failure a gate in front of the app must never have is a loop.
///
/// An interface, as `CoachPreferenceStore` is, so the gate is testable without
/// a platform and the preview harness can run it on the web.
abstract interface class IntroStore {
  /// Whether the first open has been seen, or skipped for somebody who
  /// already used the app before it existed or arrived with an account.
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
