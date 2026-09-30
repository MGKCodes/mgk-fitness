/// Permission to send a runner's training to the AI provider.
///
/// **Asked for, not assumed.** The coach cannot answer without sending the
/// runner's training, and some of that is health information: special-category
/// data under UK GDPR, whose lawful basis here is explicit consent. The privacy
/// policy has said so since 2026-09-01, and until this existed nothing ever
/// collected it. App Store guideline 5.1.2(i) asks for the same thing in its own
/// words: say where personal data goes, including to a third-party AI, and get
/// permission before it goes.
///
/// **Per account, not per install.** The answer is about what happens to an
/// account's training, and it lives on the account, beside `run_intro_seen`, so
/// a second phone does not ask again and a second account on the same phone
/// does. The medical disclaimer is the opposite case, per install, and it is
/// kept in its own store for that reason.
///
/// **Versioned.** [kAiConsentVersion] goes up when what is sent, or where it
/// goes, changes enough that the runner should be asked again. An answer
/// given to an older version reads as no answer.
library;

/// The version of the question the runner is being asked.
///
/// Raise it when the coach starts sending something new, or sending it
/// somewhere new, and every runner is asked again before their next request.
const int kAiConsentVersion = 1;

/// Where the answer is kept on the account, in auth user metadata.
///
/// **Namespaced by app, like `run_intro_seen`.** One profile spans the suite,
/// and agreeing to Run's coach is not agreeing to Lift's. Account deletion
/// clears this exact key, so it is not to be renamed.
const String kAiConsentMetadataKey = 'run_ai_consent';

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
  /// Whether the signed-in runner has agreed to the current version.
  ///
  /// Must not throw. Anything that cannot be read is a no, which is the only
  /// safe direction for a question whose yes sends health data.
  Future<bool> isGranted();

  /// Records agreement to the current version.
  Future<void> grant();

  /// Takes the agreement back. The coach asks again before its next request.
  Future<void> withdraw();
}

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
}
