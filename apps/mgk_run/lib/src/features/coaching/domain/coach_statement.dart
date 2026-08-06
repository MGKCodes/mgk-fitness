import 'dart:math' as math;

/// Checks a **generated** line of coach prose against the facts it was given,
/// and falls back to the computed line when it does not hold up.
///
/// The same bargain as plans (ADR-0003, CLAUDE.md rule 2): the model proposes,
/// Dart disposes. A plan is checked by measuring its numbers against rules; a
/// sentence is checked by making sure every number in it came from the app and
/// every boast in it is one the runner actually earned.
///
/// **Why generate at all**, when Dart can already write the line: because the
/// computed version is the same sentence every time. A standing is stable for
/// weeks by design, so a runner opening the tab sees identical words all month,
/// which reads as a machine doing an impression of noticing. Generated prose
/// varies; validation is what keeps it honest while it does.
///
/// The trick is to never ask for free prose. The model is handed a small set of
/// facts and asked to phrase *those*, which is what makes the checks below
/// possible at all — and all of them are deterministic, so validating costs no
/// second model call.
///
/// What is deliberately **not** checked: whether the line is any good. That is
/// what the eval pass is for. This only decides whether it is safe to show.
class CoachStatement {
  const CoachStatement._();

  /// Picks between a generated line and the computed one.
  ///
  /// [generated] may be null — no coach configured, the call failed, the
  /// allowance is spent, or the device is offline. All four land on [fallback],
  /// which is why the computed line still earns its place.
  static StatementResult choose({
    required String? generated,
    required StatementFacts facts,
    required String fallback,
  }) {
    if (generated == null || generated.trim().isEmpty) {
      return StatementResult._(
        text: fallback,
        source: StatementSource.fallback,
        problems: const <String>['nothing was generated'],
      );
    }

    final problems = check(generated, facts);
    if (problems.isEmpty) {
      return StatementResult._(
        text: generated.trim(),
        source: StatementSource.model,
        problems: const <String>[],
      );
    }
    return StatementResult._(
      text: fallback,
      source: StatementSource.fallback,
      problems: problems,
    );
  }

  /// Everything wrong with [text], or empty when it is safe to show.
  ///
  /// Returns all problems rather than the first, so a retry can be told
  /// everything to fix at once — the same reason the plan validator does.
  static List<String> check(String text, StatementFacts facts) {
    final problems = <String>[];
    final trimmed = text.trim();

    if (trimmed.length > facts.maxLength) {
      problems.add(
        'too long: ${trimmed.length} characters, limit ${facts.maxLength}',
      );
    }
    if (_listShaped.hasMatch(trimmed)) {
      problems.add('formatted as a list; this is one short paragraph');
    }

    problems.addAll(_unsupportedNumbers(trimmed, facts));
    problems.addAll(_unearnedClaims(trimmed, facts));
    problems.addAll(_forbidden(trimmed));

    return problems;
  }

  /// Every number in the line has to be one the app handed over.
  ///
  /// The failure this exists for: a model that adds two figures from the brief
  /// and states the total, or simply invents one. Both come out fluent and
  /// confident, and the runner has no way to tell. Rounding to fewer digits is
  /// allowed — "5 km" for 5.23 km is what a coach would say — but a number that
  /// matches nothing is not.
  static List<String> _unsupportedNumbers(String text, StatementFacts facts) {
    final problems = <String>[];

    // Times first, else "5:03" reads as the two numbers 5 and 3.
    var remaining = text;
    for (final match in _clockTime.allMatches(text)) {
      final parts = match.group(0)!.split(':').map(int.parse).toList();
      final seconds = parts.length == 3
          ? parts[0] * 3600 + parts[1] * 60 + parts[2]
          : parts[0] * 60 + parts[1];
      final ok = facts.allowedSeconds.any((a) => (a - seconds).abs() <= 1);
      if (!ok) problems.add('unsupported time "${match.group(0)}"');
      remaining = remaining.replaceFirst(match.group(0)!, ' ');
    }

    for (final match in _number.allMatches(remaining)) {
      final written = match.group(0)!;
      final value = double.parse(written);
      final decimals = written.contains('.')
          ? written.split('.').last.length
          : 0;
      final ok = facts.allowedNumbers.any(
        (a) => _numberMatches(value, decimals, a),
      );
      if (!ok) problems.add('unsupported number "$written"');
    }

    return problems;
  }

  /// True when [written], to the precision it was written at, is [allowed].
  static bool _numberMatches(double written, int decimals, num allowed) {
    if ((written - allowed).abs() <= 0.05) return true;
    final factor = math.pow(10, decimals);
    return (allowed * factor).round() / factor == written;
  }

  /// A superlative is a claim about the runner's whole history, and the model
  /// has only seen a slice of it. It may only say "longest" when Dart has
  /// established that it was.
  ///
  /// This is the case `CoachNote` warns about in its own doc: a note must never
  /// congratulate someone on a personal best they did not set. That is worse
  /// than a wrong number, because the runner has no reason to doubt it and
  /// every reason to enjoy it.
  static List<String> _unearnedClaims(String text, StatementFacts facts) {
    final lower = text.toLowerCase();
    final problems = <String>[];
    for (final entry in _claimWords.entries) {
      if (!entry.value.hasMatch(lower)) continue;
      if (facts.claims.contains(entry.key)) continue;
      problems.add('claims ${entry.key.name} without it being true');
    }
    return problems;
  }

  static List<String> _forbidden(String text) {
    final lower = text.toLowerCase();
    return <String>[
      for (final entry in _forbiddenPhrases.entries)
        if (entry.value.hasMatch(lower)) entry.key,
    ];
  }

  static final RegExp _clockTime = RegExp(r'\b\d{1,3}:\d{2}(?::\d{2})?\b');
  static final RegExp _number = RegExp(r'\d+(?:\.\d+)?');
  static final RegExp _listShaped = RegExp(r'(^|\n)\s*(?:[-*•]|\d+[.)])\s');

  /// Superlatives, and the claim each one requires. Comparatives are absent on
  /// purpose: "quicker than last month" is a comparison the app supplies, while
  /// "quickest ever" is a claim about everything the runner has ever done.
  static final Map<StatementClaim, RegExp> _claimWords =
      <StatementClaim, RegExp>{
        StatementClaim.longestRun: RegExp(
          r'\b(longest|furthest|farthest)\b|\bfurther than (you|they) ever\b',
        ),
        StatementClaim.fastestPace: RegExp(
          r'\b(fastest|quickest)\b|\bpersonal best\b|\bpb\b',
        ),
        // "Record" the noun, not the verb. A bare \brecord\b also matched
        // "record a run", which is an invitation rather than a boast — the
        // computed empty-state line was refused by its own validator until an
        // article was required here.
        StatementClaim.anyRecord: RegExp(
          r'\b(a|the|new|personal|your|another) record\b|'
          r'\brecord (time|distance|pace)\b|'
          r'\bbest ever\b|\bnever (been |run )?(faster|further)\b',
        ),
      };

  /// Lines that must never appear whatever the facts say.
  ///
  /// The comparison rules are the card's whole argument (it is you versus you)
  /// and the app has no other runner's data to compare against anyway. The
  /// named-system rules are CLAUDE.md rule 5: this repo is public and those
  /// tables and schedules are copyrighted, so a model reciting one from memory
  /// is a licensing problem as well as a coaching one.
  static final Map<String, RegExp> _forbiddenPhrases = <String, RegExp>{
    'ranks the runner against other people': RegExp(
      r'percentile|top \d+ ?%|faster than \d+ ?%|average runner|typical runner|'
      r'most runners|other runners|compared to runners',
    ),
    'grades the runner by age': RegExp(r'age.?grade|for (a runner )?your age'),
    'cites research it cannot show': RegExp(
      r'studies show|research shows|science says|studies suggest',
    ),
    'names a copyrighted training system': RegExp(
      r'\bvdot\b|\bdaniels\b|\bpfitzinger\b|\bhansons?\b|\bhal higdon\b|'
      r'\bjack daniels\b',
    ),
    'prescribes training outside the plan': RegExp(
      r'\byou should run\b.*\b(tomorrow|today|this week)\b|'
      r'\b\d+ ?x ?\d+\b|\bintervals? of\b',
    ),
  };
}

/// What a generated line is allowed to say.
class StatementFacts {
  const StatementFacts({
    this.allowedNumbers = const <num>{},
    this.allowedSeconds = const <int>{},
    this.claims = const <StatementClaim>{},
    this.maxLength = 400,
  });

  /// Every plain number the line may contain — distances, counts, days.
  ///
  /// Supplied by the caller rather than parsed out of the fallback, so that
  /// structural numbers ("four weeks" written as "4 weeks") are a deliberate
  /// inclusion rather than an accident of phrasing.
  final Set<num> allowedNumbers;

  /// Every clock time the line may contain, in seconds — paces and durations.
  final Set<int> allowedSeconds;

  /// The superlatives the runner has actually earned.
  final Set<StatementClaim> claims;

  final int maxLength;
}

/// A claim about the runner's whole history, which only Dart can establish.
enum StatementClaim { longestRun, fastestPace, anyRecord }

/// Where the shown line came from. Mirrors [PlanSource] deliberately: the same
/// bargain, applied to prose instead of a plan.
enum StatementSource { model, fallback }

/// The line to show, and how it was arrived at.
class StatementResult {
  const StatementResult._({
    required this.text,
    required this.source,
    required this.problems,
  });

  final String text;
  final StatementSource source;

  /// Why the generated line was refused, when it was. Kept rather than dropped
  /// so a retry can be told what to fix, and so the eval pass can count how
  /// often a given model fails and on what.
  final List<String> problems;

  bool get usedModel => source == StatementSource.model;
}
