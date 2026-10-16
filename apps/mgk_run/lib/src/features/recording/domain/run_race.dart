/// A run that was a race: the distance it was run over, and what the official
/// clock said.
///
/// **A race is something a run is, not only the end of a plan.** Until this
/// existed the app could only know about a race by having built a plan aimed
/// at its date (ADR-0027), so a runner who used Run to record their training
/// and then ran a half marathon got an ordinary summary of an ordinary 21.69
/// km: no chip time, no "first half marathon", nothing to say the day had been
/// different. ADR-0049 moves the race onto the run, where it can be marked
/// whether or not a plan was ever involved.
///
/// Stored on the run row rather than derived, for ADR-0027's reason: the
/// official time is something the runner told us, and nothing on the phone can
/// rebuild it.
class RunRace {
  const RunRace({required this.distanceMeters, this.officialTime, this.name});

  /// The race distance, in metres: 21,097.5 for a half, never the trace's
  /// 21,686. A half marathon whose phone read long is still a half marathon,
  /// and every figure the race screen derives — the pace, the sections, the
  /// halves — is measured against the course rather than against the weaving.
  final double distanceMeters;

  /// The time on the certificate, when the runner gave one.
  ///
  /// Null means the phone's time is the only time there is, which is the
  /// ordinary state until they look their result up. It is never set to the
  /// phone's own figure: a stored official time that merely repeats the phone
  /// would read as two sources agreeing when there was only ever one.
  final Duration? officialTime;

  /// What the runner calls it — "Royal Parks Half". Optional, and shown where
  /// the date would otherwise be.
  final String? name;

  /// The time to report: the official one where there is one, and [phone]
  /// otherwise.
  Duration timeFor(Duration phone) => officialTime ?? phone;

  RunRace copyWith({
    double? distanceMeters,
    Duration? Function()? officialTime,
    String? Function()? name,
  }) => RunRace(
    distanceMeters: distanceMeters ?? this.distanceMeters,
    officialTime: officialTime == null ? this.officialTime : officialTime(),
    name: name == null ? this.name : name(),
  );

  @override
  bool operator ==(Object other) =>
      other is RunRace &&
      other.distanceMeters == distanceMeters &&
      other.officialTime == officialTime &&
      other.name == name;

  @override
  int get hashCode => Object.hash(distanceMeters, officialTime, name);

  @override
  String toString() =>
      'RunRace(${distanceMeters}m, official: $officialTime, name: $name)';
}
