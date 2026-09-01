/// How much of the person's data is being erased.
///
/// One login serves the whole suite (ADR-0008), so "delete my account" is two
/// different requests wearing one name, and the app has to ask which. The Edge
/// Function has always supported both — an `app` of `lift` scopes the erasure,
/// an absent one takes everything — so this is a choice the server already
/// modelled and no client had yet offered.
enum DeletionScope {
  /// Erase `lift.*` and this app's coach data. The MGKFitness profile survives
  /// **if Run still holds data**; if it does not, the login goes too, because a
  /// profile with nothing behind it is not something to keep on somebody's
  /// behalf. The server decides that, not the client — see
  /// [AccountDeletionResult.accountDeleted].
  liftOnly,

  /// Erase everything, in every app, and the login itself.
  everything;

  /// What the function is sent. Null means "no scope", which it reads as all of
  /// it — the safe-by-omission default documented on the function.
  String? get app => switch (this) {
    DeletionScope.liftOnly => 'lift',
    DeletionScope.everything => null,
  };
}

/// The seam the deletion UI talks to, so the confirmation flow is testable
/// without a backend.
abstract interface class AccountDeleter {
  /// Erases what [scope] names.
  ///
  /// Throws [AccountDeletionException] on failure, with a message safe to show.
  Future<AccountDeletionResult> deleteAccount({required DeletionScope scope});
}

/// What the server actually removed.
///
/// The distinction is shown to the person rather than kept for logs: somebody
/// who asked for their whole profile to go and still has a login needs to know
/// that, and somebody who asked only for Lift needs to know their login went
/// when it turned out nothing else was using it.
class AccountDeletionResult {
  const AccountDeletionResult({
    required this.accountDeleted,
    this.retainedReason,
    this.remainingApps = const <String>[],
    this.deletedRows = const <String, int>{},
  });

  /// Whether the shared MGKFitness login itself was removed.
  final bool accountDeleted;

  /// Why the login survived, when it did.
  ///
  /// `other_app_data` — another app in the suite still holds data.
  /// `auth_delete_failed` — the data is gone but the login could not be
  /// removed, which is a support conversation rather than a retry.
  ///
  /// **This is the server's spelling and it is load-bearing.** Run's client
  /// tests for `sibling_app_data`, which the function never returns, so run's
  /// retained-login message has never once been shown. Copying that constant
  /// across would have copied the bug.
  final String? retainedReason;

  /// Which apps still hold data for this person. Empty when none do.
  final List<String> remainingApps;

  /// Rows removed per table — counts only, never values. Useful in a support
  /// conversation and safe to log.
  final Map<String, int> deletedRows;

  /// True when the data is gone and the login was deliberately kept because
  /// another app is using it.
  bool get loginRetainedForOtherApp =>
      !accountDeleted && retainedReason == 'other_app_data';

  /// True when the erasure succeeded but removing the login did not. The data
  /// is gone either way, which is the part that matters for erasure.
  bool get loginCouldNotBeRemoved =>
      !accountDeleted && retainedReason == 'auth_delete_failed';
}

/// A deletion failure with a message that is safe to show to the user.
class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message);

  final String message;

  @override
  String toString() => message;
}
