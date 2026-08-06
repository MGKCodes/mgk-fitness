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
}
