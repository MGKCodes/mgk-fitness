import '../../history/domain/run_draft.dart';
import '../domain/intake_conversation.dart';
import '../domain/intake_slots.dart';
import '../domain/goal_draft.dart';
import '../domain/plan_shape.dart';

/// Pure JSON ⇄ domain mapping for the coach `intake` surface. Kept free of
/// Supabase so it is testable without a network — the same split as
/// `history/data/run_mappers.dart`.
///
/// The wire format is metric throughout: distances in meters, durations in
/// seconds, dates as `YYYY-MM-DD`, weekdays as 1=Mon..7=Sun. The model
/// normalises the user's spoken units into these; Dart stores metric and
/// converts only at display (a load-bearing project rule).

/// The current slot state as the JSON context sent to the coach. Null slots are
/// dropped — "known" means present, so the model only sees what it already has.
Map<String, dynamic> intakeSlotsToContext(IntakeSlots s) {
  final days = s.availableWeekdays;
  final map = <String, dynamic>{
    'goal_distance_meters': s.goalDistanceMeters,
    'event_date': _dateToWire(s.eventDate),
    'current_weekly_meters': s.currentWeeklyMeters,
    'longest_recent_meters': s.longestRecentMeters,
    'shape': s.shape?.name,
    'days_per_week': s.daysPerWeek,
    'available_weekdays': days == null ? null : (days.toList()..sort()),
    'time_trial_distance_meters': s.timeTrialDistanceMeters,
    'time_trial_seconds': s.timeTrialDuration?.inSeconds,
    'injury_notes': s.injuryNotes,
  }..removeWhere((_, v) => v == null);
  return map;
}

/// The model's per-turn extraction → an [IntakeSlots] overlay. Every field is
/// tolerant of nulls and bad types: a malformed value simply stays unset, and
/// the conversation (or the editable confirmation screen) fills it later.
IntakeSlots intakeSlotsFromExtracted(Map<String, dynamic> m) => IntakeSlots(
  shape: _toShape(m['shape']),
  commitments: _toCommitments(m['commitments']),
  goalDistanceMeters: _toDouble(m['goal_distance_meters']),
  eventDate: _wireToDate(m['event_date']),
  currentWeeklyMeters: _toDouble(m['current_weekly_meters']),
  longestRecentMeters: _toDouble(m['longest_recent_meters']),
  daysPerWeek: _toInt(m['days_per_week']),
  availableWeekdays: _toDays(m['available_weekdays']),
  timeTrialDistanceMeters: _toDouble(m['time_trial_distance_meters']),
  timeTrialDuration: _toDuration(m['time_trial_seconds']),
  injuryNotes: _toText(m['injury_notes']),
);

/// The whole Edge Function response → an [IntakeTurn]. A missing or malformed
/// `extracted` degrades to an empty overlay rather than throwing.
IntakeTurn intakeTurnFromResponse(Map<String, dynamic> res) {
  final extracted = res['extracted'];
  return IntakeTurn(
    reply: res['reply'] is String ? res['reply'] as String : '',
    extracted: intakeSlotsFromExtracted(
      extracted is Map<String, dynamic> ? extracted : const <String, dynamic>{},
    ),
  );
}

/// The model's claim, or null if it named something this build does not know.
/// Null rather than a default: an unrecognised shape must not silently become a
/// block, which is the one that demands a date.
PlanShape? _toShape(Object? v) {
  if (v is! String) return null;
  for (final shape in PlanShape.values) {
    if (shape.name == v) return shape;
  }
  return null;
}

/// Null when absent so [IntakeSlots.merge] treats it as "no change" — an empty
/// list would mean "they have no commitments", which is a different claim.
List<PlanCommitment>? _toCommitments(Object? v) {
  if (v is! List) return null;
  final out = <PlanCommitment>[];
  for (final entry in v) {
    if (entry is! Map) continue;
    final weekday = _toInt(entry['weekday']);
    if (weekday == null) continue;
    out.add(
      PlanCommitment(
        weekday: weekday,
        distanceMeters: _toDouble(entry['distance_meters']),
        timed: entry['timed'] == true,
        label: _toText(entry['label']),
      ),
    );
  }
  return out;
}

String? _dateToWire(DateTime? d) => d?.toIso8601String().split('T').first;

DateTime? _wireToDate(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

double? _toDouble(Object? v) => v is num ? v.toDouble() : null;

int? _toInt(Object? v) => v is num ? v.toInt() : null;

String? _toText(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

Duration? _toDuration(Object? v) =>
    v is num ? Duration(seconds: v.toInt()) : null;

Set<int>? _toDays(Object? v) {
  if (v is! List) return null;
  final days = <int>{
    for (final e in v)
      if (e is num) e.toInt(),
  };
  return days.isEmpty ? null : days;
}

/// The `log_run` surface's answer as a [RunDraft].
///
/// Every field is optional on the wire because people do not talk in fields,
/// and a missing one is carried through as null rather than guessed at. The
/// draft is then checked by `RunDraft.issues`, which is where "you told me a
/// distance but not how long" becomes something the runner can see and fix.
///
/// A `when` the model could not resolve leaves `startedAt` null, which the
/// validator reports as "When was this run?" — better than defaulting to now,
/// which would silently date a Tuesday run to today.
RunDraft runDraftFromResponse(Map<String, dynamic> data) {
  final seconds = _int(data['duration_seconds']);
  return RunDraft(
    startedAt: _dateTime(data['when']),
    duration: seconds == null ? null : Duration(seconds: seconds),
    distanceMeters: _double(data['distance_meters']),
    // The wire allows only outdoor or treadmill; anything else, including null,
    // means the runner did not say, and manual is the honest label for a run
    // the app did not watch.
    type: switch (data['kind']) {
      kTypeOutdoor => kTypeOutdoor,
      kTypeTreadmill => kTypeTreadmill,
      _ => kTypeManual,
    },
    rpe: _int(data['rpe']),
    notes: _nonEmpty(data['notes']),
  );
}

double? _double(Object? v) => v is num ? v.toDouble() : null;

int? _int(Object? v) => v is num ? v.round() : null;

String? _nonEmpty(Object? v) {
  if (v is! String) return null;
  final trimmed = v.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _dateTime(Object? v) {
  if (v is! String) return null;
  return DateTime.tryParse(v.trim())?.toLocal();
}

/// A correction the coach heard: which day, and what changed.
///
/// The day rather than a run id, because the coach is never told an id —
/// `CoachBrief` speaks in relative days so it never quotes a database key at
/// the runner. Resolving a day to a row is Dart's job, and refusing when the
/// answer is not exactly one row is the safety (see [resolveRunOn]).
class RunCorrection {
  const RunCorrection({required this.on, required this.changes});

  /// The day of the run being corrected. Null when the model could not tell,
  /// which is a refusal rather than a reason to guess.
  final DateTime? on;

  /// Only what the runner restated. Every field null means nothing to do.
  final RunChanges changes;

  bool get isUsable => on != null && changes.isSomething;
}

/// The fields a correction may touch. Null is "leave it as it was".
class RunChanges {
  const RunChanges({this.distanceMeters, this.duration, this.rpe, this.notes});

  final double? distanceMeters;
  final Duration? duration;
  final int? rpe;
  final String? notes;

  bool get isSomething =>
      distanceMeters != null ||
      duration != null ||
      rpe != null ||
      notes != null;

  /// Applies these onto an existing draft, leaving untouched anything the
  /// runner did not restate.
  ///
  /// This is what makes "make it 6k" change the distance and nothing else. A
  /// correction that resent every field would overwrite the duration and the
  /// notes with the model's recollection of them.
  RunDraft onto(RunDraft existing) => existing.copyWith(
    distanceMeters: distanceMeters,
    duration: duration,
    rpe: rpe,
    notes: notes,
  );
}

/// The `edit_run` surface's answer.
RunCorrection runCorrectionFromResponse(Map<String, dynamic> data) {
  final changes = data['changes'];
  final c = changes is Map
      ? Map<String, dynamic>.from(changes)
      : const <String, dynamic>{};
  final seconds = _int(c['duration_seconds']);
  return RunCorrection(
    on: _dateTime(data['when']),
    changes: RunChanges(
      distanceMeters: _double(c['distance_meters']),
      duration: seconds == null ? null : Duration(seconds: seconds),
      rpe: _int(c['rpe']),
      notes: _nonEmpty(c['notes']),
    ),
  );
}

/// What the runner said about their target, as the `set_goal` surface read it.
///
/// Three states, not two, and the third is why this is not just a nullable pair.
/// A null distance means **they did not restate it** — "move the race to April"
/// leaves the marathon alone. [clearsGoal] means **they said they are stopping**,
/// which has to survive as a distinct answer: collapsing the two would make
/// every date change wipe the goal it was moving.
class GoalChange {
  const GoalChange({
    this.goalDistanceMeters,
    this.eventDate,
    this.clearsGoal = false,
  });

  /// The target distance in meters. Null means unchanged, never "none".
  final double? goalDistanceMeters;

  /// Race day. Null means unchanged, never "no race".
  final DateTime? eventDate;

  /// They are stepping off a goal entirely.
  final bool clearsGoal;

  /// False when the model read nothing usable, which is a question rather than
  /// a decision and must not raise a card.
  bool get isSomething =>
      clearsGoal || goalDistanceMeters != null || eventDate != null;

  /// Applies this onto the runner's current target.
  ///
  /// [clearsGoal] wins over everything: a runner who said they are done does
  /// not also keep a date. Otherwise each field falls back to what was already
  /// there, so what they did not mention survives.
  GoalDraft onto(GoalDraft existing) => clearsGoal
      ? const GoalDraft()
      : existing.copyWith(
          goalDistanceMeters: goalDistanceMeters,
          eventDate: eventDate,
        );
}

/// Reads the `set_goal` surface's answer. Anything unparseable becomes null,
/// which the caller treats as "nothing to propose".
GoalChange goalChangeFromResponse(Map<String, dynamic> data) => GoalChange(
  goalDistanceMeters: _double(data['goal_distance_meters']),
  eventDate: _dateTime(data['event_date']),
  clearsGoal: data['clears_goal'] == true,
);
