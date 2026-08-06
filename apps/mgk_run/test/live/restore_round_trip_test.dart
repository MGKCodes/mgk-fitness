@Tags(<String>['live'])
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/config/app_config.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/coach_memory_mirror.dart';
import 'package:mgk_run/src/features/coaching/data/coach_memory_repository.dart';
import 'package:mgk_run/src/features/coaching/data/coach_memory_drift_store.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/data/supabase_plan_backup.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_memory.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/history/data/supabase_restore.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// **The round trip, against the real backend.** Does everything actually
/// survive a lost phone?
///
/// Runs on the Dart VM, which is the point: the same `NativeDatabase` that ships
/// on iOS, the real Supabase over the real network, and an empty in-memory
/// database standing in for a fresh install — because that is exactly what a
/// fresh install is. No emulator and no device needed.
///
/// What this cannot tell you is whether iOS really deletes app data on
/// uninstall. That is the operating system's behaviour, not Runio's, and no test
/// here or on a device would be testing our code.
///
/// Tagged `live` so the ordinary suite stays hermetic and free. Run it with:
///
/// ```
/// flutter test --tags live --dart-define-from-file=config/app_config.json
/// ```
///
/// It writes to the shared project under the dev account, using ids prefixed
/// `roundtrip-` so every row it creates is identifiable, and deletes them
/// afterwards whether or not the assertions passed.
void main() {
  final config = AppConfig.current;
  if (!config.isConfigured) {
    // **Skipped, not passed.** A live test that reports green when it was never
    // pointed at a backend is worse than no test, so the ordinary suite shows
    // this as skipped with the reason attached rather than quietly counting it.
    test(
      'the restore round trip',
      () {},
      skip:
          'needs a real backend: flutter test --tags live '
          '--dart-define-from-file=config/app_config.json',
    );
    return;
  }

  late SupabaseClient client;
  late String planId;

  /// A separate client per test run rather than `Supabase.initialize`: the
  /// singleton wants shared_preferences for session storage, which is a plugin,
  /// and every class under test takes an injectable client precisely so this is
  /// possible.
  setUpAll(() async {
    client = SupabaseClient(config.supabaseUrl, config.supabasePublishableKey);
    final account = config.devAccounts.first;
    await client.auth.signInWithPassword(
      email: account.email,
      password: account.password,
    );
    expect(
      client.auth.currentUser,
      isNotNull,
      reason: 'could not sign in as the dev account',
    );
  });

  tearDownAll(() async {
    // Everything this test made, gone again, in dependency order.
    final runio = client.schema('runio');
    await runio.from('plan_sessions').delete().eq('plan_id', planId);
    await runio.from('plan_weeks').delete().eq('plan_id', planId);
    await runio.from('plans').delete().eq('id', planId);
    await runio
        .from('coach_turns')
        .delete()
        .like('conversation_id', 'roundtrip-%');
    await runio.from('coach_conversations').delete().like('id', 'roundtrip-%');
    await client.dispose();
  });

  RunnerProfile aProfile() => RunnerProfile(
    goalDistanceMeters: 21097,
    eventDate: DateTime.now().add(const Duration(days: 90)),
    currentWeeklyMeters: 30000,
    longestRecentMeters: 14000,
    daysPerWeek: 4,
    availableWeekdays: const <int>{1, 3, 5, 7},
    strengthDaysPerWeek: 1,
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 23),
  );

  test('a plan and a conversation survive a new phone', () async {
    // ---- the old phone -----------------------------------------------------
    final oldPhone = AppDatabase(NativeDatabase.memory());
    addTearDown(oldPhone.close);

    planId = 'roundtrip-${DateTime.now().microsecondsSinceEpoch}';
    final conversationId = 'roundtrip-$planId';

    final plans = PlanRepository(
      store: DriftPlanStore(oldPhone),
      backup: SupabasePlanBackup(client: client),
      newId: () => planId,
    );
    final plan = await plans.create(aProfile());

    final memory = CoachMemoryRepository(
      store: DriftCoachMemoryStore(oldPhone),
      mirror: SupabaseCoachMemoryMirror(client: client),
    );
    await memory.appendTurn(
      conversationId: conversationId,
      role: CoachRole.user,
      text: 'How am I doing?',
    );
    await memory.appendTurn(
      conversationId: conversationId,
      role: CoachRole.assistant,
      text: 'Three weeks of turning up. That is the hard part.',
    );

    // ---- did any of it actually leave the device? ---------------------------
    // Asserted against the server rather than against the push returning
    // without error, because a push failure is swallowed by design (rule 1) and
    // that is precisely how this stayed broken for a year.
    final runio = client.schema('runio');
    final storedPlan = await runio
        .from('plans')
        .select('id, weeks, goal_distance_m, strength_days_per_week')
        .eq('id', planId)
        .maybeSingle();
    expect(
      storedPlan,
      isNotNull,
      reason: 'the plan never reached Supabase, so nothing could restore it',
    );
    expect(storedPlan!['weeks'], plan.skeleton.weeks.length);
    expect(storedPlan['goal_distance_m'], closeTo(21097, 1));

    final storedWeeks = await runio
        .from('plan_weeks')
        .select('week_number')
        .eq('plan_id', planId);
    expect(storedWeeks, hasLength(plan.skeleton.weeks.length));

    final storedSessions = await runio
        .from('plan_sessions')
        .select('weekday')
        .eq('plan_id', planId);
    expect(
      storedSessions,
      isNotEmpty,
      reason: 'create materialises this week and next',
    );

    final storedTurns = await runio
        .from('coach_turns')
        .select('role, body')
        .eq('conversation_id', conversationId);
    expect(storedTurns, hasLength(2));

    // ---- the new phone -----------------------------------------------------
    // A different database with nothing in it. This is a reinstall.
    final newPhone = AppDatabase(NativeDatabase.memory());
    addTearDown(newPhone.close);
    expect(await newPhone.select(newPhone.plans).get(), isEmpty);

    final restore = SupabaseRestore(
      db: newPhone,
      consent: InMemoryBackupConsent(BackupConsent.granted),
      client: client,
    );
    final result = await restore.restoreAll();

    expect(
      result.skipped,
      isFalse,
      reason: 'consent was granted, so nothing should have been skipped',
    );
    expect(result.restoredAnything, isTrue);

    // The plan came back, arc and all.
    final restoredPlan = await DriftPlanStore(newPhone).loadActivePlan();
    expect(restoredPlan, isNotNull, reason: 'the plan did not come back');
    expect(restoredPlan!.id, planId);
    expect(restoredPlan.skeleton.weeks, hasLength(plan.skeleton.weeks.length));
    // The profile snapshot travelled with it, including the fields the parity
    // migration added.
    expect(restoredPlan.profile.goalDistanceMeters, closeTo(21097, 1));
    expect(restoredPlan.profile.strengthDaysPerWeek, 1);
    expect(restoredPlan.profile.availableWeekdays, <int>{1, 3, 5, 7});

    // The sessions came back, not just the arc.
    final restoredWeek = await DriftPlanStore(
      newPhone,
    ).loadWeek(restoredPlan, restoredPlan.weekIndexOn(DateTime.now()));
    expect(restoredWeek, isNotNull, reason: 'this week has no sessions');
    expect(restoredWeek!.sessions, isNotEmpty);

    // And the conversation, which is the most sensitive thing Runio holds.
    final restoredTurns = await newPhone.select(newPhone.coachTurns).get();
    expect(restoredTurns, hasLength(greaterThanOrEqualTo(2)));
    expect(
      restoredTurns.map((t) => t.body),
      contains('Three weeks of turning up. That is the hard part.'),
    );

    // The runs already in the account came down too — the half that was known
    // to work, asserted here so a regression in it fails this test as well.
    expect(result.runs, greaterThan(0));
  });

  test('restoring twice adds nothing the second time', () async {
    // Insert-or-ignore is the whole contract. A restore that duplicated on a
    // second run would turn "safe to retry" into "corrupts on retry", and the
    // app calls this on every cold start.
    final phone = AppDatabase(NativeDatabase.memory());
    addTearDown(phone.close);

    final restore = SupabaseRestore(
      db: phone,
      consent: InMemoryBackupConsent(BackupConsent.granted),
      client: client,
    );

    await restore.restoreAll();
    final afterFirst = (await phone.select(phone.runs).get()).length;
    expect(afterFirst, greaterThan(0));

    await restore.restoreAll();
    final afterSecond = (await phone.select(phone.runs).get()).length;
    expect(afterSecond, afterFirst, reason: 'a second pull duplicated rows');
  });

  test('a runner who declined gets nothing pulled', () async {
    // Not a privacy risk in itself — it is their own data — but a runner who
    // said no should not have the app moving their health data around at all.
    final phone = AppDatabase(NativeDatabase.memory());
    addTearDown(phone.close);

    final result = await SupabaseRestore(
      db: phone,
      consent: InMemoryBackupConsent(BackupConsent.declined),
      client: client,
    ).restoreAll();

    expect(result.skipped, isTrue);
    expect(await phone.select(phone.runs).get(), isEmpty);
  });
}
