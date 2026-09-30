import 'src/core/brand.dart';
import 'package:flutter/material.dart';
import 'package:mgk_auth/file_local_data_owner.dart';
import 'package:mgk_auth/mgk_auth.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/core/config/app_config.dart';
import 'src/core/database/app_database.dart';
import 'src/features/auth/data/phone_training_data.dart';
import 'src/features/auth/data/supabase_auth.dart';
import 'src/features/coaching/data/supabase_coach.dart';
import 'src/features/coaching/data/supabase_coach_memory.dart';
import 'src/features/planning/data/cached_standing_plan_store.dart';
import 'src/features/planning/data/file_plan_cache.dart';
import 'src/features/planning/data/local_moved_day.dart';
import 'src/features/planning/data/supabase_coach_planner.dart';
import 'src/features/planning/data/supabase_standing_plan_store.dart';
import 'src/features/legal/data/account_deletion_service.dart';
import 'src/features/home/presentation/lift_shell.dart';
import 'src/features/photos/data/camera_photo_source.dart';
import 'src/features/photos/data/drift_photo_library.dart';
import 'src/features/photos/data/supabase_photo_sync.dart';
import 'src/features/purchases/data/revenuecat_purchases.dart';
import 'src/features/purchases/domain/purchases.dart';
import 'src/features/settings/data/local_coach_preference.dart';
import 'src/features/settings/data/local_unit_preferences.dart';
import 'src/features/entitlement/data/local_entitlement_cache.dart';
import 'src/features/entitlement/data/supabase_entitlements.dart';
import 'src/features/entitlement/domain/entitlement.dart';
import 'src/features/settings/data/supabase_unit_preferences.dart';
import 'src/features/settings/data/unit_preferences_repository.dart';
import 'src/features/stats/data/drift_session_history.dart';
import 'src/features/sync/data/supabase_backup_remote.dart';
import 'src/features/sync/data/workout_backup.dart';
import 'src/features/tracking/data/drift_session_recorder.dart';
import 'src/features/tracking/data/drift_workout_library.dart';
import 'src/features/tracking/data/local_rest_alerts.dart';
import 'src/features/tracking/data/local_rest_lengths.dart';

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

  final database = AppDatabase.open();
  runApp(
    MgkLiftApp(
      database: database,
      client: client,
      // Whose training is on this phone. Only with a server: without one
      // nobody signs in, so there is nobody to ask.
      localData: client == null
          ? null
          : LocalDataGuard(
              owner: FileLocalDataOwner(),
              data: PhoneTrainingData(database, plan: FilePlanCache()),
            ),
      // Needs both halves, like every paid path: a purchase with no server to
      // write the entitlement is a charge with nothing to show for it. And a
      // build with no store key sells nothing rather than failing — the
      // paywall says subscriptions are not open.
      purchases: (client == null || !config.canSell)
          ? null
          : RevenueCatPurchases(apiKey: config.storeKey),
    ),
  );
}

class MgkLiftApp extends StatelessWidget {
  const MgkLiftApp({
    super.key,
    this.database,
    this.client,
    this.purchases,
    this.localData,
  });

  /// Whose training is on this phone. Built once in `main`, like [purchases],
  /// because it remembers the answer it gave for each account.
  final LocalDataGuard? localData;

  /// The store. Built once in `main` rather than here, because it holds what
  /// it has been told — who is signed in, what it last offered — and a
  /// rebuild must not forget either.
  final Purchases? purchases;

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
      title: kProductName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: LiftShell(
        recorder: db == null ? null : DriftSessionRecorder(db),
        // Fixing a past session reuses the session screen, with a recorder
        // aimed at that session instead of the open one.
        editorFor: db == null
            ? null
            : (id) => DriftSessionRecorder.editing(db, id),
        library: db == null ? null : DriftWorkoutLibrary(db),
        history: db == null ? null : DriftSessionHistory(db),
        // Device first, account when it can answer. The account half is what
        // makes units agree with Run; the device half is what makes them
        // survive a launch at all, because tracking needs no sign-in and a
        // free lifter would otherwise get the default every time.
        units: UnitPreferencesRepository(
          local: LocalUnitPreferences(),
          remote: supabase == null
              ? null
              : SupabaseUnitPreferences(client: supabase),
        ),
        // Photos live on the same on-device database, so they come and go with
        // it: no database means no camera entry point, rather than a screen
        // that cannot save what it takes.
        photos: db == null ? null : DriftPhotoLibrary(db),
        photoSource: db == null ? null : CameraPhotoSource(),
        // Needs both halves: the rows live in the local database and
        // the JPEGs go to a bucket, so one without the other is a sync
        // that can only ever do half a job.
        photoBackup: (db == null || supabase == null)
            ? null
            : SupabasePhotoSync(db, supabase),
        auth: supabase == null ? null : SupabaseAuth(supabase),
        localData: localData,
        // **The wire that was missing until 2026-09-02.** `isEntitled` defaulted
        // to false and nothing ever passed it, so the paid half was invisible to
        // everybody — including the account that actually holds one. The server
        // knew and the screen did not.
        //
        // The cache is what stops a bad connection reading as "has not paid".
        // It grants nothing: the coach function re-reads `core.entitlements`
        // under `service_role` before spending, so the worst a stale `true` buys
        // is a nicer-looking app and a refusal.
        entitlements: supabase == null
            ? null
            : EntitlementGate(
                source: SupabaseEntitlements(client: supabase),
                cache: LocalEntitlementCache(),
              ),
        purchases: purchases,
        sync: (db == null || supabase == null)
            ? null
            : WorkoutBackup(db, SupabaseBackupRemote(supabase)),
        // The mark stays absent rather than inert when there is no server.
        coach: supabase == null ? null : SupabaseCoach(supabase),
        // Reading back what was already said. Paired with `coach` rather than
        // gated separately: there is no build that can hold a conversation but
        // must not be shown it.
        transcript: supabase == null ? null : SupabaseCoachTranscript(supabase),
        // Not gated on the entitlement the way the coach is: somebody who has
        // stopped paying must still be able to read what was stored about them
        // and delete it.
        coachMemory: supabase == null ? null : SupabaseCoachMemory(supabase),
        // Device-local and unconditional: the switch is consent, so it
        // works with no account and no server — and a build with no
        // Supabase has no coach to switch off, which the shell reads from
        // `coach` being null rather than from this.
        coachPreference: LocalCoachPreference(),
        // Device-local, like the coach switch above: a buzz and a habit, with
        // no account or server involved in either.
        restAlerts: LocalRestAlerts(),
        restLengths: LocalRestLengths(),
        // Paired with `auth` rather than gated separately: deletion is
        // meaningless without an account and impossible without a server,
        // and both of those are the same `supabase` being non-null.
        deleter: supabase == null
            ? null
            : AccountDeletionService(client: supabase),
        planner: supabase == null ? null : SupabaseCoachPlanner(supabase),
        // With a copy on the phone, so today's planned session is on Track
        // with no signal at the gym.
        plans: supabase == null
            ? null
            : CachedStandingPlanStore(
                remote: SupabaseStandingPlanStore(supabase),
                cache: FilePlanCache(),
              ),
        // Device-local: bringing a day forward is a choice on this phone for
        // one day, not a plan edit.
        movedDays: LocalMovedDay(),
      ),
    );
  }
}
