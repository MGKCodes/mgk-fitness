/// Small, dependency-free id for a locally-created row.
///
/// Not a real UUID and does not need to be — it only has to be unique within
/// one account's rows, and the database enforces that. It is shared with the
/// Supabase row when the row eventually goes up, which is why it is generated
/// here rather than by the server: a set logged in a basement has to have an
/// identity before anything has seen it.
///
/// Lifted out of `DriftSessionRecorder`, where it was private, when the workout
/// library became a second writer of workout rows. Two copies of an id
/// generator is two chances for one of them to stop being unique.
String newRowId() {
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final salt = identityHashCode(Object()).toRadixString(36);
  return '$now-$salt';
}
