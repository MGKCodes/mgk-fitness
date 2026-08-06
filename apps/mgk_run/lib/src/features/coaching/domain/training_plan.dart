/// Training block phases (the arc of a plan).
enum Phase { base, build, peak, taper }

/// The kind of a planned session.
///
/// **[strength] is deliberately empty of prescription.** Runio plans running;
/// what a strength session contains is Liftio's job, and duplicating it here
/// would give a runner two apps disagreeing about the same workout. The plan
/// says *when*, not *what* — see docs/decisions/0010-strength-sessions-not-prescribed.md.
///
/// There is no `treadmill` kind, and there should not be: a treadmill is a
/// *venue*, not a session. A 6 km easy run is the same session indoors or out,
/// and a plan that prescribed the machine would be telling the runner something
/// it has no business deciding.
enum SessionKind {
  rest,
  recovery,
  easy,
  long,
  marathonPace,
  threshold,
  interval,

  /// A fixed distance run at race effort, repeated — a parkrun, a weekly mile.
  ///
  /// Its own kind because calling it a threshold session gives a runner the
  /// wrong instruction: threshold is an effort you could hold for about an
  /// hour, and nobody runs their parkrun that way. It is also the thing a
  /// runner without a race measures themselves by, which is why a
  /// [PlanShape.rhythm] revolves around one.
  timeTrial,
  strength;

  /// Quality sessions that stress the runner and must not land on consecutive
  /// days.
  bool get isHard => this == threshold || this == interval || this == timeTrial;

  /// Whether this session contributes to running volume.
  ///
  /// Strength is a session but not a run: counting it would put a zero into
  /// every weekly total, make it eligible to be the "long run", and spend one of
  /// the runner's stated running days on a session they do in a gym.
  bool get isRun => this != rest && this != strength;

  /// Sessions that occupy a day without adding kilometres.
  bool get isSupport => this == strength;
}

/// One week of the **skeleton** — the arc, generated once at plan creation and
/// shown to the user in full (docs/architecture/plan-generation.md).
class SkeletonWeek {
  const SkeletonWeek({
    required this.index,
    required this.phase,
    required this.volumeMeters,
    required this.longRunMeters,
    this.isDeload = false,
  });

  /// 1-based position in the plan.
  final int index;
  final Phase phase;
  final double volumeMeters;
  final double longRunMeters;
  final bool isDeload;
}

/// The full skeleton — the sequence of weeks.
class PlanSkeleton {
  const PlanSkeleton({required this.weeks});

  final List<SkeletonWeek> weeks;
}

/// One session in a generated week. [weekday] is `DateTime.monday`..`sunday`.
class PlannedSession {
  const PlannedSession({
    required this.weekday,
    required this.kind,
    this.distanceMeters = 0,
    this.label,
  });

  final int weekday;
  final SessionKind kind;
  final double distanceMeters;

  /// What the runner calls this one, when they call it something.
  ///
  /// "parkrun" beats "Time trial 5.0 km" on their own week, for the same reason
  /// ADR-0010 keeps a strength session unprescribed: the plan's job is to say
  /// when, in the runner's language, not to rename what they already do.
  final String? label;
}

/// A **generated week** — seven sessions tied to their [skeletonIndex] slot,
/// generated one week ahead (docs/architecture/plan-generation.md).
class TrainingWeek {
  const TrainingWeek({
    required this.skeletonIndex,
    required this.sessions,
    this.provisional = false,
  });

  final int skeletonIndex;
  final List<PlannedSession> sessions;

  /// True when this week was filled deterministically from the skeleton (the
  /// fallback after two failed generations) rather than generated — surfaced to
  /// the runner and regenerated when possible (plan-generation.md).
  final bool provisional;

  Iterable<PlannedSession> get runs => sessions.where((s) => s.kind.isRun);

  /// Sessions that occupy a day without adding kilometres — strength work.
  Iterable<PlannedSession> get support =>
      sessions.where((s) => s.kind.isSupport);

  /// The run scheduled on [weekday] (`DateTime.monday`..`sunday`), or null for a
  /// rest day.
  PlannedSession? runOn(int weekday) {
    for (final s in runs) {
      if (s.weekday == weekday) return s;
    }
    return null;
  }

  /// Anything scheduled on [weekday] — a run, or strength on a day with no run.
  ///
  /// A run wins when a day carries both, since the run is what the day's
  /// distance and pace belong to.
  PlannedSession? sessionOn(int weekday) =>
      runOn(weekday) ?? support.where((s) => s.weekday == weekday).firstOrNull;

  double get volumeMeters =>
      runs.fold<double>(0, (sum, s) => sum + s.distanceMeters);

  double get longRunMeters => runs.isEmpty
      ? 0
      : runs.map((s) => s.distanceMeters).reduce((a, b) => a > b ? a : b);
}
