/// Whether the runner has agreed to their data leaving the phone.
///
/// Runio stores GPS traces, heart rates, injury notes and the runner's own
/// sentences about their body. Under UK GDPR that is special-category data
/// (Art. 9), and the lawful basis for a consumer app holding it is **explicit
/// consent** — which has to be asked for, not assumed from an install.
///
/// So this is deliberately three-valued rather than a boolean. "Not asked yet"
/// is a real state and behaves like a no: nothing leaves the device until the
/// runner has actually said yes. A boolean would have to default to something,
/// and both defaults are wrong — false is indistinguishable from a considered
/// refusal, and true is consent nobody gave.
enum BackupConsent {
  /// Never asked. Behaves as [declined] for every purpose except the UI, which
  /// is the only thing that should care about the difference.
  unknown,

  /// Yes: mirror my runs, plans and coach memory so I can get them back.
  granted,

  /// No: this phone is the only copy.
  declined;

  /// The only question the push paths ask.
  bool get allowsBackup => this == granted;

  /// Whether the runner still needs to be asked. Distinct from [allowsBackup]
  /// so a refusal is not mistaken for an unanswered question and re-prompted.
  bool get needsAsking => this == unknown;
}

/// What a stored answer means for whoever is signed in now.
///
/// **A yes belongs to the account that gave it, and nobody else.** The answer
/// used to be one word in a file for the whole phone, so it outlived the person
/// who gave it: sign out, let somebody else sign in, and their account was
/// backed up on the strength of a yes they never said -- with the first
/// runner's runs and traces pushed into it by the launch backfill. A phone
/// restored from an iCloud or Google backup brought the same word back with it.
///
/// So a grant is stored with the account that gave it ([givenBy]) and applies
/// only while that account is the one signed in ([signedIn]). It also stops
/// applying while the training on the phone belongs to a different account
/// ([owner], see `LocalDataGuard`): until somebody decides whose it is,
/// nothing on it may leave for anyone. A null owner is a phone nobody has
/// claimed yet, which the first account to sign in claims, so it does not
/// block.
///
/// **A no is a no for everybody.** It can never send anything, so there is
/// nobody it can harm, and a signed-out runner who declined is almost always
/// the same person who signs in later.
///
/// A grant with no account attached -- the one word this used to store --
/// reads as unknown and is asked again, because there is no way to know whose
/// yes it was.
BackupConsent consentFor(
  BackupConsent answer, {
  required String? givenBy,
  required String? signedIn,
  required String? owner,
}) {
  if (answer != BackupConsent.granted) return answer;
  if (signedIn == null || givenBy != signedIn) return BackupConsent.unknown;
  if (owner != null && owner != signedIn) return BackupConsent.unknown;
  return BackupConsent.granted;
}

/// Where the answer is kept.
///
/// **Local only, and that is not an oversight.** Storing consent on the server
/// would mean writing a record about the runner to the very place they may be
/// declining to send anything — and reading it back would mean a network call
/// before knowing whether a network call is allowed. It also gives the right
/// behaviour on a new phone: consent arrives unset, so nothing is uploaded and
/// nothing is restored until the runner says yes on that device. Re-consenting
/// on new hardware is the correct outcome, not friction to design away.
///
/// The real store reads its answer through [consentFor], so what [read]
/// returns is the answer *for the account signed in now*, not whatever the
/// phone last recorded.
abstract class BackupConsentStore {
  Future<BackupConsent> read();

  Future<void> write(BackupConsent consent);
}

/// An in-memory store, for tests and the preview harness.
class InMemoryBackupConsent implements BackupConsentStore {
  InMemoryBackupConsent([this._value = BackupConsent.unknown]);

  BackupConsent _value;

  @override
  Future<BackupConsent> read() async => _value;

  @override
  Future<void> write(BackupConsent consent) async => _value = consent;
}
