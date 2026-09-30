import 'package:flutter/foundation.dart';

/// Whose training is on this phone.
///
/// ## Why this exists
///
/// Each app keeps one database, one profile photo, one stored name and one
/// backup answer on the phone, and none of it says who it belongs to: the
/// local database was only ever meant to hold one person. That was fine while
/// one account was all a phone ever saw. It stopped being fine in Run the
/// moment a second one signed in (`ab02080`): the launch restore and backfill
/// ran for them, and every local run the server lacked was pushed into *their*
/// account, traces and all. They saw the first runner's log, plan, injury
/// notes and coach transcripts, and the coach wrote its brief about them from
/// somebody else's training.
///
/// Lift had the same hole with sessions and photographs, and signing in with
/// Apple and Google makes a second account on one phone far more likely (an
/// Apple sign-in that hides the address is a new account), so the rule moved
/// here, for both apps.
///
/// So the phone records which account its training belongs to. It is a file
/// beside the others rather than a column, deliberately: a column would be a
/// schema change on every table, and the question is about the phone, not
/// about a row.
abstract interface class LocalDataOwnerStore {
  /// The account the training here belongs to, or null when nobody has
  /// claimed it. Must not throw.
  Future<String?> read();

  /// Must not throw.
  Future<void> write(String userId);

  /// Must not throw.
  Future<void> clear();
}

/// An owner record that forgets on restart, for tests and the preview harness.
class InMemoryLocalDataOwner implements LocalDataOwnerStore {
  InMemoryLocalDataOwner([this._owner]);

  String? _owner;

  @override
  Future<String?> read() async => _owner;

  @override
  Future<void> write(String userId) async => _owner = userId;

  @override
  Future<void> clear() async => _owner = null;
}

/// Everything on this phone that belongs to one person, as each app counts
/// it. Run's is the runs and their traces, the plans, what the coach
/// remembers, the photo, the name and the backup answer; Lift's is the
/// sessions, the saved workouts, the photographs and the settings that are
/// somebody's.
abstract interface class LocalTrainingData {
  /// True when none of it is here. Must not throw; a phone it cannot read
  /// counts as holding something, which is the direction that asks.
  Future<bool> isEmpty();

  /// Removes all of it. Throws if the training itself could not be removed,
  /// so nothing can carry on as though it had been.
  Future<void> eraseAll();
}

/// The one rule about whose training this is, and the only ways to change it.
///
/// **A phone with no training on it has no owner.** Whoever signs in next
/// claims it, and whatever they record is theirs.
///
/// **The first account to sign in while training is here becomes its owner.**
/// That is the ordinary path, not a loophole: somebody trains for weeks with no
/// account, then creates one, and what they recorded is theirs. It is also what
/// an existing install looks like the first time this runs, with a session
/// already in hand.
///
/// **A different account signing in while training is here is asked, before
/// anything else happens,** whether to erase it or sign out. Nothing restores,
/// backfills, mirrors or talks to the coach until that is answered. Each app
/// holds its own work back on that answer (Run: `AuthGate` and
/// `HomeShell._doRestoreThenLoad`; Lift: `LiftShell`).
class LocalDataGuard {
  LocalDataGuard({
    required LocalDataOwnerStore owner,
    required LocalTrainingData data,
  }) : _owner = owner,
       _data = data;

  final LocalDataOwnerStore _owner;
  final LocalTrainingData _data;

  /// Counts completed erasures, so anything holding a copy of the phone's
  /// training in memory -- the shell, the name the gate read at launch -- can
  /// start again from what is actually on disk.
  final ValueNotifier<int> erasures = ValueNotifier<int>(0);

  String? _askedFor;
  Future<bool>? _answer;

  /// Whether [userId] may use what is on this phone, claiming it when nobody
  /// else has.
  ///
  /// One answer per account, shared by everybody who asks: the gate and the
  /// shell both ask within a frame of a sign-in, and two claims racing each
  /// other is how the first would be decided twice.
  Future<bool> mayUse(String userId) {
    final answer = _answer;
    if (answer != null && _askedFor == userId) return answer;
    _askedFor = userId;
    return _answer = _decide(userId);
  }

  Future<bool> _decide(String userId) async {
    final owner = await _owner.read();
    if (owner == userId) return true;
    final empty = await _data.isEmpty();
    if (owner != null && !empty) return false;
    if (owner != null) {
      // Somebody else's phone with none of their training left on it. What is
      // left is theirs too -- the backup answer they gave, the record of their
      // last push -- and none of it should greet the next account.
      //
      // Not fatal if it fails: there is no training here to protect, and a yes
      // left behind cannot apply to this account anyway (`consentFor`).
      try {
        await _data.eraseAll();
      } on Object {
        // Deliberate: see above.
      }
    }
    await _owner.write(userId);
    return true;
  }

  /// Erases this phone's training and hands the phone to [userId].
  ///
  /// The answer to "this phone holds another account's training": the only way
  /// past it that keeps the account that just signed in.
  Future<void> eraseFor(String userId) async {
    await _data.eraseAll();
    await _owner.write(userId);
    _askedFor = userId;
    _answer = Future<bool>.value(true);
    erasures.value++;
  }

  /// Erases this phone's training and leaves it unclaimed. Signing out with
  /// "also remove my data" and deleting the account both end here.
  Future<void> erase() async {
    await _data.eraseAll();
    await _owner.clear();
    _askedFor = null;
    _answer = null;
    erasures.value++;
  }

  /// Leaves the training where it is and the phone unclaimed.
  ///
  /// For an account that has been deleted while its owner kept this phone's
  /// copy. The account it belonged to is gone, so the phone is back where
  /// somebody with no account starts: the next account to sign in claims it --
  /// including this person's own, should they make one again, which is exactly
  /// who should not be asked to erase their own training to do it.
  Future<void> release() async {
    await _owner.clear();
    _askedFor = null;
    _answer = null;
  }
}
