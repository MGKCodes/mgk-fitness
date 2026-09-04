import '../../recording/domain/run_summary.dart';
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

/// Reading **one** run in full, as the screens see it.
///
/// Here for the same reason as [RunWriter] — the query needs `AppDatabase` and
/// the screen must not name it — but it is a separate interface rather than two
/// more methods on the writer, because a reader is not a writer and a build can
/// legitimately have one without the other. The preview harness has neither.
///
/// It is also, for now, the only way the shell can ask the database about a
/// single run: `historySource` arrives as a bare tear-off of one query, so the
/// editor is the one injected object that still knows where the data lives.
/// `RunEditor` implements this by delegating to `DriftRunRepository`, which is
/// where the queries actually are — nothing about reading a run belongs to
/// editing one. If the shell ever gains a repository of its own, this seam
/// should move onto it and the delegation should go.
abstract interface class RunDetailSource {
  /// One run in full — its summary, its trace and its splits. Null when there
  /// is no such run.
  Future<RunSummary?> runDetail(String runId);

  /// The run that finished after [since], in full, or null when none did.
  ///
  /// How a finished run is found again: the shell notes the time it opened the
  /// recorder and asks for whatever ended afterwards. A runner who backed out
  /// without recording gets null, which is the case that matters — the
  /// alternative, "the newest run in the log", would hand them the *previous*
  /// run's summary as though they had just done it.
  Future<RunSummary?> runFinishedSince(DateTime since);
}

/// Pulling a device's data back down, as the shell sees it.
///
/// Here for the same reason as [RunWriter]: `SupabaseRestore` needs the
/// database, and the shell only ever needs to say "go".
abstract interface class DataRestore {
  Future<RestoreResult> restoreAll();
}

/// What a restore actually brought back.
///
/// **Lives here, and is returned rather than discarded.** `DataRestore` used to
/// answer `Future<void>`: `SupabaseRestore` counted every row it pulled, built
/// this, and handed it to a caller whose contract could not receive it. Every
/// step inside that class also swallows its own throws by design, so a total
/// failure and a clean no-op were indistinguishable at the seam and identical
/// on screen -- a runner signing in on a new phone saw an empty log either way.
class RestoreResult {
  RestoreResult();

  factory RestoreResult.skipped() => RestoreResult()..skipped = true;

  /// True when consent had not been given, so nothing was attempted.
  bool skipped = false;
  int runs = 0;
  int plans = 0;
  int turns = 0;

  bool get restoredAnything => runs > 0 || plans > 0 || turns > 0;
}
