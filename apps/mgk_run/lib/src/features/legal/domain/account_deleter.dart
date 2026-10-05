/// How much of the runner's data is being erased.
///
/// One login serves the whole suite (ADR-0008), so "delete my account" is two
/// requests wearing one name, and since 1.0.1 the app asks which, in the same
/// words as Lift. The function has always taken both: an `app` of `run` scopes
/// the erasure, an absent one takes everything.
enum DeletionScope {
  /// Erase what this app holds. The login survives **if Lift still holds
  /// data**; if it does not, the login goes too, because an account with
  /// nothing behind it is not kept on somebody's behalf. The server decides
  /// that, not the client -- see [AccountDeletionResult.accountDeleted].
  runOnly,

  /// Erase everything, in both apps, and the login itself.
  everything;

  /// What the function is sent. Null means "no scope", which it reads as all
  /// of it.
  String? get app => switch (this) {
    DeletionScope.runOnly => 'run',
    DeletionScope.everything => null,
  };
}

/// The seam the deletion UI talks to, so the confirmation flow is testable
/// without a backend.
abstract interface class AccountDeleter {
  /// Erases what [scope] names: this app's data, and the shared login too
  /// when nothing else is using it; or everything, and the login.
  ///
  /// Throws [AccountDeletionException] on failure, with a message safe to show.
  Future<AccountDeletionResult> deleteAccount({required DeletionScope scope});
}

/// What the server actually removed.
///
/// The distinction matters and is shown to the user. Run's login is a shared
/// MGKFitness account (ADR-0008), so deleting `auth.users` would delete the
/// sibling app's account as well. Asked for this app only, when the account
/// holds Lift data the server erases all of Run's data and keeps the login;
/// otherwise it removes the login too.
class AccountDeletionResult {
  const AccountDeletionResult({
    required this.accountDeleted,
    this.retainedReason,
    this.deletedRows = const <String, int>{},
  });

  /// Whether the shared login itself was removed.
  final bool accountDeleted;

  /// Why the login survived, when it did.
  ///
  /// `other_app_data` means another app still holds data under it, and is what
  /// the deployed `delete-account` function sends. `sibling_app_data` is the
  /// older name for the same thing, from the SQL routine the function wraps,
  /// and is still accepted. `auth_delete_failed` means the data went and the
  /// login could not be removed.
  final String? retainedReason;

  /// Rows removed per table — counts only, never values. Useful in a support
  /// conversation and safe to log.
  final Map<String, int> deletedRows;

  /// True when Run's data is gone but the login was deliberately kept.
  ///
  /// **It only ever matched `sibling_app_data`, which the server does not
  /// send.** The deployed function answers `other_app_data`, so every runner
  /// whose login was kept for Lift was told it had been removed "along with
  /// your login" -- the one sentence on the screen they had no way to check.
  bool get loginRetainedForSiblingApp =>
      !accountDeleted &&
      (retainedReason == 'other_app_data' ||
          retainedReason == 'sibling_app_data');

  /// True when the data went and the login is still there for no reason the
  /// runner chose: the removal failed, or the server gave no reason at all.
  ///
  /// It used to fall through to the sentence for a login that was removed.
  bool get loginNotRemoved => !accountDeleted && !loginRetainedForSiblingApp;
}

/// A deletion failure with a message that is safe to show to the user.
class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message);

  final String message;

  @override
  String toString() => message;
}
