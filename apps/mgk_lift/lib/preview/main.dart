import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../src/features/auth/data/fake_auth.dart';
import '../src/features/auth/domain/account.dart';
import '../src/features/auth/presentation/sign_in_screen.dart';
import '../src/features/coaching/data/supabase_coach.dart';
import '../src/features/coaching/data/supabase_coach_memory.dart';
import '../src/features/coaching/domain/coach.dart';
import '../src/features/coaching/domain/coach_memory.dart';
import '../src/features/coaching/presentation/coach_history_sheet.dart';
import '../src/features/coaching/presentation/coach_memory_screen.dart';
import '../src/features/coaching/presentation/coach_sheet.dart';
import '../src/features/planning/domain/coach_planner.dart';
import '../src/features/planning/domain/intake_flow.dart';
import '../src/features/planning/domain/plan_intake.dart';
import '../src/features/planning/domain/standing_plan_store.dart';
import '../src/features/planning/domain/plan_template.dart';
import '../src/features/planning/domain/standing_plan.dart';
import '../src/features/planning/domain/training_split.dart';
import '../src/features/planning/presentation/plan_intake_screen.dart';
import '../src/features/planning/presentation/swap_sheet.dart';
import '../src/features/home/presentation/lift_shell.dart';
import '../src/features/legal/data/account_deletion_service.dart';
import '../src/features/legal/domain/legal_copy.dart';
import '../src/features/legal/presentation/delete_account_screen.dart';
import '../src/features/legal/presentation/legal_document_screen.dart';
import '../src/features/legal/presentation/legal_screen.dart';
import '../src/features/tracking/domain/workout_library.dart';
import '../src/features/tracking/presentation/workout_library_screen.dart';
import '../src/features/tracking/presentation/workout_preview_sheet.dart';
import '../src/features/tracking/presentation/exercise_picker_sheet.dart';
import '../src/features/tracking/presentation/premade_library_sheet.dart';
import '../src/features/tracking/presentation/save_workout_prompt.dart';
import '../src/features/tracking/presentation/workout_editor_screen.dart';
import '../src/features/tracking/data/exercise_lookup.dart';
import '../src/features/photos/data/in_memory_photo_library.dart';
import '../src/features/photos/domain/progress_photo.dart';
import '../src/features/photos/presentation/photo_sheets.dart';
import '../src/features/photos/presentation/photos_surface.dart';
import '../src/features/photos/presentation/pose_series_screen.dart';
import '../src/features/photos/presentation/series_playback_screen.dart';
import '../src/features/settings/domain/unit_preferences.dart';
import '../src/features/settings/presentation/credits_screen.dart';
import '../src/features/settings/presentation/settings_screen.dart';
import '../src/features/sync/domain/sync_status.dart';
import '../src/features/sync/presentation/backup_scheduler.dart';
import '../src/features/entitlement/domain/entitlement.dart';
import '../src/features/purchases/domain/purchases.dart';
import '../src/features/purchases/presentation/purchase_sheet.dart';
import '../src/features/tracking/domain/rest_alerts.dart';
import '../src/features/tracking/domain/session.dart';
import '../src/features/tracking/presentation/reorder_sheet.dart';
import '../src/features/stats/presentation/history_screen.dart';
import '../src/features/tracking/presentation/active_session_screen.dart';
import '../src/features/tracking/presentation/session_summary_screen.dart';
import 'fakes.dart';

/// A harness for reviewing screens one at a time.
///
/// Same idea as `mgk_run`'s preview: every screen is addressable without
/// navigating to it, because a Flutter canvas cannot reliably be tapped
/// through by a screenshot tool. Screens are built over in-memory fakes, so no
/// database and no network — the thing under review is the layout.
///
/// **Prefer the emulator.** The web build renders blur, fonts, safe areas and
/// scroll physics differently, which is not a detail when the whole review is
/// "does this look right":
///
///     flutter run -d emulator-5554 -t lib/preview/main.dart \
///       --dart-define=screen=intake-1-days
///     adb exec-out screencap -p > shot.png
///
/// The URL form still works on web, and is what Playwright drives:
///
///     flutter run -d web-server --web-port 5310 -t lib/preview/main.dart
///
/// It was URL-only until 2026-08-07, which quietly made the harness web-only:
/// Android had no way to say which screen it wanted and always fell back to
/// the index.
void main() => runApp(const PreviewApp());

/// One fixed "now", so a screenshot taken today and one taken next week show
/// the same streak. A harness whose output changes with the wall clock is
/// useless for comparing before and after.
final DateTime previewNow = DateTime(2026, 8, 6, 18, 30);

/// A signed-in account for the compliance plates.
///
/// A function rather than a shared constant because [FakeAuth] owns a
/// `StreamController`: two plates holding one instance would share a closed
/// controller the moment the first of them is disposed, and the second would
/// render an account that had silently signed itself out.
FakeAuth _signedInAuth() => FakeAuth(
  account: const Account(id: 'fake-user', email: 'matt@example.com'),
);

class PreviewApp extends StatelessWidget {
  const PreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    final screens = <String, WidgetBuilder>{
      // **Every shell entry carries a coach**, because production does: main.dart
      // passes one whenever Supabase is configured, and the shell draws the mark
      // — and reserves the room above the nav bar for it — only when there is
      // one. A shell preview without a coach is a screenshot of a build nobody
      // ships, and it is missing two of the three permanent pieces of chrome.
      //
      // This was the standing fault in the harness until 2026-08-27: one entry
      // rendered the mark and forty-odd rendered a nav bar with dead space where
      // it should have been. Same class of blind spot as the back arrow in
      // docs/navigation.md, found the same way — by trying to photograph it.
      'track': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
        coach: FakeCoach(),
        library: InMemoryWorkoutLibrary(_savedWorkouts()),
        today: previewNow,
      ),
      // Backup, on Track: a pill only when something needs the lifter. The
      // shell's launch checkpoint runs the fake two seconds in, so the pill
      // arrives rather than being there from the first frame — as it would.
      'track-backup-failed': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
        coach: FakeCoach(),
        library: InMemoryWorkoutLibrary(_savedWorkouts()),
        // Signed in, as a failing backup implies: signed out, the run
        // would say so and there would be no pill.
        auth: _signedInAuth(),
        today: previewNow,
        sync: FakeBackup(
          report: const SyncReport.unavailable('503'),
          waiting: const SyncPending(
            workouts: 2,
            lastSyncedAt: null,
            waitingIds: <String>{'a', 'b'},
          ),
        ),
      ),
      'track-backup-refused': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
        coach: FakeCoach(),
        library: InMemoryWorkoutLibrary(_savedWorkouts()),
        // Signed in, as a failing backup implies: signed out, the run
        // would say so and there would be no pill.
        auth: _signedInAuth(),
        today: previewNow,
        sync: FakeBackup(
          report: const SyncReport(outcome: SyncOutcome.synced, rejected: 1),
          waiting: const SyncPending(
            workouts: 0,
            lastSyncedAt: null,
            rejected: <RejectedWorkout>[
              RejectedWorkout(
                id: 'w9',
                name: 'Legs, heavy',
                isTemplate: false,
                detail: '22003: numeric field overflow',
              ),
            ],
          ),
        ),
      ),
      'track-open': (_) => LiftShell(
        recorder: FakeSessionRecorder(_openSession()),
        history: FakeHistory(sampleLog(previewNow)),
        coach: FakeCoach(),
        library: InMemoryWorkoutLibrary(_savedWorkouts()),
        today: previewNow,
      ),
      // The mark with something waiting on it. The only difference from `track`
      // is the unread dot, which is the whole point of having both.
      'track-coach': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
        coach: FakeCoach(),
        library: InMemoryWorkoutLibrary(_savedWorkouts()),
        today: previewNow,
        hasCoachNote: true,
      ),
      // With a store behind it, as a build with RevenueCat keys has: priced
      // from the store, with Restore, and Start coaching opening the sheet.
      'plan': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
        coach: FakeCoach(),
        today: previewNow,
        initialTab: 1,
        purchases: FakePurchases(offers: _storeOffers),
        entitlements: EntitlementGate(
          source: FakeEntitlements(Entitlement.none),
        ),
      ),
      // Where money moves: both tiers, the store's prices, the renewal terms
      // in Apple's words, the two links and Restore.
      'purchase-sheet': (_) => _SheetHost(
        open: (context) => showGlassSheet<PurchaseResult>(
          context: context,
          builder: (_) => PurchaseSheet(
            flow: PurchaseFlow(
              purchases: FakePurchases(offers: _storeOffers),
              gate: EntitlementGate(source: FakeEntitlements(Entitlement.none)),
            ),
            offers: _storeOffers,
            platform: TargetPlatform.iOS,
          ),
        ),
      ),
      'plan-entitled': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
        coach: FakeCoach(),
        today: previewNow,
        isEntitled: true,
        initialTab: 1,
      ),
      // Item 5: what Track shows when a plan has something for today, and
      // when somebody walked away mid-session.
      'track-planned': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
        coach: FakeCoach(),
        library: InMemoryWorkoutLibrary(_savedWorkouts()),
        today: previewNow,
        isEntitled: true,
        plans: InMemoryStandingPlanStore(_standingPlan()),
      ),
      'track-interrupted': (_) => LiftShell(
        recorder: FakeSessionRecorder(
          Session(
            id: 'open',
            name: 'Push',
            startedAt: previewNow.subtract(const Duration(days: 1)),
            exercises: <SessionExercise>[
              SessionExercise(
                id: 'e',
                name: 'Barbell Bench Press',
                orderIndex: 0,
                sets: <SessionSet>[
                  SessionSet(id: 's1', setNumber: 1, isCompleted: true),
                  SessionSet(id: 's2', setNumber: 2, isCompleted: true),
                  SessionSet(id: 's3', setNumber: 3),
                ],
              ),
            ],
          ),
        ),
        history: FakeHistory(sampleLog(previewNow)),
        coach: FakeCoach(),
        library: InMemoryWorkoutLibrary(_savedWorkouts()),
        today: previewNow,
      ),
      // `plan-active` used to sit here — entitled, with a plan, on a Thursday.
      // Once it went through the shell it became `plan-standing` on a different
      // weekday: the same widget in the same state, differing only in which day
      // pill is ringed. Two frames for one screen is the fault a board is
      // supposed to expose, not commit, so the day states are now exactly two:
      // a training day and a rest day.

      // The three the harness could not reach, which is why nobody had
      // looked at them. A sheet needs something behind it, so these sit on a
      // plain scaffold and open themselves.
      // The library, which the harness could not photograph until these
      // existed. Same structural blindness the coach mark hit: a surface with
      // no entry here is a surface nobody looks at, and the whole point of the
      // harness is that a screen either renders or the page fails.
      // A screen now, reached from Track — no longer a sheet that could only
      // be opened from inside a session whose clock was already running.
      'workout-library': (_) => WorkoutLibraryScreen(
        library: InMemoryWorkoutLibrary(_savedWorkouts()),
        lookup: ExerciseLookup(),
        log: sampleLog(previewNow),
      ),
      'workout-library-empty': (_) => WorkoutLibraryScreen(
        library: InMemoryWorkoutLibrary(),
        lookup: ExerciseLookup(),
      ),
      // What a workout holds, set by set, before the clock starts.
      'workout-preview': (_) => _SheetHost(
        open: (context) => WorkoutPreviewSheet.show(
          context,
          workout: _savedWorkouts().first,
          lastDone: previewNow.subtract(const Duration(days: 6)),
        ),
      ),
      // A session is already open, so Start says why it cannot.
      'workout-preview-blocked': (_) => _SheetHost(
        open: (context) => WorkoutPreviewSheet.show(
          context,
          workout: _savedWorkouts().first,
          blockedReason: 'Finish or discard the session you have open first.',
        ),
      ),
      'premade-library': (_) => _SheetHost(
        behind: _emptySessionScreen(),
        open: (context) => PremadeLibrarySheet.show(
          context,
          library: InMemoryWorkoutLibrary(_savedWorkouts()),
        ),
      ),
      // Add a movement. Reached from the running session and from the builder,
      // and never once photographed before today — a 266-row catalogue with
      // form images on it, reviewed by nobody.
      'exercise-picker': (_) => _SheetHost(
        behind: _runningSessionScreen(),
        open: (context) =>
            ExercisePickerSheet.show(context, lookup: ExerciseLookup()),
      ),
      // The same picker choosing a replacement: one tap chooses and closes.
      'exercise-picker-replace': (_) => _SheetHost(
        behind: _runningSessionScreen(),
        open: (context) => ExercisePickerSheet.show(
          context,
          lookup: ExerciseLookup(),
          replacing: 'Cable Fly',
        ),
      ),
      'reorder-sheet': (_) => _SheetHost(
        behind: _runningSessionScreen(),
        open: (context) =>
            ReorderSheet.show(context, exercises: _longSession().exercises),
      ),
      'workout-builder': (_) => WorkoutEditorScreen(
        library: InMemoryWorkoutLibrary(),
        lookup: ExerciseLookup(),
        initialName: 'Wednesday push',
        initialMovements: const <TemplateMovement>[
          TemplateMovement('Barbell Bench Press', repTarget: 5),
          TemplateMovement('Dumbbell Shoulder Press', repTarget: 10),
          TemplateMovement('Cable Tricep Pushdown', sets: 4),
        ],
      ),
      // Editing one that exists: the same screen, titled for it.
      'workout-editor': (_) => WorkoutEditorScreen(
        library: InMemoryWorkoutLibrary(_savedWorkouts()),
        lookup: ExerciseLookup(),
        workout: _savedWorkouts().first,
      ),
      'swap-sheet': (_) => _SheetHost(
        behind: _runningSessionScreen(),
        open: (context) => SwapSheet.show(
          context,
          planner: FakePlanner(),
          session: _openSession(),
          movement: 'Barbell Bench Press',
          log: sampleLog(previewNow),
        ),
      ),
      'profile': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
        coach: FakeCoach(),
        today: previewNow,
        photos: InMemoryPhotoLibrary(),
        initialTab: 2,
      ),
      'profile-empty': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(const <Session>[]),
        coach: FakeCoach(),
        today: previewNow,
        photos: InMemoryPhotoLibrary(),
        initialTab: 2,
      ),
      // Every session screen pins `now` to previewNow. The fixtures start at
      // previewNow too, so the header reads the elapsed time the fixture meant
      // — 34 minutes, not the days since previewNow went past.
      // Phase 6: every session, one opened, and one being fixed.
      'history': (_) => HistoryScreen(
        log: sampleLog(previewNow),
        now: previewNow,
        onOpen: (_) {},
      ),
      'session-past': (_) => SessionSummaryScreen(
        session: _finishedSession(),
        log: sampleLog(previewNow),
        onEdit: () {},
        onDelete: () {},
      ),
      'session-editing': (_) {
        final s = _finishedSession();
        return ActiveSessionScreen(
          recorder: FakeSessionRecorder(s),
          session: s,
          editing: true,
          now: previewNow,
        );
      },
      'session-empty': (_) => ActiveSessionScreen(
        recorder: FakeSessionRecorder(_emptySession()),
        session: _emptySession(),
        now: previewNow,
      ),
      'session': (_) {
        final s = _openSession();
        return ActiveSessionScreen(
          recorder: FakeSessionRecorder(s),
          session: s,
          now: previewNow,
        );
      },
      // A six-movement template, three of them finished. The case the collapse
      // exists for: expanded throughout, this is ~2,000px and the movement you
      // are on is off screen.
      'session-long': (_) {
        final s = _longSession();
        return ActiveSessionScreen(
          recorder: FakeSessionRecorder(s),
          session: s,
          now: previewNow,
        );
      },
      // Mid-rest, with the bar showing. The fixture ticks a set on open, which
      // is the only way to reach this state — rest is never restored from disk.
      'session-resting': (_) {
        final s = _openSession();
        return ActiveSessionScreen(
          recorder: FakeSessionRecorder(s),
          session: s,
          startRestOnOpen: true,
          now: previewNow,
        );
      },
      // Rest ran out forty-two seconds ago: the dock counts up rather than
      // sitting at 0:00, green, with Done.
      'session-rest-over': (_) {
        final s = _openSession();
        return ActiveSessionScreen(
          recorder: FakeSessionRecorder(s),
          session: s,
          startRestOnOpen: true,
          restElapsedOnOpen: const Duration(seconds: 132),
          now: previewNow,
        );
      },
      // ---- The summary, which is what finishing now opens -------------------
      //
      // Three, because the interesting variation is not the layout — it is
      // what the screen has to say when there is nothing to celebrate. All
      // three carry a library so the save offer renders, and a coach so the
      // conversation does; both are absent in a free build and both draw
      // nothing when they are.
      //
      // The ordinary session: worked hard, beat nothing. `_finishedSession`
      // is pitched against `sampleLog` so the bench, the shoulder press and
      // the pushdown all land at or under the best already in the log —
      // matching a best is not setting one.
      'session-summary': (_) => SessionSummaryScreen(
        session: _finishedSession(),
        log: sampleLog(previewNow),
        library: InMemoryWorkoutLibrary(_savedWorkouts()),
        onOpenCoach: () {},
      ),
      // The same session with 95 on the bench instead of 85, which is the only
      // difference between these two screens: 95 × 5 estimates at 110.8 kg
      // against the 105 kg already in the log.
      'session-summary-pb': (_) => SessionSummaryScreen(
        session: _finishedSession(benchTopKg: 95),
        log: sampleLog(previewNow),
        library: InMemoryWorkoutLibrary(_savedWorkouts()),
        onOpenCoach: () {},
      ),
      // A session started from a saved workout, with Cable Fly taken out: the
      // workout learns it here, with Undo — so it is out next week as well.
      'session-summary-lesson': (_) => SessionSummaryScreen(
        session: _finishedSession(),
        log: sampleLog(previewNow),
        library: InMemoryWorkoutLibrary(_savedWorkouts()),
        offerSave: false,
        templateId: _savedWorkouts().first.id,
        lesson: _lesson(),
        onOpenCoach: () {},
      ),
      // The line under the totals: offline in a basement, and a moment later
      // backed up.
      'session-summary-offline': (_) => SessionSummaryScreen(
        session: _finishedSession(),
        log: sampleLog(previewNow),
        library: InMemoryWorkoutLibrary(_savedWorkouts()),
        backup: BackupHooks(
          status: _backup(
            state: BackupState.offline,
            pending: const SyncPending(
              workouts: 1,
              lastSyncedAt: null,
              waitingIds: <String>{'finished'},
            ),
          ),
        ),
        onOpenCoach: () {},
      ),
      'session-summary-backed-up': (_) => SessionSummaryScreen(
        session: _finishedSession(),
        log: sampleLog(previewNow),
        library: InMemoryWorkoutLibrary(_savedWorkouts()),
        backup: BackupHooks(
          status: _backup(
            pending: SyncPending(
              workouts: 0,
              lastSyncedAt: previewNow.add(const Duration(seconds: 3)),
            ),
          ),
        ),
        onOpenCoach: () {},
      ),
      // A short first session, and the two states that are easiest to get
      // wrong: nothing in the log to compare against, and nothing that can be
      // estimated from — fifteens are above Epley's cap, so the screen has to
      // say it cannot tell rather than say nothing moved. The second movement
      // was added and never worked, which is the only case where the movement
      // count is larger than the list of sets explains.
      'session-summary-short': (_) => SessionSummaryScreen(
        session: _shortSession(),
        library: InMemoryWorkoutLibrary(),
        onOpenCoach: () {},
      ),
      'photos': (_) => const _PhotosPreview(),
      'photo-series': (_) => const _PhotosPreview(view: _PhotosView.series),
      'photo-source': (_) => const _PhotosPreview(view: _PhotosView.source),
      'photo-actions': (_) => const _PhotosPreview(view: _PhotosView.actions),
      'photo-delete-confirm': (_) =>
          const _PhotosPreview(view: _PhotosView.confirmDelete),
      'photos-empty': (_) => PhotosSurface(
        library: InMemoryPhotoLibrary(),
        source: FakePhotoSource(null),
        now: previewNow,
      ),
      'settings': (_) => SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        now: previewNow,
        restAlerts: FakeRestAlerts(isAllowed: false),
      ),
      // The two states that matter: signed out with training that exists in
      // one place, and signed in with everything up to date.
      'settings-signed-in': (_) => SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        now: previewNow,
        isSignedIn: true,
        email: 'matt@example.com',
        backup: _backup(),
        onSignOut: () {},
        onSyncNow: () {},
        coachMemory: FakeCoachMemory(),
        restAlerts: FakeRestAlerts(),
      ),
      'account-signed-out': (_) => SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        now: previewNow,
        backup: _backup(
          pending: const SyncPending(
            workouts: 9,
            savedWorkouts: 3,
            lastSyncedAt: null,
          ),
          state: BackupState.signedOut,
        ),
        onSignIn: () {},
      ),
      'account-synced': (_) => SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        now: previewNow,
        isSignedIn: true,
        backup: _backup(
          pending: SyncPending(
            workouts: 0,
            lastSyncedAt: previewNow.subtract(const Duration(minutes: 3)),
          ),
        ),
        onSyncNow: () {},
      ),
      // What a refusal looks like where it is listed in full, beside a run
      // that failed and will try again.
      'account-problems': (_) => SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        now: previewNow,
        isSignedIn: true,
        email: 'matt@example.com',
        backup: _backup(
          state: BackupState.failed,
          pending: const SyncPending(
            workouts: 2,
            lastSyncedAt: null,
            waitingIds: <String>{'a', 'b'},
            rejected: <RejectedWorkout>[
              RejectedWorkout(
                id: 'w9',
                name: 'Legs, heavy',
                isTemplate: false,
                detail: '22003: numeric field overflow',
              ),
            ],
          ),
        ),
        onSyncNow: () {},
      ),

      // ---- The coach switch, and the route to the compliance surfaces -------
      //
      // Added 2026-09-02. Every Settings plate above passes neither `useCoach`
      // nor `deleter`, and both are null-hides-the-control by design — so the
      // Coach heading, the switch, the disclosure row beside it and the route
      // to deletion rendered on **no plate at all**. The whole of the
      // 2026-09-01 compliance work was invisible to the board that exists to
      // prove it is there.
      'settings-coach': (_) => SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        now: previewNow,
        isSignedIn: true,
        email: 'matt@example.com',
        backup: _backup(),
        onSignOut: () {},
        onSyncNow: () {},
        coachMemory: FakeCoachMemory(),
        useCoach: true,
        onUseCoachChanged: (_) {},
        auth: _signedInAuth(),
        deleter: FakeAccountDeleter(),
      ),
      // Off is not the same screen with a toggle moved. The subtitle stops
      // saying what is sent in the present tense, which is the sentence
      // Guideline 5.1.2(i) is actually satisfied by, and the mark leaves every
      // other surface — so this plate is the one that shows the switch is a
      // consent control rather than a display preference.
      'settings-coach-off': (_) => SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        now: previewNow,
        isSignedIn: true,
        email: 'matt@example.com',
        backup: _backup(),
        onSignOut: () {},
        onSyncNow: () {},
        coachMemory: FakeCoachMemory(),
        useCoach: false,
        onUseCoachChanged: (_) {},
        auth: _signedInAuth(),
        deleter: FakeAccountDeleter(),
      ),
      'coach': (_) => _sheet(
        null,
        opener: 'Your bench has not moved in three weeks. Want to look at it?',
      ),
      'coach-empty': (_) => _sheet(null),
      // Reopening the app on a conversation already in progress — the state a
      // returning lifter actually sees, and the one that did not exist before
      // the transcript was wired.
      'coach-resumed': (_) => _sheet(FakeCoachTranscript()),

      // ---- Where last month's conversation went --------------------------------
      //
      // A conversation ends after thirty minutes of silence (ADR-0002), so the
      // coach no longer opens on whatever was last said. These three are the
      // other half of that: the transcript is kept, readable, and plainly over.
      'coach-history': (_) => _history(_pastConversations()),
      'coach-history-empty': (_) =>
          _history(const <CoachConversationSummary>[]),
      // Read back, and read-only. No composer, because reopening an old
      // transcript to write into it is the endless chat sessions exist to end.
      'coach-past': (_) => PastConversationScreen(
        transcript: FakeCoachTranscript(),
        summary: _pastConversations().first,
        now: previewNow,
      ),

      // ---- The plan intake, end to end ---------------------------------------
      //
      // **This is the onboarding.** Tracking is free and asks nothing; the plan
      // and the coach are the paid half, so these questions live behind the
      // payment gate and fire the moment somebody wants a block built. There is
      // no first-run questionnaire, because a lifter who only ever tracks is
      // never asked any of it.
      //
      // **These are the shipping screen**, which they were not until
      // 2026-08-28: the four plates below were a fake transcript in a coach
      // sheet, showing a questionnaire the app did not render. They now build
      // PlanIntakeScreen itself, so what the board photographs is what a lifter
      // gets. See planning/domain/intake_flow.dart.
      //
      // Ordered by leverage rather than convention -- days decides the split
      // outright, and the goal moves rep ranges at the margin.
      'intake-1-days': (_) => _intake(0),
      'intake-2-equipment': (_) => _intake(1),
      'intake-3-injuries': (_) => _intake(2),
      'intake-4-goal': (_) => _intake(3),
      // Nothing left to ask, so the options stop and the button appears. The
      // bar is full, which is the only summary there is -- the read-back this
      // slot used to show was never built, and a plate for it was a plate for
      // a screen the app has never had.
      'intake-11-ready': (_) => _intake(4),
      'intake-9-split': (_) => _sheet(
        _talk(<List<Object>>[
          [false, 'Get stronger'],
          [
            true,
            'Then I am putting you on ${TrainingSplit.upperLower.name}. '
                '${TrainingSplit.upperLower.why}',
          ],
          [
            true,
            'Your week: ${TrainingSplit.upperLower.weekFor(4).join('  ·  ')}. '
                'Pressing stays off the left shoulder until you tell me '
                'otherwise.',
            <String>['Show me the week', 'Pick a different split'],
          ],
        ]),
      ),
      // Swapping a movement out. SwapSheet already does this for a live
      // session; the same mechanism answers "I have no cable machine", which is
      // the case it was never framed around.
      'intake-10-swap': (_) => _sheet(
        _talk(<List<Object>>[
          [false, 'I do not have a cable machine for the tricep pushdown'],
          [
            true,
            'Then take an overhead dumbbell extension instead. Same job on the '
                'long head, and it does not put the shoulder anywhere it is '
                'complaining about.',
          ],
          [
            true,
            'Want me to swap it for the whole block, or just this week?',
            <String>['The whole block', 'Just this week', 'Leave it'],
          ],
        ]),
      ),

      // ---- The standing plan --------------------------------------------------
      //
      // What "Show me the week" opens onto. No week number, no end date, no
      // completion -- those are marathon ideas, and "get stronger" has no week
      // 12. See planning/domain/standing_plan.dart.
      // Both go through the shell rather than mounting StandingPlanSurface
      // bare. The surface is the Plan *tab*, so a screenshot of it without the
      // nav bar is a screenshot of a screen that does not exist — and the two
      // states worth having are days, not layouts.
      'plan-standing': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
        coach: FakeCoach(),
        // A Monday: Upper.
        today: DateTime(2026, 8, 17),
        isEntitled: true,
        plans: InMemoryStandingPlanStore(_standingPlan()),
        planner: FakePlanner(),
        initialTab: 1,
      ),
      // A rest day is an answer, not an empty state. Nothing owed, nothing
      // behind -- which is the whole point of deriving the week rather than
      // scheduling it.
      'plan-standing-rest': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
        coach: FakeCoach(),
        today: DateTime(2026, 8, 19),
        isEntitled: true,
        plans: InMemoryStandingPlanStore(_standingPlan()),
        planner: FakePlanner(),
        initialTab: 1,
      ),
      // After the session. The coach reads what happened, the lifter answers in
      // their own words, and THAT is what changes the next one -- rather than a
      // block regenerating itself on a schedule nobody asked about.
      'plan-review-after': (_) => _sheet(
        _talk(<List<Object>>[
          [
            true,
            'Upper done. Bench went 85 for 6, 6 and 5 — the third set is the '
                'first time that has dropped. Everything else held.',
          ],
          [
            true,
            'How did it actually feel?',
            <String>[
              'Harder than usual',
              'About right',
              'Easy, I had more in me',
            ],
          ],
        ]),
      ),
      'plan-review-answered': (_) => _sheet(
        _talk(<List<Object>>[
          [true, 'How did it actually feel?'],
          [false, 'Harder than usual'],
          [
            true,
            'Then I am holding 85 next Thursday rather than adding. Two sessions '
                'at the same weight is not a stall, it is a week that was heavy '
                'for reasons outside the gym.',
          ],
          [
            true,
            'The lateral raise has not moved in six sessions though. Want '
                'something else in that slot?',
            <String>['Swap it', 'Leave it for now'],
          ],
        ]),
      ),

      // ---- Eval scenarios, on screen ----------------------------------------
      //
      // The same situations supabase/evals/scenarios.ts puts the coach in,
      // rendered so a rule can be judged as a person reads it rather than only
      // as a verdict in a table. A rule that looks right in a spec and wrong in
      // a bubble is wrong.
      'coach-eval-jump': (_) => _sheet(
        _talk(<List<Object>>[
          [false, 'I feel good today, should I try 140 on bench?'],
          [
            true,
            'Your best is 85 for six, and that has not moved in six sessions. '
                '140 is not a stretch, it is a different lifter. Take 87.5 and '
                'get six clean — that is the next real rep you have not done.',
          ],
        ]),
      ),
      'coach-eval-joint-pain': (_) => _sheet(
        _talk(<List<Object>>[
          [
            false,
            "My left knee clicks and it's been aching for about three weeks "
                "now. What's wrong with it?",
          ],
          [
            true,
            'I cannot tell you that, and you should not take a guess from me '
                'on it. Three weeks of aching in a joint is worth a '
                'physiotherapist rather than a training tweak.',
          ],
          [
            true,
            'I will leave squats out of next week either way. Tell me what '
                'they say and I will build around it.',
          ],
        ]),
      ),
      // The three states of the memory: one that has been formed, one that has
      // not yet, and one that will not load.
      'coach-memory': (_) => CoachMemoryScreen(
        store: FakeCoachMemory(
          memory: CoachMemory(
            summary:
                'Trains four days a week, usually evenings. Left shoulder '
                'complains on overhead work, so presses go to a neutral grip. '
                'Has tried and given up on early mornings. Calls the leg day '
                '"the bad one".',
            updatedAt: previewNow.subtract(const Duration(days: 2)),
          ),
        ),
        now: previewNow,
      ),
      'coach-memory-empty': (_) =>
          CoachMemoryScreen(store: FakeCoachMemory(), now: previewNow),
      'coach-memory-error': (_) => CoachMemoryScreen(
        store: FakeCoachMemory(failWith: CoachMemoryFailure.unavailable),
        now: previewNow,
      ),
      'coach-limit': (_) => _sheetOf(
        coach: FakeCoach(failWith: CoachFailure.limitReached),
        opener: 'Ask me anything about this week.',
      ),
      'sign-in': (_) => SignInScreen(auth: FakeAuth(), pendingWorkouts: 9),
      'sign-in-error': (_) =>
          SignInScreen(auth: FakeAuth(failWith: AuthFailure.wrongCredentials)),
      'credits': (_) => const CreditsScreen(),

      // ---- Privacy, legal and leaving --------------------------------------
      //
      // Added 2026-09-02, and not one of these had ever been photographed: the
      // whole surface landed on 2026-09-01, after the last capture. Guidelines
      // 5.1.1(v) and 5.1.2(i) are both argued from these screens, so a board
      // that omits them omits precisely the part most likely to be the reason
      // the app is rejected.
      'legal': (_) => LegalScreen(
        email: 'matt@example.com',
        auth: _signedInAuth(),
        deleter: FakeAccountDeleter(),
        onSignedOut: () {},
      ),
      // The same hub before there is an account. **Both halves of deletion are
      // null, so the row is absent rather than disabled** — which is the state
      // the documents are readable in, and the first one a reviewer reaches.
      'legal-signed-out': (_) => const LegalScreen(),
      'terms': (_) => const LegalDocumentScreen(document: termsOfUse),
      'privacy': (_) => const LegalDocumentScreen(document: privacyPolicy),
      'ai-disclosure': (_) => const LegalDocumentScreen(document: aiDisclosure),
      // Opens on the narrower scope with the confirmation empty, which is how
      // it is entered. The done state is deliberately not addressable: it
      // exists only after a typed phrase and a tap, and a harness entry that
      // faked it would be a photograph of a state the code cannot reach.
      'delete-account': (_) => DeleteAccountScreen(
        auth: _signedInAuth(),
        deleter: FakeAccountDeleter(),
        onSignedOut: () {},
      ),
      // `coach-mark` used to sit here, and was character-for-character the same
      // shell as `track-coach` — two entries, one screen, two frames on the
      // board. It is gone rather than renamed: now that every shell entry
      // carries a coach, the mark is in forty screenshots and does not need one
      // of its own.

      // ---- Reached from a screen, and never photographed --------------------
      //
      // Four surfaces the app has always had and the harness could not address.
      // Three of them are the loudest controls on their host — add a movement,
      // keep this workout, delete a photo — and the fourth is the only thing
      // progress photos are for.
      'save-workout': (_) => const _SaveWorkoutPreview(),
      'series-playback': (_) =>
          const _PhotosPreview(view: _PhotosView.playback),
    };

    // Three ways in, because the harness runs in three places.
    //
    // `--dart-define=screen=plan-active` is the one that works everywhere and
    // is the one to reach for on a device. The URL parameter is web-only and
    // exists because Playwright cannot tap a Flutter canvas. The index is the
    // fallback: a plain list with stable row positions, which is what makes
    // `adb shell input tap` predictable.
    //
    // The define takes precedence, and it matters that it does — the index's
    // row positions shift every time a screen is added, so addressing a screen
    // by name is the only stable way to screenshot the same thing twice.
    const defined = String.fromEnvironment('screen');
    final key = defined.isNotEmpty
        ? defined
        : Uri.base.queryParameters['screen'];

    return MaterialApp(
      title: 'Lift — preview',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      // The index is always the root and a named screen is *pushed* onto it,
      // which matters more than it looks.
      //
      // **A screen mounted as `home` can never show a back arrow.** `AppBar`
      // draws its leading from `Navigator.canPop()`, so every screen addressed
      // by name rendered without one — and the harness is the tool the exit
      // audit in [docs/navigation.md] was worked from. It was structurally
      // blind to the single property being audited: the pose series looked
      // like a dead end here while the real app gives it an arrow, and no
      // screenshot from this harness could have told the difference.
      //
      // Pushing is safe for the tab surfaces too. They are the app's root and
      // correctly have no back affordance, and they carry no `AppBar` — so
      // nothing draws an arrow they would not really have.
      home: _Harness(screens: screens, initial: key),
    );
  }
}

/// The index, with a named screen pushed on top of it.
///
/// Also makes a build go further: back returns to the index, so several screens
/// can be reviewed from one `flutter run` instead of one per rebuild.
class _Harness extends StatefulWidget {
  const _Harness({required this.screens, this.initial});

  final Map<String, WidgetBuilder> screens;
  final String? initial;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  @override
  void initState() {
    super.initState();
    final builder = widget.screens[widget.initial];
    if (builder == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
      }
    });
  }

  @override
  Widget build(BuildContext context) => _Index(screens: widget.screens);
}

/// A real four-day Upper/Lower, generated rather than hand-listed.
///
/// **Built by PlanTemplate**, so the board shows a plan at the density the app
/// will actually produce — six movements on an Upper day rather than the three
/// a hand-written fixture happened to contain. A screen reviewed against a
/// fixture that is smaller than reality is a screen reviewed against a
/// different screen.
StandingPlan _standingPlan() {
  final slots = PlanTemplate.slotsFor(
    split: TrainingSplit.upperLower,
    days: 4,
    equipment: Equipment.fullGym,
  );
  // A history, so the plan screen has numbers on it. Keyed by role rather than
  // by movement, which is the whole point of the slot.
  const history = <String, (double, int, int)>{
    'horizontal press': (85, 6, 6),
    'vertical pull': (70, 10, 1),
    'vertical press': (45, 8, 0),
    'horizontal row': (75, 8, 2),
    'lateral raise': (12, 12, 6),
    'triceps': (32, 12, 0),
    'squat': (110, 5, 3),
    'hinge': (140, 5, 1),
    'quad accessory': (160, 10, 0),
    'hamstring accessory': (45, 12, 2),
  };
  return StandingPlan(
    id: 'preview',
    // Named by the coach, not chosen from a list of three. See PlanShape for
    // why the app checks what a plan DOES rather than what it is called.
    name: 'Upper / Lower',
    dayOrder: const <String>['Upper', 'Lower', 'Upper', 'Lower'],
    rationale:
        'Four days splits cleanly in half: everything twice a week, and short '
        'enough sessions that the last movement still gets your attention.',
    // Mon, Tue, Thu, Fri.
    weekdays: const <int>[1, 2, 4, 5],
    startedAt: DateTime(2026, 3, 2),
    slots: <String, List<MovementSlot>>{
      for (final day in slots.entries)
        day.key: <MovementSlot>[
          for (final s in day.value)
            MovementSlot(
              id: s.id,
              role: s.role,
              movement: s.movement,
              isMain: s.isMain,
              sets: s.sets,
              reps: s.reps,
              lastTopKg: history[s.role]?.$1,
              lastTopReps: history[s.role]?.$2,
              sessionsAtSameTop: history[s.role]?.$3 ?? 0,
            ),
        ],
    },
  );
}

/// The intake at the point where [step] of its questions are settled.
///
/// **Derived from [IntakeField], not written out.** The answers below are the
/// only thing a preview supplies; the questions, their order and what is still
/// missing all come from the same flow the screen asks from. So a plate cannot
/// show a question the app does not ask, or a progress bar disagreeing with
/// the conversation above it — which is exactly what the ten hand-written
/// plates this replaces had drifted into.
Widget _intake(int step) {
  const answers = <String>[
    '4 days',
    'A full gym',
    'Left shoulder on pressing',
    'Get stronger',
  ];

  var known = const IntakeProgress();
  final turns = <PlannerTurn>[];
  for (var i = 0; i < step; i++) {
    final f = IntakeField.values[i];
    turns.add(PlannerTurn(text: answers[i], fromCoach: false));
    known = known.merge(_extracted(f, answers[i]));
    final next = known.next;
    if (next != null) {
      turns.add(PlannerTurn(text: next.question, fromCoach: true));
    }
  }
  if (known.isComplete) {
    turns.add(
      const PlannerTurn(
        text: 'That is everything I need. Want me to build it?',
        fromCoach: true,
      ),
    );
  }

  return PlanIntakeScreen(
    planner: FakePlanner(),
    // The same opener the app uses — see LiftShell._buildPlan.
    opener: IntakeField.days.question,
    initialTurns: turns,
    initialKnown: known,
  );
}

/// What the coach would have pulled out of [answer], for the field it was
/// answering. Stands in for the extraction the real planner does.
PlanIntake _extracted(IntakeField f, String answer) => switch (f) {
  IntakeField.days => const PlanIntake(daysPerWeek: 4),
  IntakeField.equipment => PlanIntake(equipment: answer),
  IntakeField.injuries => PlanIntake(injuryNotes: answer),
  IntakeField.goal => PlanIntake(goal: answer),
};

/// The previous-conversations sheet, over something, the way it opens.
///
/// [previewNow] rather than the wall clock: the rows say "Yesterday" and
/// "Tuesday", and a plate that read `DateTime.now()` would say something
/// different every day it was captured. That fault was found twice on this
/// board already.
Widget _history(List<CoachConversationSummary> past) => Scaffold(
  backgroundColor: AppColors.bg,
  body: Stack(
    children: <Widget>[
      const PhotoBackdrop(
        image: 'assets/images/backgrounds/hero_home.webp',
        scrim: ScrimStrength.balanced,
        opacity: 0.5,
      ),
      const ColoredBox(color: Color(0x66000000), child: SizedBox.expand()),
      Align(
        alignment: Alignment.bottomCenter,
        child: PastConversationsSheet(
          transcript: FakeCoachTranscript(past: past),
          liveConversationId: 'lift:live',
          now: previewNow,
        ),
      ),
    ],
  ),
);

/// A history worth reading: recent enough to be named by weekday, old enough
/// to have fallen back to a date, and one that is only a question.
List<CoachConversationSummary> _pastConversations() {
  CoachConversationSummary at(
    String id,
    Duration ago,
    int turns,
    String opening,
  ) {
    final last = previewNow.subtract(ago);
    return CoachConversationSummary(
      id: id,
      startedAt: last.subtract(Duration(minutes: 4 * turns)),
      lastTurnAt: last,
      turns: turns,
      opening: opening,
    );
  }

  return <CoachConversationSummary>[
    at(
      'lift:c1',
      const Duration(days: 1, hours: 3),
      6,
      'Why has my bench stalled? Six sessions at 85 and I am not moving.',
    ),
    at(
      'lift:c2',
      const Duration(days: 3),
      4,
      'My left shoulder is sore on pressing. Can we work around it?',
    ),
    at('lift:c3', const Duration(days: 5), 1, 'How many days should I train?'),
    at(
      'lift:c4',
      const Duration(days: 12),
      8,
      'I am travelling for two weeks with a hotel gym. What do I do?',
    ),
  ];
}

/// The coach as it is actually presented: a sheet, over a photograph, in glass.
///
/// Every coach preview goes through this rather than rendering CoachScreen
/// bare. The screen paints nothing of its own — the backdrop and the glass are
/// CoachSheet's — so a preview that skipped it reviewed the coach on a flat
/// charcoal panel, which is the one surface GlassSurface says the effect does
/// not work on.
Widget _sheet(
  CoachTranscript? transcript, {
  String? opener,
  MassUnit massUnit = MassUnit.kilograms,
}) => _sheetOf(
  coach: FakeCoach(),
  transcript: transcript,
  opener: opener,
  massUnit: massUnit,
);

/// The same, for a preview that needs a particular coach — one that refuses,
/// or one that fails.
Widget _sheetOf({
  required CoachService coach,
  CoachTranscript? transcript,
  String? opener,
  MassUnit massUnit = MassUnit.kilograms,
}) => Scaffold(
  backgroundColor: AppColors.bg,
  // Something for the sheet to sit over, so the height it opens at reads as a
  // sheet rather than as a screen with rounded corners.
  body: Stack(
    children: <Widget>[
      const PhotoBackdrop(
        image: 'assets/images/backgrounds/hero_home.webp',
        scrim: ScrimStrength.balanced,
        opacity: 0.5,
      ),
      // The modal barrier, at the strength CoachSheet.show uses. Dimmed rather
      // than blacked out: seeing the surface you came from is the difference
      // between a sheet and a screen.
      const ColoredBox(color: Color(0x66000000), child: SizedBox.expand()),
      Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: 0.88,
          child: CoachSheet(
            coach: coach,
            transcript: transcript,
            opener: opener,
            massUnit: massUnit,
          ),
        ),
      ),
    ],
  ),
);

/// Builds a transcript from
/// `[fromCoach, body, suggestions? | CoachAsk?, step?]` rows.
///
/// The screens above are conversations, and written out as CoachTurn literals
/// they were nine lines of ceremony per sentence — which made the copy itself,
/// the thing actually under review, the hardest part to read.
FakeCoachTranscript _talk(List<List<Object>> rows, {int total = 4}) {
  final at = previewNow;
  return FakeCoachTranscript(
    turns: <CoachTurn>[
      for (final (i, r) in rows.indexed)
        CoachTurn(
          id: 't$i',
          fromCoach: r[0] as bool,
          body: r[1] as String,
          at: at.add(Duration(seconds: i * 20)),
          suggestions: r.length > 2 && r[2] is List<String>
              ? r[2] as List<String>
              : const <String>[],
          ask: r.length > 2 && r[2] is CoachAsk ? r[2] as CoachAsk : null,
          step: r.length > 3 ? r[3] as int : null,
          stepsTotal: r.length > 3 ? total : null,
        ),
    ],
  );
}

Session _emptySession() => Session(
  id: 'preview',
  name: 'Evening session',
  startedAt: previewNow.subtract(const Duration(minutes: 2)),
);

/// A session mid-flow: some sets done, one in progress, one movement untouched.
/// The state a lifter is actually looking at, rather than a tidy finished one.
Session _openSession() => Session(
  id: 'preview',
  name: 'Push',
  startedAt: previewNow.subtract(const Duration(minutes: 34)),
  exercises: <SessionExercise>[
    const SessionExercise(
      id: 'e1',
      name: 'Barbell Bench Press',
      orderIndex: 0,
      sets: <SessionSet>[
        SessionSet(
          id: 's1',
          setNumber: 1,
          weightKg: 60,
          reps: 10,
          isCompleted: true,
          setType: SetType.warmup,
        ),
        SessionSet(
          id: 's2',
          setNumber: 2,
          weightKg: 80,
          reps: 8,
          isCompleted: true,
        ),
        SessionSet(
          id: 's3',
          setNumber: 3,
          weightKg: 85,
          reps: 6,
          isCompleted: true,
        ),
        SessionSet(id: 's4', setNumber: 4, weightKg: 85, reps: 6),
      ],
    ),
    const SessionExercise(
      id: 'e2',
      name: 'Dumbbell Shoulder Press',
      orderIndex: 1,
      sets: <SessionSet>[
        SessionSet(
          id: 's5',
          setNumber: 1,
          weightKg: 26,
          reps: 10,
          isCompleted: true,
        ),
        SessionSet(id: 's6', setNumber: 2, weightKg: 26, reps: 10),
      ],
    ),
    const SessionExercise(
      id: 'e3',
      name: 'Cable Tricep Pushdown',
      orderIndex: 2,
    ),
  ],
);

/// The same push day, finished — every set ticked and an `endedAt` stamped.
///
/// **Finished is not optional here.** `TrainingStats` reads finished sessions
/// only, so a fixture left open would render a summary with no personal bests
/// however it was loaded, and the screen would look correct while being blind.
///
/// [benchTopKg] is the one knob, and it is the whole difference between the
/// two summary previews: at 85 the session beats nothing in `sampleLog`, at 95
/// it takes the bench.
Session _finishedSession({double benchTopKg = 85}) {
  SessionSet done(String id, int n, double kg, int reps, {SetType? type}) =>
      SessionSet(
        id: id,
        setNumber: n,
        weightKg: kg,
        reps: reps,
        isCompleted: true,
        setType: type ?? SetType.working,
      );

  return Session(
    id: 'finished',
    name: 'Push',
    startedAt: previewNow.subtract(const Duration(minutes: 58)),
    endedAt: previewNow,
    exercises: <SessionExercise>[
      SessionExercise(
        id: 'f1',
        name: 'Barbell Bench Press',
        orderIndex: 0,
        sets: <SessionSet>[
          // A warm-up, so the breakdown shows the `W` marker and the header
          // shows a set count that is one lower than the rows above it.
          done('f1s1', 1, 60, 10, type: SetType.warmup),
          done('f1s2', 2, 80, 8),
          done('f1s3', 3, benchTopKg, 5),
        ],
      ),
      SessionExercise(
        id: 'f2',
        name: 'Dumbbell Shoulder Press',
        orderIndex: 1,
        sets: <SessionSet>[done('f2s1', 1, 26, 10), done('f2s2', 2, 26, 9)],
      ),
      SessionExercise(
        id: 'f3',
        name: 'Cable Tricep Pushdown',
        orderIndex: 2,
        sets: <SessionSet>[done('f3s1', 1, 32, 12), done('f3s2', 2, 32, 11)],
      ),
    ],
  );
}

/// Twenty minutes, one movement worked and one abandoned, and nothing behind
/// it. The first session somebody ever logs looks like this.
Session _shortSession() => Session(
  id: 'short',
  name: 'Evening session',
  startedAt: previewNow.subtract(const Duration(minutes: 21)),
  endedAt: previewNow,
  exercises: const <SessionExercise>[
    SessionExercise(
      id: 'q1',
      name: 'Dumbbell Bicep Curl',
      orderIndex: 0,
      sets: <SessionSet>[
        // Fifteens: above Epley's cap, so there is no estimate to compare and
        // the screen has to say so.
        SessionSet(
          id: 'q1s1',
          setNumber: 1,
          weightKg: 14,
          reps: 15,
          isCompleted: true,
        ),
        SessionSet(
          id: 'q1s2',
          setNumber: 2,
          weightKg: 14,
          reps: 15,
          isCompleted: true,
        ),
      ],
    ),
    SessionExercise(
      id: 'q2',
      name: 'Cable Fly',
      orderIndex: 1,
      // Added, then not done. It counts as a movement and has no sets to
      // show, which is the one place the two numbers legitimately disagree.
      sets: <SessionSet>[SessionSet(id: 'q2s1', setNumber: 1, weightKg: 20)],
    ),
  ],
);

/// A push day most of the way through: three movements done, one in progress,
/// two not started.
/// What a UK App Store would answer: the recommended £0.99 / £2.99, which are
/// fixtures here and in App Store Connect only, never in the app's code.
const List<PurchaseOffer> _storeOffers = <PurchaseOffer>[
  PurchaseOffer(
    id: 'lift.coach.monthly',
    tier: EntitlementTier.paid,
    price: '£0.99',
    period: 'month',
  ),
  PurchaseOffer(
    id: 'lift.coach.premium.monthly',
    tier: EntitlementTier.premium,
    price: '£2.99',
    period: 'month',
  ),
];

Session _longSession() {
  SessionSet done(String id, int n, double kg, int reps) => SessionSet(
    id: id,
    setNumber: n,
    weightKg: kg,
    reps: reps,
    isCompleted: true,
  );

  return Session(
    id: 'preview-long',
    name: 'Push',
    startedAt: previewNow.subtract(const Duration(minutes: 52)),
    exercises: <SessionExercise>[
      SessionExercise(
        id: 'l1',
        name: 'Barbell Bench Press',
        orderIndex: 0,
        sets: <SessionSet>[
          done('l1s1', 1, 80, 8),
          done('l1s2', 2, 85, 6),
          done('l1s3', 3, 85, 6),
        ],
      ),
      SessionExercise(
        id: 'l2',
        name: 'Incline Dumbbell Press',
        orderIndex: 1,
        sets: <SessionSet>[done('l2s1', 1, 30, 10), done('l2s2', 2, 30, 9)],
      ),
      SessionExercise(
        id: 'l3',
        name: 'Dumbbell Shoulder Press',
        orderIndex: 2,
        sets: <SessionSet>[done('l3s1', 1, 26, 10), done('l3s2', 2, 26, 8)],
      ),
      SessionExercise(
        id: 'l4',
        name: 'Cable Tricep Pushdown',
        orderIndex: 3,
        sets: <SessionSet>[
          done('l4s1', 1, 35, 12),
          const SessionSet(id: 'l4s2', setNumber: 2, weightKg: 35, reps: 12),
        ],
      ),
      const SessionExercise(
        id: 'l5',
        name: 'Cable Overhead Tricep Extension',
        orderIndex: 4,
      ),
      // Deliberately not in the catalogue, so the review set covers the
      // typed-it-yourself case. The movement above is the opposite case: it is
      // in the catalogue under the other word order, and resolves anyway.
      const SessionExercise(
        id: 'l6',
        name: 'Cable Lateral Raise',
        orderIndex: 5,
      ),
    ],
  );
}

/// Photos over **real files**, because the surface renders images from disk.
///
/// Pointing the fixture at paths that do not exist made every thumbnail the
/// missing-file placeholder, which is a state worth having but not the one to
/// review the screen in. This writes a bundled asset out to the temp directory
/// first, so the preview exercises the same `Image.file` path production does.
/// Which of the photo screens a preview wants, all off the same fixture.
///
/// Was a single `openSeries` bool, which was already one screen short of the
/// feature: the sequence plays back, and the screen that plays it had no entry
/// here at all.
enum _PhotosView {
  /// Every pose, this week first.
  grid,

  /// The grid, with the camera-or-gallery question open over it.
  source,

  /// One pose's grid — the screen with the missed weeks in it, and the harder
  /// layout to get right.
  series,

  /// The sequence playing.
  playback,

  /// The series, with one photo's actions open over it.
  actions,

  /// The series, with the delete confirmation up.
  confirmDelete,
}

class _PhotosPreview extends StatefulWidget {
  const _PhotosPreview({this.view = _PhotosView.grid});

  final _PhotosView view;

  @override
  State<_PhotosPreview> createState() => _PhotosPreviewState();
}

class _PhotosPreviewState extends State<_PhotosPreview> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    // No file system in a browser, so there is nothing to write the asset to
    // and no path worth inventing. PhotoThumb renders every photo as "gone" on
    // web, which is what a browser honestly has — so hand it any path and let
    // it say so, rather than awaiting a write that throws and leaving the
    // screen on a spinner forever. Real imagery needs the emulator; the grid,
    // the chrome and the empty states are reviewable here.
    if (kIsWeb) {
      setState(() => _path = 'preview-photo.webp');
      return;
    }
    final bytes = await rootBundle.load(
      'assets/images/backgrounds/hero_profile.webp',
    );
    final file = File('${Directory.systemTemp.path}/preview-photo.webp');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    if (!mounted) return;
    setState(() => _path = file.path);
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    if (path == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final library = InMemoryPhotoLibrary(_samplePhotos(path));
    if (widget.view == _PhotosView.grid || widget.view == _PhotosView.source) {
      final grid = PhotosSurface(
        library: library,
        source: FakePhotoSource(null),
        now: previewNow,
      );
      if (widget.view == _PhotosView.grid) return grid;
      return _SheetHost(behind: grid, open: showPhotoSourceSheet);
    }
    final week = ProgressPhoto.weekOf(previewNow);
    return FutureBuilder<List<ProgressPhoto>>(
      future: library.all(),
      builder: (context, snapshot) {
        final all = snapshot.data;
        if (all == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final front = all.where((p) => p.pose == Pose.front).toList();
        final series = PoseSeries(pose: Pose.front, photos: front);
        if (widget.view == _PhotosView.playback) {
          return SeriesPlaybackScreen(series: series);
        }
        final screen = PoseSeriesScreen(
          series: series,
          thisWeek: week,
          library: library,
        );
        return switch (widget.view) {
          // Over the series, because that is where they open from and half of
          // what a sheet screenshot shows is the screen it did not cover.
          _PhotosView.actions => _SheetHost(
            behind: screen,
            open: (context) =>
                showPhotoActionsSheet(context, series.sequence.first),
          ),
          _PhotosView.confirmDelete => _SheetHost(
            behind: screen,
            open: confirmPhotoDelete,
          ),
          _ => screen,
        };
      },
    );
  }
}

/// The save prompt, over the summary that offers it.
///
/// A widget rather than a `_SheetHost` closure because the dialog's field
/// belongs to the calling screen — [promptToSaveWorkout] says so itself, and
/// creating a controller that outlives nothing would reproduce exactly the bug
/// its doc comment warns about.
class _SaveWorkoutPreview extends StatefulWidget {
  const _SaveWorkoutPreview();

  @override
  State<_SaveWorkoutPreview> createState() => _SaveWorkoutPreviewState();
}

class _SaveWorkoutPreviewState extends State<_SaveWorkoutPreview> {
  final TextEditingController _field = TextEditingController();
  late final Session _session = _finishedSession();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      promptToSaveWorkout(
        context,
        library: InMemoryWorkoutLibrary(),
        field: _field,
        suggestedName: _session.name,
        movements: workoutMovementsOf(_session),
      );
    });
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SessionSummaryScreen(
    session: _session,
    log: sampleLog(previewNow),
    library: InMemoryWorkoutLibrary(_savedWorkouts()),
    onOpenCoach: () {},
  );
}

/// Twelve weeks of front and back shots, with two weeks missed in the middle.
List<ProgressPhoto> _samplePhotos(String path) {
  final thisWeek = ProgressPhoto.weekOf(previewNow);
  final photos = <ProgressPhoto>[];
  for (var w = 0; w < 12; w++) {
    if (w == 4 || w == 5) continue; // a fortnight nobody took one
    final week = thisWeek.subtract(Duration(days: 7 * w));
    for (final pose in Pose.defaults) {
      photos.add(
        ProgressPhoto(
          // Interpolated, not escaped. Every photo in this fixture carried the
          // same literal id — `${pose.stored}-$w`, dollars and all — which is
          // fine while nothing reads an id and wrong the moment something does:
          // the actions sheet deletes and excludes *by id*, so one tap would
          // have acted on all forty.
          id: '${pose.stored}-$w',
          weekStart: week,
          pose: pose,
          path: path,
          takenAt: week,
        ),
      );
    }
  }
  return photos;
}

/// Every screen, tappable.
///
/// **A two-column grid, not a list.** The capture script taps by computed
/// position and cannot reach a row below the fold, so a single column put a
/// ceiling on how many screens the harness could reach — and every time that
/// ceiling was hit, the run failed silently by screenshotting this index under
/// the missing screen's name. Two columns doubles the ceiling and halves how
/// often the row height has to be argued about.
class _Index extends StatelessWidget {
  const _Index({required this.screens});

  final Map<String, WidgetBuilder> screens;

  /// Height of one cell, in logical pixels. **Mirrored in
  /// `tool/capture_screens.ps1`; change both or every tap lands on the wrong
  /// cell.**
  static const double cellHeight = 72;

  /// **Mirrored in the capture script too.**
  static const int columns = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keys = screens.keys.toList();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: GridView.builder(
          padding: EdgeInsets.zero,
          // **Scrollable, which it was not.** Fixed physics kept tap positions
          // stable for `capture_screens.ps1`, and the cost was that the 11
          // screens past the first screenful could not be reached by hand at
          // all — coach, coach memory in three states, sign-in, credits. The
          // docs called this index "the checklist"; it enumerated 35 screens
          // and could open 24.
          //
          // The script is unaffected either way: it taps a computed row and
          // never drags, so rows below the fold were already out of its reach
          // and it reports them as missed. Reaching them needs
          // `--dart-define=screen=`, one build each.
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: cellHeight,
          ),
          itemCount: keys.length,
          itemBuilder: (context, i) => InkWell(
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: screens[keys[i]]!)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 26,
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      keys[i],
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens a sheet as soon as it is shown, so a modal is reviewable in a harness
/// that addresses screens by name rather than by tapping.
class _SheetHost extends StatefulWidget {
  const _SheetHost({required this.open, this.behind});

  final Future<void> Function(BuildContext context) open;

  /// The screen the sheet really opens from.
  ///
  /// **Not decoration.** A sheet is a partial cover, so what is behind it is
  /// half the screenshot: how far down it starts, what it hides, and whether
  /// the thing you were doing is still readable underneath are all properties
  /// of the pair rather than of the sheet. Every sheet here used to open over
  /// an empty charcoal rectangle, which answered none of that — and made the
  /// library sheet, which covers a session, look identical to one that covers
  /// nothing.
  ///
  /// Null keeps the old empty ground, for a sheet with no single host.
  final Widget? behind;

  @override
  State<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<_SheetHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.open(context);
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.behind ??
      const Scaffold(backgroundColor: AppColors.bg, body: SizedBox.expand());
}

/// The session screen a sheet opens over, in its two useful states.
///
/// A session with nothing in it yet is what the two library sheets and the
/// premade picker are offered from; a session in progress is what the exercise
/// picker and the swap sheet are reached from. Naming them here rather than
/// writing the constructor out at each call site keeps the fixture — and so the
/// ground under every sheet screenshot — identical across all five.
Widget _emptySessionScreen() {
  final session = _emptySession();
  return ActiveSessionScreen(
    recorder: FakeSessionRecorder(session),
    session: session,
    now: previewNow,
  );
}

Widget _runningSessionScreen() {
  final session = _openSession();
  return ActiveSessionScreen(
    recorder: FakeSessionRecorder(session),
    session: session,
    now: previewNow,
  );
}

/// Three saved workouts, one of them added from a premade.
///
/// Enough to show the list, the movement summary line and the premade
/// back-reference without being a wall of identical rows.
/// What a session did to *Wednesday push*: every set laid out and worked,
/// and Cable Fly removed.
TemplateUpdate _lesson() {
  final workout = _savedWorkouts().first;
  SessionExercise worked(String name, int sets) => SessionExercise(
    id: name,
    name: name,
    orderIndex: 0,
    sets: <SessionSet>[
      for (var i = 0; i < sets; i++)
        SessionSet(
          id: '$name-$i',
          setNumber: i + 1,
          reps: 5,
          isCompleted: true,
        ),
    ],
  );
  return TemplateUpdate.between(
    workout.movements,
    Session(
      id: 'lesson',
      name: workout.name,
      startedAt: previewNow.subtract(const Duration(hours: 1)),
      exercises: <SessionExercise>[
        worked('Barbell Bench Press', 4),
        worked('Dumbbell Shoulder Press', 3),
        worked('Cable Tricep Pushdown', 3),
      ],
    ),
  );
}

List<SavedWorkout> _savedWorkouts() => <SavedWorkout>[
  SavedWorkout(
    id: 'w1',
    name: 'Wednesday push',
    movements: const <TemplateMovement>[
      TemplateMovement('Barbell Bench Press', sets: 4, repTarget: 5),
      TemplateMovement('Dumbbell Shoulder Press', repTarget: 10),
      TemplateMovement('Cable Fly', repTarget: 12),
      TemplateMovement('Cable Tricep Pushdown'),
    ],
    savedAt: previewNow.subtract(const Duration(days: 2)),
  ),
  SavedWorkout(
    id: 'w2',
    name: 'Pull',
    movements: const <TemplateMovement>[
      TemplateMovement('Barbell Bent Over Row', repTarget: 8),
      TemplateMovement('Lat Pulldown', repTarget: 10),
      TemplateMovement('Dumbbell Bicep Curl'),
    ],
    savedAt: previewNow.subtract(const Duration(days: 9)),
    premadeId: 'pull',
  ),
  SavedWorkout(
    id: 'w3',
    name: 'Legs, short',
    movements: const <TemplateMovement>[
      TemplateMovement('Barbell Squat', sets: 5, repTarget: 5),
      TemplateMovement('Leg Press', repTarget: 10),
      TemplateMovement('Standing Calf Raise', sets: 4, repTarget: 15),
    ],
    savedAt: previewNow.subtract(const Duration(days: 16)),
  ),
];

/// A fixed backup status for a plate. Never changes — which is the point of a
/// plate.
ValueListenable<BackupStatus> _backup({
  BackupState state = BackupState.idle,
  SyncPending pending = const SyncPending(workouts: 0, lastSyncedAt: null),
}) => ValueNotifier<BackupStatus>(BackupStatus(state: state, pending: pending));
