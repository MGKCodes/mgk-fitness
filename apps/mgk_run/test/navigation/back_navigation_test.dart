import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_flow.dart';
import 'package:mgk_run/src/features/legal/domain/disclaimer_store.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_detail_screen.dart';
import 'package:mgk_run/src/features/legal/domain/account_deleter.dart';
import 'package:mgk_run/src/features/legal/presentation/delete_account_screen.dart';
import 'package:mgk_run/src/features/legal/presentation/legal_screen.dart';
import 'package:mgk_run/src/features/legal/presentation/medical_disclaimer_screen.dart';
import 'package:mgk_run/src/features/legal/presentation/privacy_policy_screen.dart';
import 'package:mgk_run/src/features/profile/domain/runner_stats.dart';
import 'package:mgk_run/src/features/profile/presentation/profile_screen.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_run/src/features/recording/presentation/run_summary_screen.dart';
import 'package:mgk_run/src/features/settings/domain/unit_settings.dart';
import 'package:mgk_run/src/features/settings/presentation/settings_screen.dart';

/// The flow builds its own plan now, so a test has to give it something to
/// build (ADR-0019). These suites never reach the reveal; this exists to
/// satisfy the constructor.
Future<StoredPlan> _aPlan(RunnerProfile profile) async => StoredPlan(
  id: 'plan-1',
  profile: profile,
  skeleton: buildSkeleton(profile, now: DateTime(2026, 7, 25)),
  startDate: mondayOf(DateTime(2026, 7, 25)),
);

/// A deleter that never returns, so the screen stays in its resting state.
class _IdleDeleter implements AccountDeleter {
  @override
  Future<AccountDeletionResult> deleteAccount() async =>
      const AccountDeletionResult(accountDeleted: true);
}

void main() {
  final profile = RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 1),
    currentWeeklyMeters: 45000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );
  final slot = buildSkeleton(
    profile,
    now: DateTime(2026, 7, 25),
    weeks: 12,
  ).weeks[5];

  final summary = RunSummary(
    startedAt: DateTime(2026, 7, 21, 7, 32),
    duration: const Duration(minutes: 27, seconds: 45),
    distanceMeters: 5230,
    avgPaceSecondsPerKm: 318,
  );

  /// Every screen the app *pushes*. Each must be escapable — a pushed screen
  /// with no way back is a dead end, and the runner's only recourse is to kill
  /// the app.
  final pushed = <String, Widget Function()>{
    'Profile': () => ProfileScreen(
      stats: RunnerStats.from(<RunSummary>[summary]),
      profile: profile,
    ),
    'Settings': () => SettingsScreen(
      unit: UnitSystem.metric,
      settings: InMemoryUnitSettings(),
      auth: FakeAuthRepository(
        signedIn: true,
        email: 'dev@mgkfitness.mgkcodes.com',
      ),
    ),
    'Privacy & legal': () => LegalScreen(
      auth: FakeAuthRepository(
        signedIn: true,
        email: 'dev@mgkfitness.mgkcodes.com',
      ),
      deleter: _IdleDeleter(),
    ),
    'Privacy policy': () => const PrivacyPolicyScreen(),
    'Medical disclaimer (read-only)': () => const MedicalDisclaimerScreen(),
    'Delete account': () => DeleteAccountScreen(
      auth: FakeAuthRepository(
        signedIn: true,
        email: 'dev@mgkfitness.mgkcodes.com',
      ),
      deleter: _IdleDeleter(),
    ),
    'Run summary': () => RunSummaryScreen(summary: summary),
    'Week detail': () => WeekDetailScreen(
      week: buildFallbackWeek(slot, profile),
      slot: slot,
      paces: TrainingPaces.fromRace(
        Distance.meters(5000),
        const Duration(minutes: 22),
      ),
    ),
  };

  for (final entry in pushed.entries) {
    testWidgets('${entry.key} can be backed out of', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => entry.value()),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.text('open'),
        findsNothing,
        reason: '${entry.key} did not open',
      );

      // Flutter supplies a BackButton implicitly; a screen that suppresses it
      // must offer its own way out instead.
      final back = find.byType(BackButton);
      expect(
        back,
        findsOneWidget,
        reason: '${entry.key} has no back affordance — it is a dead end',
      );

      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(
        find.text('open'),
        findsOneWidget,
        reason: '${entry.key} back did not return to the previous screen',
      );
    });
  }

  // Screens that deliberately do *not* offer a plain back button, because
  // leaving them is a decision rather than a navigation. Each must still be
  // escapable — the rule is "no dead ends", not "back button everywhere".
  group('deliberate exits', () {
    testWidgets('a live run is left through cancel, not a back button', (
      tester,
    ) async {
      var cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RecordingScreen(
            recorder: FakeRunRecorder(),
            onCancel: () => cancelled = true,
          ),
        ),
      );
      await tester.pump();

      // No back button on purpose: swiping out of a run in progress would lose
      // it, and the on-device database owns that run (CLAUDE.md rule 1).
      expect(find.byType(BackButton), findsNothing);

      // The status pill pulses forever, so pumpAndSettle can never settle on
      // this screen — pump explicit frames instead.
      await tester.tap(find.byTooltip('Cancel run'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Leaving is confirmed, not immediate.
      expect(find.text('Discard this run?'), findsOneWidget);

      await tester.tap(find.text('Discard'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(cancelled, isTrue);
    });

    testWidgets('the disclaimer gate is left by declining', (tester) async {
      var declined = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MedicalDisclaimerScreen(
            onAcknowledge: () {},
            onDecline: () => declined = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A legal gate must not be dismissable by reflex.
      expect(find.byType(BackButton), findsNothing);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(declined, isTrue);
    });

    testWidgets('the coach flow closes back to the tab it came from', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CoachFlow(
                        buildPlan: _aPlan,
                        coach: FakeCoachService(),
                        disclaimer: InMemoryDisclaimerStore(acknowledged: true),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsNothing);

      // Past the shape question, which is the flow's first step now
      // (ADR-0019); the close button under test belongs to the conversation
      // behind it.
      await tester.tap(find.text('I have a race coming up'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('and backing out of the shape question leaves it too', (
      tester,
    ) async {
      // The shape question is a new first step and therefore a new way to be
      // stuck. Every other step of this flow has a way out that lands back on
      // the tab; this one has to as well, or the first screen of the plan flow
      // is a trap.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CoachFlow(
                        buildPlan: _aPlan,
                        coach: FakeCoachService(),
                        disclaimer: InMemoryDisclaimerStore(acknowledged: true),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('What are you after?'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });
  });
}
