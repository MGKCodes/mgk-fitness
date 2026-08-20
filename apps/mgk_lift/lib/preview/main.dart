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
import '../src/features/coaching/presentation/coach_memory_screen.dart';
import '../src/features/coaching/presentation/coach_sheet.dart';
import '../src/features/coaching/presentation/plan_surface.dart';
import '../src/features/planning/domain/plan.dart';
import '../src/features/planning/domain/plan_validator.dart';
import '../src/features/planning/presentation/adapt_sheet.dart';
import '../src/features/planning/presentation/plan_intake_screen.dart';
import '../src/features/planning/presentation/plan_review_screen.dart';
import '../src/features/planning/presentation/swap_sheet.dart';
import '../src/features/home/presentation/lift_shell.dart';
import '../src/features/photos/data/in_memory_photo_library.dart';
import '../src/features/photos/domain/progress_photo.dart';
import '../src/features/photos/presentation/photos_surface.dart';
import '../src/features/photos/presentation/pose_series_screen.dart';
import '../src/features/settings/domain/unit_preferences.dart';
import '../src/features/settings/presentation/credits_screen.dart';
import '../src/features/settings/presentation/settings_screen.dart';
import '../src/features/sync/domain/sync_status.dart';
import '../src/features/tracking/domain/session.dart';
import '../src/features/tracking/presentation/track_surface.dart';
import '../src/features/tracking/presentation/active_session_screen.dart';
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
///       --dart-define=screen=plan-intake
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

/// Repeated across the onboarding fixtures so each step carries the turns
/// before it rather than starting mid-conversation.
const String _onboardingOpener =
    'Before I build you anything I need four things. Spin rather than type, '
    'skip anything you would rather not say, and Settings shows you the lot '
    'afterwards.';

class PreviewApp extends StatelessWidget {
  const PreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    final screens = <String, WidgetBuilder>{
      'track': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
      ),
      'track-open': (_) => LiftShell(
        recorder: FakeSessionRecorder(_openSession()),
        history: FakeHistory(sampleLog(previewNow)),
      ),
      'plan': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
        initialTab: 1,
      ),
      'plan-entitled': (_) =>
          const Scaffold(body: PlanSurface(isEntitled: true)),
      // Item 5: what Track shows when a plan has something for today, and
      // when somebody walked away mid-session.
      'track-planned': (_) => Scaffold(
        body: TrackSurface(
          plan: samplePlan(previewNow),
          today: previewNow,
          log: sampleLog(previewNow),
          onStartPlanned: (_) {},
        ),
      ),
      'track-interrupted': (_) => Scaffold(
        body: TrackSurface(
          today: previewNow,
          log: sampleLog(previewNow),
          openSession: Session(
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
          onStartSession: () {},
        ),
      ),
      // A live block, mid-week, with today's session on it.
      'plan-active': (_) => Scaffold(
        body: PlanSurface(
          isEntitled: true,
          plan: samplePlan(previewNow),
          today: previewNow,
          onOpenSession: (_) {},
          // Passed so the adapt entry point is actually on screen. Without it
          // the preview silently reviewed a surface with one of its two
          // actions missing, which is how it went unlooked-at this long.
          onAdapt: () {},
        ),
      ),
      // The three the harness could not reach, which is why nobody had
      // looked at them. A sheet needs something behind it, so these sit on a
      // plain scaffold and open themselves.
      'plan-intake': (_) => PlanIntakeScreen(
        planner: FakePlanner(),
        opener:
            'What are you training for, and which days can you get to the '
            'gym?',
      ),
      'swap-sheet': (_) => _SheetHost(
        open: (context) => SwapSheet.show(
          context,
          planner: FakePlanner(),
          session: _openSession(),
          movement: 'Barbell Bench Press',
          log: sampleLog(previewNow),
        ),
      ),
      'adapt-sheet': (_) => _SheetHost(
        open: (context) => AdaptSheet.show(
          context,
          planner: FakePlanner(),
          plan: samplePlan(previewNow),
          weekNumber: 1,
        ),
      ),
      'plan-review': (_) => PlanReviewScreen(
        plan: samplePlan(previewNow),
        unit: MassUnit.kilograms,
        onAccept: () {},
      ),
      // The honest first-plan state: a lifter with almost no history, so
      // almost nothing carries a number.
      'plan-review-no-targets': (_) => PlanReviewScreen(
        plan: samplePlan(previewNow, targeted: false),
        unit: MassUnit.kilograms,
        onAccept: () {},
      ),
      'profile': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
        initialTab: 2,
      ),
      'profile-empty': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: const FakeHistory(<Session>[]),
        initialTab: 2,
      ),
      // Every session screen pins `now` to previewNow. The fixtures start at
      // previewNow too, so the header reads the elapsed time the fixture meant
      // — 34 minutes, not the days since previewNow went past.
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
      'photos': (_) => const _PhotosPreview(),
      'photo-series': (_) => const _PhotosPreview(openSeries: true),
      'photos-empty': (_) => PhotosSurface(
        library: InMemoryPhotoLibrary(),
        source: FakePhotoSource(null),
        now: previewNow,
      ),
      'settings': (_) => SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
      ),
      // The two states that matter: signed out with training that exists in
      // one place, and signed in with everything up to date.
      'settings-signed-in': (_) => SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        isSignedIn: true,
        email: 'matt@example.com',
        pending: const SyncPending(workouts: 0, lastSyncedAt: null),
        onSignOut: () {},
        onSyncNow: () {},
        coachMemory: FakeCoachMemory(),
      ),
      'backup-signed-out': (_) => SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        pending: const SyncPending(workouts: 9, lastSyncedAt: null),
        onSignIn: () {},
      ),
      'backup-synced': (_) => SettingsScreen(
        initial: const UnitPreferences(),
        store: InMemoryUnitPreferences(),
        isSignedIn: true,
        pending: SyncPending(
          workouts: 0,
          lastSyncedAt: previewNow.subtract(const Duration(minutes: 3)),
        ),
        onSyncNow: () {},
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

      // ---- The coach's onboarding -------------------------------------------
      //
      // Conversational rather than a form, because a coach that opens with a
      // questionnaire is a form wearing a coach's voice. On the PLAN path, not
      // app install: a tracking-only lifter is never asked, because nothing
      // they use consumes any of this. See docs/coach-profile.md.
      //
      // **Nothing is repeated back as it is given.** Echoing each answer turned
      // a four-question conversation into eight turns, half of them the coach
      // telling you what you had just said. The confirmation happens once, at
      // the end, where it is a thing to accept rather than a tic.
      'coach-onboarding': (_) => _sheet(
        _talk(<List<Object>>[
          [
            true,
            'Before I build you anything I need four things. Spin rather than '
                'type, skip anything you would rather not say, and Settings '
                'shows you the lot afterwards.',
          ],
          [true, 'When were you born?', CoachAsk.yearOfBirth],
        ]),
      ),
      // Height BEFORE weight, and asked separately. Together they read as a
      // medical form; apart, height is the harmless one and answering it makes
      // the next question ordinary rather than the first thing asked.
      //
      // **Cumulative, like the real conversation.** These fixtures used to hold
      // only the turns nearest the question, which made the board look as
      // though the history vanished at each step. Nothing removes a turn -- the
      // list only ever grows -- and a preview that implied otherwise was
      // inventing a bug to review.
      'coach-onboarding-height': (_) => _sheet(
        _talk(<List<Object>>[
          [true, _onboardingOpener],
          [true, 'When were you born?'],
          [false, '1994'],
          [true, 'How tall are you?', CoachAsk.heightCm],
        ]),
      ),
      'coach-onboarding-weight': (_) => _sheet(
        _talk(<List<Object>>[
          [true, _onboardingOpener],
          [true, 'When were you born?'],
          [false, '1994'],
          [true, 'How tall are you?'],
          [false, '180 cm'],
          [
            true,
            'And roughly what do you weigh? I will track it from here, so this '
                'is a starting point rather than a number to get right.',
            CoachAsk.weightKg,
          ],
        ]),
      ),
      // The five goals, stacked rather than wrapped. They conflict on purpose:
      // picking one is what makes it the PRIMARY goal rather than a wish list.
      'coach-onboarding-goal': (_) => _sheet(
        _talk(<List<Object>>[
          [true, 'When were you born?'],
          [false, '1994'],
          [true, 'How tall are you?'],
          [false, '180 cm'],
          [true, 'And roughly what do you weigh?'],
          [false, '82 kg'],
          [
            true,
            'Last one. What are you actually training for? I will build around '
                'whichever you pick.',
            <String>[
              'Get stronger',
              'Gain muscle',
              'Lose weight',
              'Gain weight',
              'Get healthy',
              'Prefer not to say',
            ],
          ],
        ]),
      ),
      // The one confirmation, at the end. Everything it holds, in one place,
      // with changing it as available as accepting it.
      'coach-onboarding-summary': (_) => _sheet(
        _talk(<List<Object>>[
          [true, 'How tall are you?'],
          [false, '180 cm'],
          [true, 'And roughly what do you weigh?'],
          [false, '82 kg'],
          [true, 'What are you actually training for?'],
          [false, 'Get stronger'],
          [
            true,
            'Here is what I have. Born 1994, 180 cm, 82 kg today, '
                'training to get stronger.',
            <String>['That is right', 'Change something', 'Start over'],
          ],
        ]),
      ),
      // A declined answer, carried rather than nagged. "Prefer not to say" is
      // an answer -- a coach that asks again has not accepted one.
      'coach-onboarding-declined': (_) => _sheet(
        _talk(<List<Object>>[
          [true, 'How tall are you?'],
          [false, '180 cm'],
          [true, 'And roughly what do you weigh?'],
          [false, 'Prefer not to say'],
          [
            true,
            'Fine — I will work from what you lift instead, which is the better '
                'signal anyway. Last one.',
            <String>['Get stronger', 'Gain muscle', 'Lose weight'],
          ],
        ]),
      ),
      // Runio meeting a profile Liftio filled in. It ASKS rather than assuming:
      // an app volunteering your weight when you never told that app your
      // weight reads as surveillance, even on the same account.
      'coach-profile-detected': (_) => _sheet(
        _talk(<List<Object>>[
          [
            true,
            'I found your MGK Fitness profile — born 1994, 180 cm, 82 kg. That '
                'came from Liftio, not from anything you told me.',
          ],
          [
            true,
            'Still right? Running goals are separate, so I will ask about those '
                'either way.',
            <String>['That is right', 'Update it', 'Do not use it'],
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
      ),
      'coach-memory-empty': (_) => CoachMemoryScreen(store: FakeCoachMemory()),
      'coach-memory-error': (_) => CoachMemoryScreen(
        store: FakeCoachMemory(failWith: CoachMemoryFailure.unavailable),
      ),
      'coach-limit': (_) => _sheetOf(
        coach: FakeCoach(failWith: CoachFailure.limitReached),
        opener: 'Ask me anything about this week.',
      ),
      'sign-in': (_) => SignInScreen(auth: FakeAuth(), pendingWorkouts: 9),
      'sign-in-error': (_) =>
          SignInScreen(auth: FakeAuth(failWith: AuthFailure.wrongCredentials)),
      'credits': (_) => const CreditsScreen(),
      'coach-mark': (_) => LiftShell(
        recorder: FakeSessionRecorder(),
        history: FakeHistory(sampleLog(previewNow)),
        coach: FakeCoach(),
        hasCoachNote: true,
      ),
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

/// The coach as it is actually presented: a sheet, over a photograph, in glass.
///
/// Every coach preview goes through this rather than rendering CoachScreen
/// bare. The screen paints nothing of its own — the backdrop and the glass are
/// CoachSheet's — so a preview that skipped it reviewed the coach on a flat
/// charcoal panel, which is the one surface GlassSurface says the effect does
/// not work on.
Widget _sheet(CoachTranscript? transcript, {String? opener}) =>
    _sheetOf(coach: FakeCoach(), transcript: transcript, opener: opener);

/// The same, for a preview that needs a particular coach — one that refuses,
/// or one that fails.
Widget _sheetOf({
  required CoachService coach,
  CoachTranscript? transcript,
  String? opener,
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
          ),
        ),
      ),
    ],
  ),
);

/// Builds a transcript from `[fromCoach, body, suggestions? | CoachAsk?]` rows.
///
/// The screens above are conversations, and written out as CoachTurn literals
/// they were nine lines of ceremony per sentence — which made the copy itself,
/// the thing actually under review, the hardest part to read.
FakeCoachTranscript _talk(List<List<Object>> rows) {
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

/// A push day most of the way through: three movements done, one in progress,
/// two not started.
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
class _PhotosPreview extends StatefulWidget {
  const _PhotosPreview({this.openSeries = false});

  /// Opens straight into one pose's grid, which is the screen with the missed
  /// weeks in it and the harder layout to get right.
  final bool openSeries;

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
    if (!widget.openSeries) {
      return PhotosSurface(
        library: library,
        source: FakePhotoSource(null),
        now: previewNow,
      );
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
        return PoseSeriesScreen(
          series: PoseSeries(
            pose: Pose.front,
            photos: all.where((p) => p.pose == Pose.front).toList(),
          ),
          thisWeek: week,
          library: library,
        );
      },
    );
  }
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
          id: '\${pose.stored}-\$w',
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

/// A block for the previews: two weeks written, the rest still to come.
Plan samplePlan(DateTime now, {bool targeted = true}) {
  final start = now.subtract(Duration(days: now.weekday - 1));
  PlannedMovement m(String name, int sets, int reps, double? kg) =>
      PlannedMovement(
        name: name,
        sets: sets,
        reps: reps,
        target: targeted && kg != null ? Mass.kilograms(kg) : null,
      );

  return Plan(
    id: 'preview',
    startDate: start,
    weeks: 8,
    status: PlanStatus.active,
    goal: 'Get my bench past 100 by Christmas',
    profile: const PlanProfile(daysPerWeek: 2, availableWeekdays: <int>[1, 4]),
    arc: <PlanWeek>[
      for (var i = 1; i <= 8; i++)
        PlanWeek(
          number: i,
          phase: i % 4 == 0 ? PlanPhase.deload : PlanPhase.build,
          intent: i % 4 == 0
              ? 'Back off. Keep the movements, drop the load.'
              : 'Add a little to the top set and keep the volume steady.',
        ),
    ],
    sessions: <PlanSession>[
      for (var week = 1; week <= 2; week++) ...<PlanSession>[
        PlanSession(
          id: 'preview-w$week-d1',
          weekNumber: week,
          weekday: 1,
          scheduledDate: start.add(Duration(days: (week - 1) * 7)),
          kind: 'push',
          rationale:
              'Your bench has not moved in three weeks, so the top set goes '
              'up and everything else stays where it was.',
          movements: <PlannedMovement>[
            m('Barbell Bench Press', 3, 5, 85),
            m('Dumbbell Shoulder Press', 3, 8, 27.5),
            m('Cable Tricep Pushdown', 3, 12, null),
          ],
        ),
        PlanSession(
          id: 'preview-w$week-d4',
          weekNumber: week,
          weekday: 4,
          scheduledDate: start.add(Duration(days: (week - 1) * 7 + 3)),
          kind: 'pull',
          rationale: 'Your back is behind your chest, so it gets the volume.',
          movements: <PlannedMovement>[
            m('Barbell Deadlift', 3, 5, 140),
            m('Barbell Row', 3, 8, 70),
            m('Cable Bicep Curl', 3, 12, null),
          ],
        ),
      ],
    ],
  );
}

/// Opens a sheet as soon as it is shown, so a modal is reviewable in a harness
/// that addresses screens by name rather than by tapping.
class _SheetHost extends StatefulWidget {
  const _SheetHost({required this.open});

  final Future<void> Function(BuildContext context) open;

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
      const Scaffold(backgroundColor: AppColors.bg, body: SizedBox.expand());
}
