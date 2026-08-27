/// Whether this install has been through the intro.
///
/// **A local fact, because it has to answer before there is an account.**
/// It used to be one: `AuthRepository.hasMetCoach` reads a flag off the auth
/// user's metadata, which is the right home for it while every runner is signed
/// in — it travels with the account, so somebody arriving from Lift is not
/// introduced to a coach they have already met.
///
/// It cannot answer for a runner who has no account, and that is now the
/// ordinary case rather than an edge one. The app opens on a working tracker
/// and asks for an account only when one buys something (ADR-0019), so the
/// question "has this person met the coach and answered the permissions" has to
/// be answerable with nothing signed in.
///
/// So both are kept and either satisfies the gate: the metadata flag still
/// travels between devices for anybody who has an account, and this records the
/// install. Belt and braces on purpose — the cost of getting it wrong in one
/// direction is a conversation somebody has twice, and in the other it is a
/// runner who is never asked for location and cannot work out why a run records
/// no route.
///
/// An interface (not a concrete class) so screens are testable and the preview
/// harness runs on web, where the file-backed implementation cannot.
abstract interface class IntroStore {
  /// Whether the intro has already run on this install.
  ///
  /// Must **not** throw. A store that cannot read its backing state returns
  /// `false`: the fail-safe direction is to run the intro again, which costs a
  /// conversation somebody has seen before. Skipping it wrongly costs the
  /// permissions, which is the expensive mistake.
  Future<bool> isDone();

  /// Records that the intro finished, and what the runner said to call them.
  ///
  /// The name is here for the same reason the marker is: it was given to the
  /// coach in a conversation that no longer ends in an account, so
  /// `AuthRepository.currentName` - which reads auth user metadata - has
  /// nowhere to keep it. Without this the runner tells the coach their name and
  /// the coach forgets it the moment the intro ends.
  ///
  /// Must not throw; a failed write only means it is shown once more next
  /// launch.
  Future<void> markDone({String? name});

  /// What the runner said to call them, or null if they skipped it or the
  /// intro has not run. Must not throw.
  Future<String?> readName();
}

/// An [IntroStore] that forgets on restart. Used by widget tests and by the
/// preview harness, and as the fail-safe fallback when no real store is wired:
/// the intro still appears, only the persistence is missing.
class InMemoryIntroStore implements IntroStore {
  InMemoryIntroStore({bool done = false, String? name})
    : _done = done,
      _name = name;

  bool _done;
  String? _name;

  /// How many times [markDone] was called — handy in tests.
  int markCount = 0;

  @override
  Future<bool> isDone() async => _done;

  @override
  Future<String?> readName() async => _name;

  @override
  Future<void> markDone({String? name}) async {
    _done = true;
    if (name != null) _name = name;
    markCount++;
  }
}
