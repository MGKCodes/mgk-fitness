import 'run_draft.dart';

/// Writing runs, as the screens see it.
///
/// A pure interface with a very specific job: **keeping `dart:io` out of the
/// web import graph.** `RunEditor` needs `AppDatabase`, which imports
/// `drift/native` and `dart:io`, so a screen that named `RunEditor` in its
/// signature dragged sqlite3's FFI bindings into any web build that touched it.
/// That silently broke the preview harness — the tool used to review this app's
/// UI — and it broke at the moment the shell gained a run editor, not at the
/// moment anyone looked.
///
/// So the shell depends on this and the real editor implements it, the same
/// shape as `UnitCache` and its factory. The dependency points at the domain,
/// which is where it should have pointed anyway.
abstract interface class RunWriter {
  /// Writes a new hand-entered run, returning its id. Throws if the draft does
  /// not pass its own checks.
  Future<String> add(RunDraft draft);

  /// Corrects an existing run. The trace is never touched.
  Future<void> edit(String runId, RunDraft draft);

  /// The stored run as a draft, or null if there is no such run.
  Future<RunDraft?> draftOf(String runId);

  /// Sends every local run the backup does not already hold.
  Future<int> backfill();
}

/// Pulling a device's data back down, as the shell sees it.
///
/// Here for the same reason as [RunWriter]: `SupabaseRestore` needs the
/// database, and the shell only ever needs to say "go".
abstract interface class DataRestore {
  Future<void> restoreAll();
}
