/// Permission to send a lifter's training to the AI provider.
///
/// **Asked for, not assumed.** The coach cannot answer without sending what
/// the lifter wrote and a summary of their training, and some of that is
/// health information: injury notes, and what a body has been made to do.
/// That is special-category data under UK GDPR, whose lawful basis here is
/// explicit consent, and the privacy policy has said so since 2.0.0. App Store
/// guideline 5.1.2(i) asks for the same thing in its own words.
///
/// **What it replaces.** Lift 2.0.0 had a switch on the phone, `coach.enabled`,
/// on until somebody turned it off. On by default is not a yes, and a switch on
/// the phone is nothing the coach's server can check. So the answer moved to
/// the account, in the same shape and under the same rule as Run's (Run's
/// ADR-0036, issue #10), and 2.0.0's lifters are asked like everybody else. The
/// switch is still there, and still decides whether the coach is shown at all;
/// see `CoachPreferenceStore`.
///
/// **Per account, not per install.** The answer is about what happens to an
/// account's training, so a second phone does not ask again and a second
/// account on the same phone does. The medical disclaimer is the opposite
/// case, per install, and is kept in its own store for that reason.
///
/// **Versioned.** [kAiConsentVersion] goes up when what is sent, or where it
/// goes, changes enough that the lifter should be asked again. An answer given
/// to an older version reads as no answer.
library;

/// The version of the question the lifter is being asked.
///
/// Mirrored by `AI_CONSENT_VERSION` in `supabase/functions/coach/consent.ts`,
/// and by Run's: raise them together, or the server refuses an answer the app
/// accepts.
const int kAiConsentVersion = 1;

/// Where the answer is kept on the account, in auth user metadata.
///
/// **Namespaced by app.** One profile spans the suite, and agreeing to Run's
/// coach is not agreeing to Lift's. The coach's server reads this exact key,
/// and deleting Lift's data clears it, so it is not to be renamed.
const String kAiConsentMetadataKey = 'lift_ai_consent';

/// One answer: which version of the question, and when.
///
/// Stored as `{"version": 1, "at": "<ISO-8601 UTC>"}`. The date is there
/// because consent has to be demonstrable, not only true.
///
/// A **withdrawal** is version 0. It only ever exists on the phone, as a
/// decision the account has not heard about yet; on the account a withdrawal
/// is the key being removed.
class AiConsent {
  const AiConsent({required this.version, required this.at});

  /// Agreement to the question as it is asked today.
  AiConsent.now(DateTime now) : version = kAiConsentVersion, at = now.toUtc();

  /// A withdrawal, made at [now].
  AiConsent.withdrawn(DateTime now)
    : version = withdrawnVersion,
      at = now.toUtc();

  /// The version a withdrawal carries. Below every real version, so a
  /// withdrawal can never read as current.
  static const int withdrawnVersion = 0;

  final int version;

  /// When it was given, in UTC.
  final DateTime at;

  /// Whether this answers the question the app is asking today.
  bool get isCurrent => version >= kAiConsentVersion;

  bool get isWithdrawal => version == withdrawnVersion;

  Map<String, Object> toJson() => <String, Object>{
    'version': version,
    'at': at.toUtc().toIso8601String(),
  };

  /// The stored shape, or null for anything that is not one.
  ///
  /// **Unreadable is no answer.** A version that is not a number or a date
  /// that does not parse could be anything, and reading it as agreement would
  /// send health data on the strength of a malformed field.
  static AiConsent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final version = raw['version'];
    final at = raw['at'];
    if (version is! num || at is! String) return null;
    final parsed = DateTime.tryParse(at);
    if (parsed == null) return null;
    return AiConsent(version: version.toInt(), at: parsed.toUtc());
  }

  @override
  bool operator ==(Object other) =>
      other is AiConsent && other.version == version && other.at == at;

  @override
  int get hashCode => Object.hash(version, at);
}

/// Where the answer is read and written, for whoever is signed in.
///
/// Everything here is about **the signed-in account**. With nobody signed in
/// there is nobody to have agreed, so [isGranted] is false and the writes do
/// nothing; the coach needs an account anyway.
abstract interface class AiConsentStore {
  /// Whether the signed-in lifter has agreed to the current version.
  ///
  /// Must not throw. Anything that cannot be read is a no, which is the only
  /// safe direction for a question whose yes sends health data.
  Future<bool> isGranted();

  /// Records agreement to the current version.
  Future<void> grant();

  /// Takes the agreement back. The coach asks again before its next request.
  Future<void> withdraw();

  /// The coach's server read the account and found no yes, though this phone
  /// had one (`403 consent_required`).
  ///
  /// Two ways to get here: a yes given with no signal that has not reached the
  /// account yet, or a withdrawal made on another phone that has not reached
  /// this one. Either way the phone's answer was the wrong one to act on, so
  /// after this [isGranted] says no and the coach asks again, rather than
  /// every request meeting the same refusal.
  ///
  /// Must not throw: it is called on the way to reporting a refusal, and
  /// failing here would replace that with something less true.
  Future<void> refusedByAccount();
}

/// Whether [store] says yes, with a store that cannot answer read as no.
///
/// What the two clients ask before every request. The contract says
/// [AiConsentStore.isGranted] never throws; this holds even if one does.
Future<bool> consentGiven(AiConsentStore store) async {
  try {
    return await store.isGranted();
  } on Object {
    return false;
  }
}

/// Whether a refusal from the `coach` function is its consent check: a 403
/// whose body is `{"error": "consent_required"}`.
bool refusedForConsent(Object? details) =>
    details is Map && details['error'] == 'consent_required';

/// An [AiConsentStore] in memory, for tests and the preview harness.
///
/// Keyed by account like the real one. [userId] is asked on every call, so a
/// test can sign somebody else in halfway through.
class InMemoryAiConsentStore implements AiConsentStore {
  InMemoryAiConsentStore({String? Function()? userId, DateTime Function()? now})
    : _userId = userId ?? (() => _someone),
      _now = now ?? DateTime.now;

  /// Whoever is signed in has already agreed. For tests that are about
  /// something else and need the coach to open.
  factory InMemoryAiConsentStore.granted() =>
      InMemoryAiConsentStore()..seed(_someone, AiConsent.now(DateTime.now()));

  static const String _someone = 'someone';

  final String? Function() _userId;
  final DateTime Function() _now;
  final Map<String, AiConsent> _answers = <String, AiConsent>{};

  /// How many times each thing was done, so a test can say it happened once.
  int reads = 0;
  int grants = 0;
  int withdrawals = 0;

  /// What is stored for [userId], or null.
  AiConsent? answerFor(String userId) => _answers[userId];

  /// Stores [consent] for [userId] as though an earlier session had.
  void seed(String userId, AiConsent consent) => _answers[userId] = consent;

  @override
  Future<bool> isGranted() async {
    reads++;
    final id = _userId();
    if (id == null) return false;
    return _answers[id]?.isCurrent ?? false;
  }

  @override
  Future<void> grant() async {
    final id = _userId();
    if (id == null) return;
    grants++;
    _answers[id] = AiConsent.now(_now());
  }

  @override
  Future<void> withdraw() async {
    final id = _userId();
    if (id == null) return;
    withdrawals++;
    _answers.remove(id);
  }

  @override
  Future<void> refusedByAccount() async {
    final id = _userId();
    if (id == null) return;
    _answers.remove(id);
  }
}
