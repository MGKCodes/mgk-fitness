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

/// Where the answer is kept.
///
/// **Local only, and that is not an oversight.** Storing consent on the server
/// would mean writing a record about the runner to the very place they may be
/// declining to send anything — and reading it back would mean a network call
/// before knowing whether a network call is allowed. It also gives the right
/// behaviour on a new phone: consent arrives unset, so nothing is uploaded and
/// nothing is restored until the runner says yes on that device. Re-consenting
/// on new hardware is the correct outcome, not friction to design away.
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
