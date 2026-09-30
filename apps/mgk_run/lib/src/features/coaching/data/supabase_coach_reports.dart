import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/coach_report.dart';

/// Inserts a report into `coach.reports` as the signed-in runner.
///
/// **Insert, and nothing else.** The table lets a client insert its own rows
/// and read none, including the one it just wrote, so this never chains a
/// `.select()`: asking for the row back would be refused and turn a report
/// that arrived into one the runner is told failed.
///
/// `const`, resolving the client per call, so a widget can take one as a
/// default argument without Supabase being initialised -- the same shape as
/// `SupabaseEntitlements`.
class SupabaseCoachReports implements CoachReporter {
  const SupabaseCoachReports({
    SupabaseClient? client,
    this.timeout = const Duration(seconds: 10),
  }) : _explicitClient = client;

  final SupabaseClient? _explicitClient;

  /// A report that has not landed in this long is reported as not sent, so
  /// the runner is not left watching a spinner on a dead connection.
  final Duration timeout;

  SupabaseClient? get _client {
    if (_explicitClient != null) return _explicitClient;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> report(CoachReport report) async {
    final client = _client;
    if (client == null) throw StateError('Supabase is not initialised');
    await client
        .schema('coach')
        .from('reports')
        .insert(report.toRow())
        .timeout(timeout);
  }
}
