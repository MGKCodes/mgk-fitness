import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/core/config/app_config.dart';
import 'src/core/database/app_database.dart';
import 'src/features/auth/data/supabase_auth.dart';
import 'src/features/home/presentation/lift_shell.dart';
import 'src/features/photos/data/camera_photo_source.dart';
import 'src/features/photos/data/drift_photo_library.dart';
import 'src/features/settings/domain/unit_preferences.dart';
import 'src/features/stats/data/drift_session_history.dart';
import 'src/features/sync/data/supabase_sync.dart';
import 'src/features/tracking/data/drift_session_recorder.dart';

/// Lift — the Flutter rewrite of Liftio.
///
/// Three surfaces, three time horizons, with the coach floating over all of
/// them: the same shape as `mgk_run`, because the two apps are one product.
///
/// **Everything is injected here and nowhere else.** The widgets below take
/// interfaces, so a test or the preview harness passes fakes and never needs a
/// database, a network or an account.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A build with no config is a complete offline tracker rather than a broken
  // app: `AppConfig` reads compile-time defines, and the file that supplies
  // them is gitignored because this repository is public. Missing means
  // "no server", which every surface already handles.
  final config = AppConfig.fromEnvironment();
  SupabaseClient? client;
  if (config.isConfigured) {
    try {
      final supabase = await Supabase.initialize(
        url: config.supabaseUrl,
        publishableKey: config.supabasePublishableKey,
      );
      client = supabase.client;
    } on Object {
      // Reachability is not a launch requirement. Failing here would take the
      // app down over a network the lifter may not have, standing in a gym.
      client = null;
    }
  }

  runApp(MgkLiftApp(database: AppDatabase.open(), client: client));
}

class MgkLiftApp extends StatelessWidget {
  const MgkLiftApp({super.key, this.database, this.client});

  /// The on-device database. Injected rather than reached for, so a test can
  /// pass an in-memory one — or none, in which case tracking is simply
  /// unavailable and the app still runs.
  final AppDatabase? database;

  /// Supabase. Null when unconfigured or unreachable at launch, which every
  /// surface treats as "this device only" rather than as an error.
  final SupabaseClient? client;

  @override
  Widget build(BuildContext context) {
    final db = database;
    final supabase = client;

    return MaterialApp(
      title: 'Lift',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: LiftShell(
        recorder: db == null ? null : DriftSessionRecorder(db),
        history: db == null ? null : DriftSessionHistory(db),
        // Units still live for the session only. `core.user_settings` is shared
        // with Run and is the right home; wiring it is a small job that wants
        // the account to exist first, which it now does.
        units: InMemoryUnitPreferences(),
        // Photos live on the same on-device database, so they come and go with
        // it: no database means no camera entry point, rather than a screen
        // that cannot save what it takes.
        photos: db == null ? null : DriftPhotoLibrary(db),
        photoSource: db == null ? null : CameraPhotoSource(),
        auth: supabase == null ? null : SupabaseAuth(supabase),
        sync: (db == null || supabase == null)
            ? null
            : SupabaseSync(db, supabase),
        // No coach client passed in: the mark stays absent rather than inert.
      ),
    );
  }
}
