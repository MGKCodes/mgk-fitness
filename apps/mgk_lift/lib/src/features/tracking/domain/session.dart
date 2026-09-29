import 'package:meta/meta.dart';

/// A training session, as the app thinks about it rather than as it is stored.
///
/// Immutable: the recorder produces a new one on every change, so a widget can
/// never be holding a session that has quietly moved underneath it.
@immutable
class Session {
  const Session({
    required this.id,
    required this.name,
    required this.startedAt,
    this.endedAt,
    this.notes,
    this.exercises = const <SessionExercise>[],
    this.templateId,
    this.templateSnapshot,
  });

  final String id;
  final String name;
  final DateTime startedAt;

  /// The saved workout this session was started from, if any.
  final String? templateId;

  /// That workout as it stood when the session started — what the session is
  /// compared against at Finish, so the workout can learn from it. See
  /// `TemplateUpdate`. Kept on this device only; nothing uploads it.
  ///
  /// Raw rather than decoded so the domain type here stays free of the
  /// template's; `TemplateMovement.decode` reads it.
  final String? templateSnapshot;

  /// Null while the session is in progress. This is the whole crash-recovery
  /// mechanism: on launch, a workout row with no `endedAt` is a session that was
  /// interrupted rather than finished, and it is offered back rather than lost.
  final DateTime? endedAt;

  final String? notes;
  final List<SessionExercise> exercises;

  bool get isInProgress => endedAt == null;

  /// How long the session ran. Read from the clock while in progress, so a
  /// screen showing it does not need the recorder to tick.
  Duration elapsedAt(DateTime now) =>
      (endedAt ?? now).difference(startedAt).abs();

  /// The sets that count toward anything: performed, and not warm-ups.
  ///
  /// **The single definition of "counts", for the whole app.** It lived in two
  /// places for a while — here and in `TrainingStats` — and they disagreed:
  /// the session header counted warm-ups in its volume while Profile did not,
  /// so the same lifter saw two different totals depending which screen they
  /// were on. Anything reporting a number folds over this.
  Iterable<SessionSet> get workingSets =>
      exercises.expand((e) => e.workingSets);

  /// Total load moved: reps × weight.
  ///
  /// Planned-but-not-performed sets are excluded because counting them would
  /// let a lifter inflate the figure by adding rows they never lifted.
  /// Warm-ups are excluded because three empty-bar sets before a heavy single
  /// should not read as a bigger session than the single.
  double get volumeKg =>
      workingSets.fold(0, (sum, s) => sum + (s.reps * s.weightKg));

  int get completedSets => workingSets.length;

  int get totalSets => exercises.fold(0, (sum, e) => sum + e.sets.length);

  /// Sets on the page that have not been ticked — what Finish will drop.
  int get untickedSets => exercises.fold(
    0,
    (sum, e) => sum + e.sets.where((s) => !s.isCompleted).length,
  );

  // ---- the same change the recorder makes, made to this copy ---------------
  //
  // The session screen shows a change the moment it is made and writes it
  // behind, so it needs to make the recorder's change to its own copy first.
  // These mirror the recorder's rules — contiguous numbers and positions — so
  // the copy on screen and the rows on disk agree before storage answers, not
  // only after.

  Session withExercises(List<SessionExercise> exercises) => Session(
    id: id,
    name: name,
    startedAt: startedAt,
    endedAt: endedAt,
    notes: notes,
    exercises: exercises,
    templateId: templateId,
    templateSnapshot: templateSnapshot,
  );

  /// This session with one set changed by [change].
  Session mapSet(String setId, SessionSet Function(SessionSet set) change) =>
      withExercises(<SessionExercise>[
        for (final e in exercises)
          e.sets.any((s) => s.id == setId)
              ? e.withSets(<SessionSet>[
                  for (final s in e.sets) s.id == setId ? change(s) : s,
                ])
              : e,
      ]);

  /// This session without one set; the movement's sets renumber.
  Session withoutSet(String setId) => withExercises(<SessionExercise>[
    for (final e in exercises)
      e.sets.any((s) => s.id == setId)
          ? e.withSets(<SessionSet>[
              for (final s in e.sets)
                if (s.id != setId) s,
            ])
          : e,
  ]);

  /// This session with [set] back in movement [exerciseId], at its number.
  Session withSetRestored(String exerciseId, SessionSet set) =>
      withExercises(<SessionExercise>[
        for (final e in exercises)
          e.id == exerciseId
              ? e.withSets(
                  <SessionSet>[...e.sets]
                    ..insert((set.setNumber - 1).clamp(0, e.sets.length), set),
                )
              : e,
      ]);

  /// This session without one movement; positions close up.
  Session withoutExercise(String exerciseId) => withExercises(
    _positioned(<SessionExercise>[
      for (final e in exercises)
        if (e.id != exerciseId) e,
    ]),
  );

  /// This session with [exercise] back at its position.
  Session withExerciseRestored(SessionExercise exercise) => withExercises(
    _positioned(
      <SessionExercise>[...exercises]
        ..insert(exercise.orderIndex.clamp(0, exercises.length), exercise),
    ),
  );

  static List<SessionExercise> _positioned(List<SessionExercise> list) =>
      <SessionExercise>[
        for (var i = 0; i < list.length; i++) list[i].atPosition(i),
      ];
}

/// One movement within a session.
@immutable
class SessionExercise {
  const SessionExercise({
    required this.id,
    required this.name,
    required this.orderIndex,
    this.notes,
    this.cardioMode,
    this.sets = const <SessionSet>[],
  });

  final String id;
  final String name;
  final int orderIndex;
  final String? notes;

  /// Set when this movement is measured in time and distance rather than reps
  /// and load.
  final String? cardioMode;

  final List<SessionSet> sets;

  /// Performed, and not a warm-up. See [Session.workingSets].
  Iterable<SessionSet> get workingSets =>
      sets.where((s) => s.isCompleted && !s.isWarmup);

  /// Every set on this movement has been ticked.
  ///
  /// Warm-ups count here, unlike everywhere else — this is about whether the
  /// lifter is *finished with the movement*, not about what goes in their
  /// totals. Drives the card collapsing to a one-line summary once there is
  /// nothing left to do on it.
  ///
  /// A movement with no sets is **not** complete: it has not been started.
  bool get isComplete => sets.isNotEmpty && sets.every((s) => s.isCompleted);

  bool get isCardio => cardioMode != null;

  /// Whether another set can be added — see [SessionLimits.setsPerMovement].
  bool get canAddSet => sets.length < SessionLimits.setsPerMovement;

  /// This movement holding [next], renumbered from one — the recorder's rule.
  SessionExercise withSets(List<SessionSet> next) => SessionExercise(
    id: id,
    name: name,
    orderIndex: orderIndex,
    notes: notes,
    cardioMode: cardioMode,
    sets: <SessionSet>[
      for (var i = 0; i < next.length; i++) next[i].numbered(i + 1),
    ],
  );

  /// This movement at [position] in its session.
  SessionExercise atPosition(int position) => position == orderIndex
      ? this
      : SessionExercise(
          id: id,
          name: name,
          orderIndex: position,
          notes: notes,
          cardioMode: cardioMode,
          sets: sets,
        );

  /// The heaviest working set, for the one-line summary a collapsed exercise
  /// shows. Null when nothing has been performed yet — which reads as "not
  /// started", not as zero.
  ///
  /// Warm-ups excluded, or a heavy-ish warm-up on a bad day could be reported
  /// as the best of the session.
  SessionSet? get topSet {
    final done = workingSets.toList();
    if (done.isEmpty) return null;
    return done.reduce((a, b) => b.weightKg > a.weightKg ? b : a);
  }

  /// What the first column of [set]'s row reads: `W`, `D` or `F` for a marked
  /// set, and otherwise its number **among the ordinary working sets** —
  /// `W, 1, 2, D, 3`.
  ///
  /// **The one definition, for every screen that numbers a set.** Both used to
  /// print `setNumber`, which is a storage position, so a warm-up took the
  /// number 1 and the first real set read "2" — a lifter's "three sets of
  /// five" came out as `W, 2, 3, 4`. Found by photographing the screen.
  String labelFor(SessionSet set) {
    final marker = set.setType.marker;
    if (marker != null) return marker;
    var n = 0;
    for (final s in sets) {
      if (s.setType == SetType.working) n++;
      if (s.id == set.id) return '$n';
    }
    // Not one of this movement's sets. The storage position is the only honest
    // answer left, and it cannot happen from any caller that passes its own.
    return '${set.setNumber}';
  }
}

/// How much one session can hold, and how big a number can be.
///
/// **Limits catch typing, not training.** Every one sits well past anything a
/// real session reaches, so it only ever meets a slipped thumb — 1,000 reps for
/// 10, a weight with an extra zero. A value past a limit is refused where it is
/// typed and never silently clamped: a clamped number is a quietly wrong one,
/// which is worse than a refusal the lifter can see.
///
/// Numbers from `docs/lift-2.0.0-logging-rework.md`, decision D2.
abstract final class SessionLimits {
  /// Covers the longest drop-set chains; stops a runaway "Add set".
  static const int setsPerMovement = 20;

  /// A long session is about twelve.
  static const int movements = 30;

  /// A three-digit field. Nothing heavier than a calf raise gets near it.
  static const int maxReps = 200;

  /// Above any sled a gym owns. Zero is legal: it is bodyweight.
  static const double maxWeightKg = 1000;

  /// One line on every screen that shows a name.
  static const int nameLength = 60;
}

/// Thrown when a change would take a session past one of [SessionLimits].
///
/// The screen disables the control before this can happen; the recorder
/// refuses anyway, because a limit enforced only by a button is not a limit.
class SessionLimitReached implements Exception {
  const SessionLimitReached(this.what);

  /// Which limit, in words — `20 sets`.
  final String what;

  @override
  String toString() => 'Limit reached: $what.';
}

/// One working set.
@immutable
class SessionSet {
  const SessionSet({
    required this.id,
    required this.setNumber,
    this.reps = 0,
    this.weightKg = 0,
    this.isCompleted = false,
    this.setType = SetType.working,
    this.durationS,
    this.distanceM,
  });

  final String id;
  final int setNumber;
  final int reps;

  /// Working or warm-up. Warm-ups are logged — they happened — but excluded
  /// from volume and from every personal best, because three empty-bar sets
  /// before a heavy single should not read as a bigger session than the single.
  final SetType setType;

  bool get isWarmup => setType == SetType.warmup;

  /// **Kilograms.** Store metric, convert at display — a lifter switching to
  /// pounds must not change what their history means.
  final double weightKg;

  /// Whether it was actually performed. A set row appears the moment it is
  /// added so the lifter can see and edit it; this is the tick that says it
  /// happened.
  final bool isCompleted;

  final int? durationS;
  final double? distanceM;

  /// This set at [number] in its movement.
  SessionSet numbered(int number) => number == setNumber
      ? this
      : SessionSet(
          id: id,
          setNumber: number,
          reps: reps,
          weightKg: weightKg,
          isCompleted: isCompleted,
          setType: setType,
          durationS: durationS,
          distanceM: distanceM,
        );

  SessionSet copyWith({
    int? reps,
    double? weightKg,
    bool? isCompleted,
    SetType? setType,
    int? durationS,
    double? distanceM,
  }) => SessionSet(
    id: id,
    setNumber: setNumber,
    reps: reps ?? this.reps,
    weightKg: weightKg ?? this.weightKg,
    isCompleted: isCompleted ?? this.isCompleted,
    setType: setType ?? this.setType,
    durationS: durationS ?? this.durationS,
    distanceM: distanceM ?? this.distanceM,
  );
}

/// What a set was for.
///
/// **All four of Liftio's, and the stored strings are Liftio's too.** The port
/// carried the interaction — tap the set number to change its type — and only
/// two of the four types, which had a consequence nobody had spotted:
/// `fromStored` mapped every unrecognised value to [working], so the
/// `dropset` and `failure` rows already sitting in the cloud from the shipped
/// app were being read back as ordinary working sets. Restoring the types is
/// therefore a data-fidelity fix as much as a feature.
///
/// Liftio wrote `null` for a working set and this app writes `'working'`; both
/// read back as [working], so the two are compatible in either direction
/// without a migration.
enum SetType {
  working('working', marker: null, label: 'a working set'),
  warmup('warmup', marker: 'W', label: 'a warm-up'),
  dropSet('dropset', marker: 'D', label: 'a drop set'),
  failure('failure', marker: 'F', label: 'taken to failure');

  const SetType(this.stored, {required this.marker, required this.label});

  /// The value in the database. Unknown values read as [working], so a set is
  /// only ever discounted from a lifter's totals deliberately.
  final String stored;

  /// The single letter shown in place of the set number, or null for a working
  /// set, which shows its number. One character because the column is 28px
  /// wide and shares its row with two number fields and a tick.
  final String? marker;

  /// How a tooltip names it, in a sentence reading "Mark this as …".
  final String label;

  /// The next type in the cycle, since the control is one tap target rather
  /// than a menu — which is how Liftio did it, and how this app already did
  /// it for the two types it had.
  SetType get next => switch (this) {
    SetType.working => SetType.warmup,
    SetType.warmup => SetType.dropSet,
    SetType.dropSet => SetType.failure,
    SetType.failure => SetType.working,
  };

  static SetType fromStored(String? value) => switch (value) {
    'warmup' => SetType.warmup,
    'dropset' => SetType.dropSet,
    'failure' => SetType.failure,
    _ => SetType.working,
  };
}
