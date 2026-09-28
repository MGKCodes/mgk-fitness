import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../tracking/data/session_hydration.dart';
import '../../tracking/domain/session.dart';
import '../domain/session_history.dart';

/// Reads finished sessions from the on-device database.
///
/// Local, so the log opens instantly and works with no signal — the same posture
/// as recording. Supabase is a backup, not the thing a screen waits on.
class DriftSessionHistory implements SessionHistory {
  const DriftSessionHistory(this._db);

  final AppDatabase _db;

  @override
  Future<List<Session>> all({int? limit}) async {
    final query = _db.select(_db.workouts)
      // Finished, real, and not deleted. A template has no date and never
      // happened; an open session belongs to the recorder, not the log.
      ..where(
        (w) =>
            w.endedAt.isNotNull() &
            w.deletedAt.isNull() &
            w.isTemplate.equals(false),
      )
      ..orderBy([(w) => OrderingTerm.desc(w.startedAt)]);
    if (limit != null) query.limit(limit);

    // Every session in three reads, not one per movement per session — this
    // runs on every return to Track, and the old shape grew with the log.
    return hydrateWorkouts(_db, await query.get());
  }
}
