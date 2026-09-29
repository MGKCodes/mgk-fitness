import 'dart:convert';

import 'package:meta/meta.dart';

import 'previous_performance.dart';
import 'session.dart';

/// One movement in a saved workout: what to do, and how much of it.
///
/// **A set count and a rep target, never a weight** — decision D4 in
/// `docs/lift-2.0.0-logging-rework.md`, which revises "a saved workout says
/// what to do, not what to lift" rather than reversing it. Three sets of eight
/// is what to do. The weight is what to lift, and it comes from what this lifter
/// did last time, at the moment the session starts — so it is never stale.
///
/// Names only, the old shape, meant a session from a six-movement workout
/// opened as six empty cards: eighteen taps on "Add set" and a dozen typed
/// numbers before the first real tick.
@immutable
class TemplateMovement {
  const TemplateMovement(this.name, {this.sets = defaultSets, this.repTarget});

  /// The movement, by name — the same free text a session records.
  final String name;

  /// Working sets laid out when a session starts from the workout. One to
  /// [SessionLimits.setsPerMovement].
  final int sets;

  /// Reps each set aims for, or null for "whatever you did last time" — which
  /// is the honest target for most accessory work.
  final int? repTarget;

  /// What a movement added without a count gets. Liftio built three empty sets
  /// per movement, so the 47 templates already on the server read the same way.
  static const int defaultSets = 3;

  TemplateMovement copyWith({
    String? name,
    int? sets,
    int? Function()? repTarget,
  }) => TemplateMovement(
    name ?? this.name,
    sets: sets ?? this.sets,
    repTarget: repTarget == null ? this.repTarget : repTarget(),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'sets': sets,
    if (repTarget != null) 'reps': repTarget,
  };

  static TemplateMovement fromJson(Map<String, Object?> json) =>
      TemplateMovement(
        json['name']! as String,
        sets: (json['sets'] as num?)?.toInt() ?? defaultSets,
        repTarget: (json['reps'] as num?)?.toInt(),
      );

  /// A workout's movements as the snapshot column stores them.
  static String encode(List<TemplateMovement> movements) =>
      jsonEncode(<Object?>[for (final m in movements) m.toJson()]);

  /// The reverse; null for anything that is not a snapshot this wrote.
  static List<TemplateMovement>? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = jsonDecode(raw) as List<Object?>;
      return <TemplateMovement>[
        for (final item in list)
          TemplateMovement.fromJson((item! as Map).cast<String, Object?>()),
      ];
    } on Object {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TemplateMovement &&
      other.name == name &&
      other.sets == sets &&
      other.repTarget == repTarget;

  @override
  int get hashCode => Object.hash(name, sets, repTarget);

  @override
  String toString() => '$name ${sets}x${repTarget ?? '-'}';
}

/// The sets a session opens with for [movement], given what was lifted on it
/// [last] time.
///
/// Set *i* takes last time's set *i* — or the last one there was — for its
/// weight; its reps are the target when there is one, and last time's when not.
/// A movement never done opens with the right number of blank rows, which is
/// still one tap each fewer than before.
List<({int reps, double weightKg})> seedSets(
  TemplateMovement movement,
  PreviousPerformance? last,
) {
  final done = last?.sets ?? const <SessionSet>[];
  final count = movement.sets.clamp(1, SessionLimits.setsPerMovement);
  final seeds = <({int reps, double weightKg})>[];
  for (var i = 0; i < count; i++) {
    final from = done.isEmpty
        ? null
        : done[i < done.length ? i : done.length - 1];
    final reps = movement.repTarget ?? from?.reps ?? 0;
    final kg = from?.weightKg ?? 0;
    seeds.add((
      reps: reps.clamp(0, SessionLimits.maxReps),
      weightKg: kg.clamp(0, SessionLimits.maxWeightKg).toDouble(),
    ));
  }
  return seeds;
}

/// Every movement of a workout with its opening sets, from what this lifter
/// has lifted — what `SessionRecorder.fillFromLibrary` is handed.
List<({String name, List<({int reps, double weightKg})> sets})> seedWorkout(
  List<TemplateMovement> movements,
  List<Session> log,
) => <({String name, List<({int reps, double weightKg})> sets})>[
  for (final m in movements)
    (name: m.name, sets: seedSets(m, PreviousPerformance.of(log, m.name))),
];

/// When a saved workout was last done, from the sessions started from it —
/// `Last done Tuesday` on its row. Null for one never done.
DateTime? lastDone(String workoutId, List<Session> log) {
  DateTime? latest;
  for (final s in log) {
    if (s.templateId != workoutId || s.isInProgress) continue;
    if (latest == null || s.startedAt.isAfter(latest)) latest = s.startedAt;
  }
  return latest;
}

/// A finished session as a saved workout's movements: each movement once, in
/// order, with as many sets as were worked — what "Save to your workouts"
/// keeps. A movement done twice is one movement.
List<TemplateMovement> movementsOf(Session session) {
  final seen = <String>{};
  return <TemplateMovement>[
    for (final e in session.exercises)
      if (seen.add(e.name.toLowerCase()))
        TemplateMovement(
          e.name,
          sets: () {
            final rows = e.sets.where((s) => !s.isWarmup).length;
            return rows == 0
                ? TemplateMovement.defaultSets
                : rows.clamp(1, SessionLimits.setsPerMovement);
          }(),
        ),
  ];
}

/// What changed between the workout a session started from and the session as
/// it finished — the rule that lets a template **learn from the session**, so
/// a movement removed today does not have to be removed again next week.
///
/// The table in `docs/lift-2.0.0-logging-rework.md`, Phase 3:
///
/// | In the session | The template |
/// |---|---|
/// | movement removed with ✕ | removed |
/// | movement added, and done | added, at the same position |
/// | movement added, nothing ticked | not added — Finish drops it |
/// | movements reordered | new order |
/// | set rows added or removed | the set count follows |
/// | movement kept, nothing ticked | unchanged — skipping is not removing |
/// | sets left unticked | unchanged — a skipped set is not a removed one |
/// | reps and weights | never changed by a session |
/// | warm-ups | not part of a template |
///
/// It reads the session **before** Finish drops its unticked sets — a row left
/// unticked is still a row the lifter kept, so it still counts.
@immutable
class TemplateUpdate {
  const TemplateUpdate._({
    required this.before,
    required this.after,
    required this.removed,
    required this.added,
    required this.reordered,
    required this.resized,
  });

  /// Compares the workout as it was when the session started with the session.
  ///
  /// Movements are matched by name, case-insensitively, in order — so a
  /// workout holding the same movement twice matches each to its own.
  factory TemplateUpdate.between(
    List<TemplateMovement> before,
    Session session,
  ) {
    final unmatched = <int>[for (var i = 0; i < before.length; i++) i];
    final matchedFrom = <int>[];
    final after = <TemplateMovement>[];
    final added = <String>[];
    final resized = <String>[];

    for (final e in session.exercises) {
      final key = e.name.toLowerCase();
      final at = unmatched.indexWhere(
        (i) => before[i].name.toLowerCase() == key,
      );
      final index = at < 0 ? null : unmatched.removeAt(at);
      final was = index == null ? null : before[index];
      // A movement added today and never done is not part of the workout —
      // Finish drops it from the session, and has just told the lifter so.
      if (was == null && !e.sets.any((s) => s.isCompleted)) continue;
      // By position, not by value: two identical entries are two movements.
      if (index != null) matchedFrom.add(index);
      final rows = e.sets.where((s) => !s.isWarmup).length;
      // Nothing laid out at all is a movement not started, not one with its
      // sets removed: the count stays as it was.
      final sets = rows == 0
          ? (was?.sets ?? TemplateMovement.defaultSets)
          : rows.clamp(1, SessionLimits.setsPerMovement);
      if (was == null) {
        added.add(e.name);
      } else if (was.sets != sets) {
        resized.add(e.name);
      }
      after.add(
        TemplateMovement(e.name, sets: sets, repTarget: was?.repTarget),
      );
    }

    final removed = <String>[for (final i in unmatched) before[i].name];
    var reordered = false;
    for (var i = 1; i < matchedFrom.length; i++) {
      if (matchedFrom[i] < matchedFrom[i - 1]) reordered = true;
    }

    return TemplateUpdate._(
      before: List<TemplateMovement>.unmodifiable(before),
      after: List<TemplateMovement>.unmodifiable(after),
      removed: removed,
      added: added,
      reordered: reordered,
      resized: resized,
    );
  }

  final List<TemplateMovement> before;
  final List<TemplateMovement> after;
  final List<String> removed;
  final List<String> added;
  final bool reordered;

  /// Movements whose set count changed.
  final List<String> resized;

  bool get isEmpty =>
      removed.isEmpty && added.isEmpty && !reordered && resized.isEmpty;

  /// `removed Cable Fly, added Dips` — the line under the summary's totals.
  String describe() {
    final parts = <String>[
      if (removed.isNotEmpty) 'removed ${_list(removed)}',
      if (added.isNotEmpty) 'added ${_list(added)}',
      if (resized.isNotEmpty) 'new set count on ${_list(resized)}',
      if (reordered) 'new order',
    ];
    return parts.join(', ');
  }

  static String _list(List<String> names) => switch (names.length) {
    1 => names.single,
    2 => '${names[0]} and ${names[1]}',
    _ => '${names[0]} and ${names.length - 1} more',
  };
}
