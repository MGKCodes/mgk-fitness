/// What Health knows about a stretch of time the runner spent running.
///
/// Distinct from `HealthWorkout`, and the difference is which way round the
/// question goes. A workout is a *run somebody else recorded* that this app is
/// importing. This is the app's own run, already recorded here, asking the
/// phone what else it noticed while the run was happening — the pedometer being
/// the obvious thing, since a GPS trace cannot count steps.
///
/// **Every field is nullable and expected to be null.** iOS refuses to tell an
/// app which read permissions were granted, so a runner who declined and a
/// runner whose phone recorded nothing produce the same answer, and the only
/// honest thing to do with that answer is show nothing (CLAUDE.md rule 6).
/// Nothing here may be defaulted to zero on the way past: a zero is a claim
/// that the runner took no steps, which is a claim about their body that the
/// app has no basis for.
class RunHealthMetrics {
  const RunHealthMetrics({this.steps});

  /// Nothing known — a declined read, a platform with no Health, a phone that
  /// counted nothing, or a failure. All four are one value on purpose, because
  /// the app cannot tell them apart and pretending otherwise invents an error
  /// state out of a permission the runner is entitled to withhold.
  static const RunHealthMetrics none = RunHealthMetrics();

  /// Steps taken over the run's window, when Health has them.
  final int? steps;

  /// True when there is nothing to write down. Callers use it to skip the write
  /// entirely rather than storing a row of nulls over data that might already
  /// be there.
  bool get isEmpty => steps == null;
}

/// Where a finished run's Health figures come from.
///
/// A port for the same reason `WorkoutSource` is one: the parts worth testing
/// are the write path and the absence rules, and neither can be exercised
/// against HealthKit from a desktop. Tests supply their own answers.
abstract class RunHealthSource {
  /// What Health recorded between [start] and [end].
  ///
  /// **Never throws, and callers may rely on that.** This is asked on the
  /// critical path of the Finish button, behind a run that has already
  /// committed to the device (CLAUDE.md rule 1) — so a Health store that is
  /// slow, absent, locked or refusing must end as [RunHealthMetrics.none] and
  /// not as an exception that finishing a run has to catch.
  Future<RunHealthMetrics> forInterval({
    required DateTime start,
    required DateTime end,
  });
}
