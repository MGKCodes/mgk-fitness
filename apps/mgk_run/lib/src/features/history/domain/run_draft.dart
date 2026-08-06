/// A run the runner is entering or correcting by hand, and the checks it has to
/// pass before it becomes a row.
///
/// This exists as a **pure, testable validator** rather than as form logic,
/// because it has two callers with very different trustworthiness. One is a
/// person typing into a field, who can see what they typed. The other is the
/// coach, proposing a run from a sentence like "I did 5k in 26 minutes this
/// morning" — and that is the model proposing, which means Dart has to dispose
/// (CLAUDE.md rule 2, ADR-0003).
///
/// So the rules live here, once, and both paths go through them. A form that
/// validated itself would leave the conversational path unguarded, which is
/// exactly the path where a misheard number does the most damage: the runner
/// never typed it, so they have no reason to check it.
///
/// Metric throughout — km only exist at the display layer (CLAUDE.md rule 4).
library;

/// Where a run came from. Recorded runs are `gps`; everything here is `manual`.
///
/// This is the run's **provenance** and is never edited, even when the numbers
/// are. It is what lets "a tracked run is a tracked run" stay true.
const String kSourceManual = 'manual';
const String kSourceGps = 'gps';

/// What kind of running it was. A treadmill run has no trace and no splits,
/// which is a normal state rather than missing data.
const String kTypeOutdoor = 'outdoor';
const String kTypeTreadmill = 'treadmill';
const String kTypeManual = 'manual';

const List<String> kRunTypes = <String>[
  kTypeOutdoor,
  kTypeTreadmill,
  kTypeManual,
];

/// One thing wrong with a draft, named by the field it belongs to so a form can
/// put the message under the right input. Mirrors `SlotIssue` from intake.
class RunIssue {
  const RunIssue(this.field, this.message);

  final String field;
  final String message;

  @override
  String toString() => '$field: $message';
}

/// A proposed run, before it is written.
///
/// Every numeric field is nullable so a partly-filled form and a partly-heard
/// sentence are the same shape. [issues] is what decides whether it may be
/// saved, not the presence of values.
class RunDraft {
  const RunDraft({
    this.startedAt,
    this.duration,
    this.distanceMeters,
    this.type = kTypeTreadmill,
    this.avgHr,
    this.rpe,
    this.notes,
  });

  final DateTime? startedAt;
  final Duration? duration;
  final double? distanceMeters;

  /// One of [kRunTypes]. Defaults to treadmill: it is the reason a runner
  /// reaches for manual entry in the first place, so it is the kind guess that
  /// saves the most taps.
  final String type;

  final int? avgHr;

  /// Rate of perceived exertion, 1 to 10. The one subjective field, and the
  /// only signal a treadmill run carries about how hard it actually was.
  final int? rpe;

  final String? notes;

  RunDraft copyWith({
    DateTime? startedAt,
    Duration? duration,
    double? distanceMeters,
    String? type,
    int? avgHr,
    int? rpe,
    String? notes,
  }) => RunDraft(
    startedAt: startedAt ?? this.startedAt,
    duration: duration ?? this.duration,
    distanceMeters: distanceMeters ?? this.distanceMeters,
    type: type ?? this.type,
    avgHr: avgHr ?? this.avgHr,
    rpe: rpe ?? this.rpe,
    notes: notes ?? this.notes,
  );

  /// Average pace, or null when it cannot be derived. Display only — the stored
  /// column is written from this so a run and its pace can never disagree.
  double? get avgPaceSecondsPerKm {
    final d = distanceMeters;
    final t = duration;
    if (d == null || t == null || d <= 0) return null;
    return t.inSeconds / (d / 1000);
  }

  /// Everything wrong with this draft, in field order.
  ///
  /// The bounds are deliberately **loose**. This is a plausibility check, not a
  /// judgement about the runner: someone walking a very slow recovery mile and
  /// someone running a road 10k are both legitimate, and a validator that
  /// refuses the first has decided what counts as running. What it is actually
  /// catching is a misplaced decimal, a misheard unit, and a model that
  /// confidently invented a number — the failures that corrupt a log quietly.
  List<RunIssue> issues(DateTime now) {
    final out = <RunIssue>[];

    final started = startedAt;
    if (started == null) {
      out.add(const RunIssue('started_at', 'When was this run?'));
    } else if (started.isAfter(now.add(const Duration(minutes: 5)))) {
      // Five minutes of slack, because a device clock a little ahead of the
      // server is not the runner claiming to have run tomorrow.
      out.add(const RunIssue('started_at', 'That is in the future.'));
    } else if (now.difference(started) > const Duration(days: 365 * 5)) {
      out.add(
        const RunIssue('started_at', 'That is more than five years ago.'),
      );
    }

    final d = distanceMeters;
    if (d == null) {
      out.add(const RunIssue('distance', 'How far did you go?'));
    } else if (d <= 0) {
      out.add(const RunIssue('distance', 'Distance has to be more than zero.'));
    } else if (d > 500000) {
      // Longer than any ultra anyone enters casually, and exactly what a
      // kilometres-typed-as-metres mistake looks like.
      out.add(
        const RunIssue('distance', 'That is over 500 km. Check the units.'),
      );
    }

    final t = duration;
    if (t == null) {
      out.add(const RunIssue('duration', 'How long did it take?'));
    } else if (t.inSeconds <= 0) {
      out.add(const RunIssue('duration', 'Duration has to be more than zero.'));
    } else if (t > const Duration(hours: 48)) {
      out.add(const RunIssue('duration', 'That is over 48 hours. Check it.'));
    }

    // Pace is only checked once both sides are sane, so a single bad field
    // produces one message rather than two that say the same thing.
    final pace = avgPaceSecondsPerKm;
    if (pace != null && out.isEmpty) {
      if (pace < 120) {
        out.add(
          const RunIssue(
            'distance',
            'That pace is faster than a world record.',
          ),
        );
      } else if (pace > 1800) {
        out.add(const RunIssue('duration', 'That is slower than 30 min/km.'));
      }
    }

    if (!kRunTypes.contains(type)) {
      out.add(const RunIssue('type', 'Unknown kind of run.'));
    }

    final hr = avgHr;
    if (hr != null && (hr < 30 || hr > 240)) {
      out.add(const RunIssue('avg_hr', 'Heart rate looks wrong.'));
    }

    final e = rpe;
    if (e != null && (e < 1 || e > 10)) {
      out.add(const RunIssue('rpe', 'Effort runs from 1 to 10.'));
    }

    return out;
  }

  /// Whether this draft may be written.
  bool isValid(DateTime now) => issues(now).isEmpty;
}

/// Thrown when a draft is written without passing its own checks.
///
/// In the domain beside [RunIssue] rather than beside the editor that throws
/// it, so a screen can catch it without importing the data layer — which is
/// what drags `dart:io` into a web build (see [RunWriter]).
///
/// Carries the issues rather than a message, so a confirmation can show the
/// runner exactly which number could not be accepted instead of failing with
/// something they cannot act on.
class RunDraftInvalid implements Exception {
  const RunDraftInvalid(this.issues);

  final List<RunIssue> issues;

  @override
  String toString() =>
      'RunDraftInvalid: ${issues.map((i) => i.toString()).join('; ')}';
}

/// The one run on [day], or null when that is not exactly one run.
///
/// **Refusing is the point.** The coach identifies a run by the day it happened
/// on, because it is never told a run's id. Two runs on the same day is an
/// ordinary thing — a morning easy run and an evening parkrun — and a model
/// asked to choose between them would choose. Choosing wrong means silently
/// rewriting a run the runner never mentioned, and the log looks entirely
/// normal afterwards, so nothing would ever surface it.
///
/// So: no match or several, no edit. The coach says it could not tell which
/// run, which is a sentence the runner can answer.
///
/// Compares calendar days in local time, since "yesterday's run" is a thing a
/// person says about their own day rather than about UTC.
T? soleRunOn<T>(
  Iterable<T> runs,
  DateTime day, {
  required DateTime Function(T) startedAt,
}) {
  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  T? found;
  for (final run in runs) {
    if (!sameDay(startedAt(run), day)) continue;
    if (found != null) return null; // more than one: refuse
    found = run;
  }
  return found;
}
