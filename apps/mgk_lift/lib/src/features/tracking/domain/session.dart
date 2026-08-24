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
  });

  final String id;
  final String name;
  final DateTime startedAt;

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
