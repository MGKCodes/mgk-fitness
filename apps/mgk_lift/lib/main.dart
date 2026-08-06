import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import 'src/core/database/app_database.dart';
import 'src/features/home/presentation/lift_shell.dart';
import 'src/features/settings/domain/unit_preferences.dart';
import 'src/features/stats/data/drift_session_history.dart';
import 'src/features/tracking/data/drift_session_recorder.dart';

/// Lift — the Flutter rewrite of Liftio.
///
/// Three surfaces, three time horizons, with the coach floating over all of
/// them: the same shape as `mgk_run`, because the two apps are one product.
///
/// What is wired: the shell, the navigation, and the design system. What is not,
/// yet: the on-device database, Supabase, and the coach. Those are injected in
/// this file when they arrive, so the widgets below stay testable without any of
/// them — the pattern `mgk_run`'s `HomeShell` uses.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MgkLiftApp(database: AppDatabase.open()));
}

class MgkLiftApp extends StatelessWidget {
  const MgkLiftApp({super.key, this.database});

  /// The on-device database. Injected rather than reached for, so a test can
  /// pass an in-memory one — or none, in which case tracking is simply
  /// unavailable and the app still runs.
  final AppDatabase? database;

  @override
  Widget build(BuildContext context) {
    final db = database;
    return MaterialApp(
      title: 'Lift',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: LiftShell(
        recorder: db == null ? null : DriftSessionRecorder(db),
        history: db == null ? null : DriftSessionHistory(db),
        // Supabase is not wired up yet, so units are kept for the session at
        // their defaults. Swapping in SupabaseUnitPreferences is the only
        // change needed once auth lands.
        units: InMemoryUnitPreferences(),
        // No coach passed in: the mark stays absent rather than inert. A mark
        // that cannot open anything is worse than no mark.
      ),
    );
  }
}
