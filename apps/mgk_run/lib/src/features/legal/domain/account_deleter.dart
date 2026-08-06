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

  /// Why the login survived, when it did. `sibling_app_data` means the account
  /// is in use by Liftio.
  final String? retainedReason;

  /// Rows removed per table — counts only, never values. Useful in a support
  /// conversation and safe to log.
  final Map<String, int> deletedRows;

  /// True when Runio's data is gone but the login was deliberately kept.
  bool get loginRetainedForSiblingApp =>
      !accountDeleted && retainedReason == 'sibling_app_data';
}

/// A deletion failure with a message that is safe to show to the user.
class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message);

  final String message;

  @override
  String toString() => message;
}
