/// The seam the deletion UI talks to, so the confirmation flow is testable
/// without a backend.
abstract interface class AccountDeleter {
  /// Erases the signed-in user's Runio data, and the shared login too when that
  /// login is Runio-only.
  ///
  /// Throws [AccountDeletionException] on failure, with a message safe to show.
  Future<AccountDeletionResult> deleteAccount();
}

/// What the server actually removed.
///
/// The distinction matters and is shown to the user. Runio's login is a shared
/// MGKCodes fitness account (ADR-0008), so deleting `auth.users` would delete
/// the sibling app's account as well. When the account holds Liftio data the
/// server erases all Runio data and keeps the login; otherwise it removes the
/// login too.
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

  /// True when Runio's data is gone but the login was deliberately kept.
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
