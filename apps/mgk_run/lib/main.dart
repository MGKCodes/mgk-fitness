import 'src/core/brand.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/core/config/app_config.dart';
import 'src/dev/dev_persona.dart';
import 'src/dev/dev_seed.dart';
import 'src/core/database/app_database.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'src/features/auth/presentation/auth_gate.dart';
import 'src/features/settings/data/supabase_unit_settings.dart';
import 'src/features/coaching/data/coach_memory_drift_store.dart';
import 'src/features/coaching/data/coach_memory_mirror.dart';
import 'src/features/coaching/data/coach_service.dart';
import 'src/features/coaching/data/drift_plan_store.dart';
import 'src/features/coaching/data/supabase_plan_backup.dart';
import 'src/features/coaching/data/consented_backups.dart';
import 'src/features/history/data/consented_run_backup.dart';
import 'src/features/settings/data/backup_consent_factory.dart';
import 'src/features/settings/data/backup_health_factory.dart';
import 'src/features/history/data/drift_run_repository.dart';
import 'src/features/history/data/reported_run_backup.dart';
import 'src/features/history/data/run_editor.dart';
import 'src/features/history/data/supabase_restore.dart';
import 'src/features/history/data/supabase_run_backup.dart';
import 'src/features/recording/data/geolocator_location_source.dart';
import 'src/features/recording/data/recording_run_recorder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final configured = AppConfig.current.isConfigured;
  if (configured) {
    await Supabase.initialize(
      url: AppConfig.current.supabaseUrl,
      publishableKey: AppConfig.current.supabasePublishableKey,
    );
  }

  runApp(
    RunioApp(
      isConfigured: configured,
      database: configured ? AppDatabase.open() : null,
    ),
  );
}

/// Root of the Runio app.
class RunioApp extends StatelessWidget {
  const RunioApp({super.key, required this.isConfigured, this.database});

  /// Whether Supabase config was supplied at build time. When false the app
  /// shows [ConfigMissingScreen] instead of trying to reach a backend.
  final bool isConfigured;

  /// The on-device database — the offline-first source of truth for recording.
  /// Null when the app is unconfigured.
  final AppDatabase? database;

  @override
  Widget build(BuildContext context) {
    final db = database;
    return MaterialApp(
      title: kProductName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: isConfigured && db != null
          ? _AppRoot(db: db)
          : const ConfigMissingScreen(),
    );
  }
}

/// The signed-in app, and the one place a debug [DevPersona] is swapped in.
///
/// In a release build this is a straight pass-through to [AuthGate] with the
/// real sources: [kDebugMode] is a compile-time false, so the listener, the
/// seeding and every branch below fold away and the seed code is tree-shaken
/// out of the bundle entirely.
class _AppRoot extends StatefulWidget {
  const _AppRoot({required this.db});

  final AppDatabase db;

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  DevPersona? _persona;

  /// Held rather than created in [build]: a future rebuilt on every frame would
  /// re-seed the stores continuously, and the plan the runner is looking at
  /// would be replaced underneath them.
  Future<DevSeed>? _seed;

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) return;
    // Read directly rather than through _onPersona: setState is not allowed
    // during initState, and there is nothing to rebuild yet anyway.
    _persona = devPersona.value;
    final persona = _persona;
    if (persona != null) _seed = buildDevSeed(persona);
    devPersona.addListener(_onPersona);
  }

  @override
  void dispose() {
    if (kDebugMode) devPersona.removeListener(_onPersona);
    super.dispose();
  }

  void _onPersona() {
    final next = devPersona.value;
    if (next == _persona) return;
    setState(() {
      _persona = next;
      _seed = next == null ? null : buildDevSeed(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final seeding = _seed;
    if (seeding == null) return _gate(null);
    return FutureBuilder<DevSeed>(
      future: seeding,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // A seed that failed to build falls back to the real app rather than to
        // a broken one — and the throw is the validator refusing a fixture,
        // which is a bug in the fixture, not something to hide behind.
        return _gate(snapshot.data);
      },
    );
  }

  /// The app wired to real sources, or to [seed]'s when a persona is on.
  Widget _gate(DevSeed? seed) {
    final db = widget.db;
    // One consent store, shared by every backup. Built here rather than inside
    // each wrapper so all three read the same answer — three stores could
    // disagree, and the disagreement would be silent.
    final consent = createBackupConsentStore();
    // Where a failed push is written down. Nothing else reads it here — it is
    // for Settings, which builds its own store from the same factory and reads
    // the same file. Threading it through the shell would mean four widgets
    // holding a dependency only the last of them uses.
    final backupHealth = createBackupHealthStore();
    // Gated at construction: nothing below ever holds an ungated backup, so
    // there is no call path that can skip the check.
    //
    // The reporter sits *inside* the gate, so it only ever sees pushes consent
    // allowed. A run that was not sent because the runner declined is not a
    // failure and must not be reported as one — the switch is working.
    final runBackup = seed == null
        ? ConsentedRunBackup(
            inner: ReportedRunBackup(
              inner: SupabaseRunBackup(db: db),
              health: backupHealth,
            ),
            consent: consent,
          )
        : null;
    // Pulls anything missing back down — a reinstall, or a new phone. Gated on
    // consent inside, and best-effort: it runs over a connection nobody
    // promised, and every write is repeatable so a partial pull continues next
    // launch rather than starting again.
    final restore = seed == null
        ? SupabaseRestore(db: db, consent: consent)
        : null;
    return AuthGate(
      // A key per persona, so switching rebuilds the shell rather than reusing
      // it: HomeShell builds its repositories once into `late final` fields, so
      // a swapped store would otherwise be ignored until the next launch.
      key: ValueKey<DevPersona?>(seed?.persona),
      recorderFactory: () => RecordingRunRecorder(
        source: GeolocatorLocationSource(),
        db: db,
        // Same persona rule as the plan below: invented runs never reach the
        // shared project.
        backup: runBackup,
      ),
      // **The log is read from the phone** (ADR-0023). This was Supabase, which
      // meant a recorded run appeared only if it had been mirrored — so
      // declining backup, or losing a push, made a runner's own runs invisible
      // to them on the device that held them. Drift is the source of truth for
      // a run (rule 1) and is now also what the log is read from.
      historySource: seed?.history ?? DriftRunRepository(db).fetchRuns,
      // Adding and correcting runs. Local write first, then the mirror, and the
      // mirror is now only a mirror: the log shows the run either way.
      // `runBackup` is already the consent-gated wrapper (or null for a
      // persona), so this cannot reach Supabase without permission.
      runEditor: RunEditor(db: db, backup: runBackup),
      restore: restore,
      consentStore: consent,
      coach: CoachService(),
      planClient: CoachService(),
      // The plan is owned by the on-device database; Supabase only
      // mirrors it (CLAUDE.md rule 1).
      planStore: seed?.planStore ?? DriftPlanStore(db),
      // **A persona never reaches Supabase.** No backup and no mirror while one
      // is on: invented runs pushed to the shared project would be
      // indistinguishable from the runner's own, and there would be nothing to
      // tell them apart by afterwards.
      planBackup: seed == null
          ? ConsentedPlanBackup(inner: SupabasePlanBackup(), consent: consent)
          : null,
      // Same ownership as the plan: the coach's memory is the device's,
      // and Supabase only mirrors it. A transcript is the runner's own
      // words about their body (CLAUDE.md rule 6), so it stays local
      // and the mirror is best-effort.
      memoryStore: seed?.memoryStore ?? DriftCoachMemoryStore(db),
      // The transcripts are the most sensitive thing Runio holds — the
      // runner's own sentences about their body — so this is the gate that
      // matters most, and it was the last of the three to get one.
      memoryMirror: seed == null
          ? ConsentedMemoryMirror(
              inner: SupabaseCoachMemoryMirror(),
              consent: consent,
            )
          : null,
      // The display unit lives in the shared user_settings row, so it
      // follows the runner across to Liftio.
      unitSettings: SupabaseUnitSettings(),
    );
  }
}

/// Shown when the app was built without Supabase configuration.
class ConfigMissingScreen extends StatelessWidget {
  const ConfigMissingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.settings_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                'Configuration missing',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Build with '
                '--dart-define-from-file=config/app_config.json.\n'
                'See config/app_config.example.json.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
