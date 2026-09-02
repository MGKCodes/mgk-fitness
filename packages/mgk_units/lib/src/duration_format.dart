/// Display helpers for [Duration].
extension DurationFormat on Duration {
  /// Formats as `H:MM:SS` when there is at least one hour, otherwise `M:SS`.
  ///
  /// Negative durations are formatted from their absolute value.
  String get hoursMinutesSeconds {
    final totalSeconds = inSeconds.abs();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      final mm = minutes.toString().padLeft(2, '0');
      return '$hours:$mm:$ss';
    }
    return '$minutes:$ss';
  }

  /// A **total**, not a time: `305 h` once there is an hour, `47:20` below one.
  ///
  /// [hoursMinutesSeconds] is right for a thing that was run — a 10K in
  /// `50:55` — where every second is a fact somebody earned. It is wrong for
  /// a career: `305:32:23` is nine glyphs of tabular figures that nobody reads
  /// past the first three, and the 23 seconds are noise accumulated over two
  /// hundred runs rather than a measurement of anything.
  ///
  /// It also does not fit. On Profile the lifetime row is three columns in
  /// equal `Expanded`s, and a `Text` in a bounded box clips **silently** — no
  /// overflow stripe — so `305:32:23` drew straight through the streak beside
  /// it and rendered `305:32:2353 wk`. Shrinking the glyphs to fit was the
  /// first answer and it was the wrong one: it made an unreadable figure
  /// smaller. Rounding says the true thing at a length the column has.
  ///
  /// Truncated rather than rounded to nearest, because a total is a floor:
  /// somebody with 305 hours and 59 minutes has not run 306 hours.
  String get totalHours {
    final totalSeconds = inSeconds.abs();
    final hours = totalSeconds ~/ 3600;
    if (hours > 0) return '$hours h';
    final minutes = totalSeconds ~/ 60;
    final ss = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$ss';
  }
}
