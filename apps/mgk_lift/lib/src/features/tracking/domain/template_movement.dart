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

/// What a session did to the **movements** of the workout it came from — the
/// only thing a session can now change about a workout (R3).
///
/// It replaced `TemplateUpdate`, which learned everything — set counts, order,
/// movements — applied at Finish with an Undo on the summary. The design review found that a
/// workout quietly rewriting itself was the wrong default, and that the thing
/// worth keeping was the one a lifter decides on purpose: *I dropped the flyes
/// and did dips instead.* So Finish asks one question, only when a movement
/// was added or removed (a swap reads as both), and yes changes only those.
/// Set counts, rep targets and order stay as the workout had them; a session
/// never changes them, and never asks about them.
///
/// Matched by name, case-insensitively, in order — a workout holding the same
/// movement twice matches each to its own — and with the learning table's
/// rules for what is not a change: a movement kept and skipped is not
/// removed, and one added and never done is not added.
class MovementChange {
  const MovementChange._({
    required this.added,
    required this.removed,
    required List<({TemplateMovement movement, int? after})> additions,
    required Set<int> removedAt,
  }) : _additions = additions,
       _removedAt = removedAt;

  factory MovementChange.between(
    List<TemplateMovement> before,
    Session session,
  ) {
    final unmatched = <int>[for (var i = 0; i < before.length; i++) i];
    final additions = <({TemplateMovement movement, int? after})>[];
    // The workout's movement the session last passed, so an added one lands
    // after it: "at its position", in the workout's own order.
    int? anchor;
    for (final e in session.exercises) {
      final key = e.name.toLowerCase();
      final at = unmatched.indexWhere(
        (i) => before[i].name.toLowerCase() == key,
      );
      if (at >= 0) {
        anchor = unmatched.removeAt(at);
        continue;
      }
      // Added today and never done: Finish drops it, and has said so.
      if (!e.sets.any((s) => s.isCompleted)) continue;
      final rows = e.sets.where((s) => !s.isWarmup).length;
      additions.add((
        movement: TemplateMovement(
          e.name,
          sets: rows == 0
              ? TemplateMovement.defaultSets
              : rows.clamp(1, SessionLimits.setsPerMovement),
        ),
        after: anchor,
      ));
    }
    return MovementChange._(
      added: <String>[for (final a in additions) a.movement.name],
      removed: <String>[for (final i in unmatched) before[i].name],
      additions: additions,
      removedAt: unmatched.toSet(),
    );
  }

  /// Movements done today that the workout does not have, in session order.
  final List<String> added;

  /// The workout's movements that were taken out of the session.
  final List<String> removed;

  final List<({TemplateMovement movement, int? after})> _additions;
  final Set<int> _removedAt;

  bool get isEmpty => added.isEmpty && removed.isEmpty;

  /// `+ Dips, − Cable Fly`: the line under the question.
  String describe() => <String>[
    for (final name in added) '+ $name',
    for (final name in removed) '− $name',
  ].join(', ');

  /// [before] — the workout as the session started from it — with only this
  /// change made: the removed movements gone, the added ones after the
  /// movement they followed in the session, everything else untouched.
  List<TemplateMovement> applyTo(List<TemplateMovement> before) {
    List<TemplateMovement> after(int? index) => <TemplateMovement>[
      for (final a in _additions)
        if (a.after == index) a.movement,
    ];
    return <TemplateMovement>[
      ...after(null),
      for (var i = 0; i < before.length; i++) ...<TemplateMovement>[
        if (!_removedAt.contains(i)) before[i],
        ...after(i),
      ],
    ];
  }
}
