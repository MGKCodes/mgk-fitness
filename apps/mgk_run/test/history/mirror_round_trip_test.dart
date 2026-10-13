import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Every column the mirror writes must be a column the restore reads.**
///
/// The two halves of one seam live in different files and were kept in step by
/// somebody remembering. They fell out of step: `elevation_max_m` and `steps`
/// were written by the recorder on every run, dropped on the way up, and absent
/// on the way back down, so a runner who changed phone lost their high point
/// and their step count. Silently — absence is the designed state for both, so
/// there was nothing to see and nothing to report.
///
/// The interface-level tests could not catch it. They fake [RunBackup] and
/// assert what a caller does with the result, which is the right shape for
/// consent and failure handling and says nothing about a column list. So this
/// reads the two files as text, the way `naming_test.dart` reads `lib/` for
/// retired product names, and for the same reason: the invariant is real, it is
/// about source rather than behaviour, and nothing else was going to notice.
void main() {
  /// `'column': value,` inside the upsert map.
  Set<String> pushed() {
    final source = File(
      'lib/src/features/history/data/supabase_run_backup.dart',
    ).readAsStringSync();
    final upsert = source.substring(
      source.indexOf("from('runs').upsert"),
      source.indexOf('});', source.indexOf("from('runs').upsert")),
    );
    return RegExp(
      r"'([a-z_]+)':",
    ).allMatches(upsert).map((m) => m.group(1)!).toSet();
  }

  /// `r['column']` anywhere in the restore's mapping.
  Set<String> restored() {
    final source = File(
      'lib/src/features/history/data/supabase_restore.dart',
    ).readAsStringSync();
    return RegExp(
      r"r\['([a-z_]+)'\]",
    ).allMatches(source).map((m) => m.group(1)!).toSet();
  }

  test('a run survives the round trip with every column it went up with', () {
    // `user_id` is the one legitimate asymmetry: the mirror writes it because
    // row-level security keys on it, and the restore never reads it because it
    // is already restoring for exactly one runner.
    final up = pushed()..remove('user_id');
    final down = restored();

    expect(
      up.difference(down),
      isEmpty,
      reason:
          'these are mirrored up and never read back, so a restore onto a new '
          'phone drops them — which is what happened to elevation_max_m and '
          'steps for a month. Add them to SupabaseRestore._runCompanion.',
    );
  });

  test('the columns that were lost, and the race, are on both sides', () {
    // Named rather than left to the set comparison above, so that a change
    // which deletes both at once cannot pass by making the two sides agree.
    // The race columns are here because an official time is the one figure on
    // a run nothing can rebuild (ADR-0049).
    for (final column in <String>[
      'elevation_max_m',
      'steps',
      'race_distance_m',
      'race_time_s',
      'race_name',
    ]) {
      expect(pushed(), contains(column), reason: '$column must be mirrored');
      expect(restored(), contains(column), reason: '$column must be restored');
    }
  });

  test('the mirror does not write a column the schema lacks', () {
    // The other direction, and the one that fails loudly rather than silently:
    // PostgREST rejects the whole upsert for an unknown column, so a typo here
    // stops every backup rather than losing one field. Pinned against the
    // migrations that define `run.runs`.
    final baseline = File(
      '../../supabase/migrations/20260806120000_baseline.sql',
    ).readAsStringSync();
    // Scoped to the runs table: the baseline defines every table in the
    // project, and matching all of them would let a typo pass because some
    // other table happened to have that column.
    final createRuns = baseline.substring(
      baseline.indexOf('.runs ('),
      baseline.indexOf(');', baseline.indexOf('.runs (')),
    );
    // Found by name, not by version: the ledger stamps a version when a
    // migration is applied, and this one was re-stamped on 2026-09-29 (from
    // 20260901130000) after `db push` had skipped it. A hard-coded version
    // broke the Android build that day.
    String migration(String name) => Directory('../../supabase/migrations')
        .listSync()
        .whereType<File>()
        .singleWhere((f) => f.path.endsWith(name))
        .readAsStringSync();
    // Every migration that adds a column to `run.runs`. The race columns
    // (ADR-0049) are the second set; a third goes here, by name, in the same
    // change that adds it to the mirror.
    final added = <String>[
      migration('_run_elevation_max_and_steps.sql'),
      migration('_run_race_on_the_run.sql'),
    ].join('\n');

    final schema = <String>{
      ...RegExp(
        r'^\s+([a-z_]+)\s+(?:text|uuid|integer|real|timestamp|boolean)',
        multiLine: true,
      ).allMatches(createRuns).map((m) => m.group(1)!),
      ...RegExp(
        r'add column if not exists\s+([a-z_]+)',
      ).allMatches(added).map((m) => m.group(1)!),
    };
    expect(schema, isNotEmpty, reason: 'the schema scrape found no columns');
    for (final column in pushed()) {
      expect(
        schema,
        contains(column),
        reason: 'the mirror writes `$column`, which run.runs does not have',
      );
    }
  });
}
