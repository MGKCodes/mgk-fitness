/// Whether a planned session has been done, skipped, or is still ahead. The
/// runner marks this from the Today view; it feeds back into weekly session
/// generation (completions, misses, RPE trend — plan-generation.md).
enum SessionStatus {
  planned,
  completed,
  skipped;

  bool get isDone => this == completed;
  bool get isSkipped => this == skipped;
}
