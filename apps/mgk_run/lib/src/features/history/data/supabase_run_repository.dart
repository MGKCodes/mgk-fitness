import 'package:supabase_flutter/supabase_flutter.dart';

import '../../recording/domain/run_point.dart';
import '../../recording/domain/run_split.dart';
import '../../recording/domain/run_summary.dart';
import '../../../core/supabase/paged_select.dart';
import 'run_mappers.dart';

/// Reads runs from the shared Supabase platform (the `runSchema` schema). RLS scopes
/// every table to `auth.uid()`, so these queries only ever return the signed-in
/// user's own runs — no explicit user filter needed.
///
/// The list query is intentionally light (summary rows only, no trace); the
/// full route + splits are loaded on demand by [fetchRunDetail].
class SupabaseRunRepository {
  SupabaseRunRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// All of the user's runs, newest first (summary fields only).
  Future<List<RunSummary>> fetchRuns() async {
    final rows = await fetchAllPages(
      (f, t) => _client
          .schema('runSchema')
          .from('runs')
          .select()
          .order('started_at', ascending: false)
          .range(f, t),
    );
    return <RunSummary>[for (final row in rows) runSummaryFromRow(row)];
  }

  /// One run with its full trace and splits, for the summary screen.
  Future<RunSummary> fetchRunDetail(String id) async {
    final runSchema = _client.schema('run');
    final runFuture = runSchema.from('runs').select().eq('id', id).single();
    // Paged: a long run holds more than a thousand trace points, and an
    // unbounded select would quietly return the first thousand — a route that
    // simply stops partway, drawn as though it were the whole run.
    final pointsFuture = fetchAllPages(
      (f, t) => runSchema
          .from('run_points')
          .select()
          .eq('run_id', id)
          .order('seq')
          .range(f, t),
    );
    final splitsFuture = fetchAllPages(
      (f, t) => runSchema
          .from('run_splits')
          .select()
          .eq('run_id', id)
          .order('seq')
          .range(f, t),
    );

    final run = await runFuture;
    final pointRows = await pointsFuture;
    final splitRows = await splitsFuture;

    return runSummaryFromRow(
      Map<String, dynamic>.from(run),
      points: <RunPoint>[for (final r in pointRows) runPointFromRow(r)],
      splits: <RunSplit>[for (final r in splitRows) runSplitFromRow(r)],
    );
  }
}
