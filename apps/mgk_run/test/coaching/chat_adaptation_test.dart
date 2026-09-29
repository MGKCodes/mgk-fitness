import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_client.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/data/plan_store.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/chat_widgets.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_button.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/coaching/domain/ai_consent.dart';
import 'package:mgk_run/src/features/legal/domain/disclaimer_store.dart';

/// A coach that always wants to change the week, and remembers the brief it was
/// given. Standing in for the model, so the test is about what the app does
/// with an intent rather than about whether a model produces one.
class _AdaptingChat implements CoachChatClient {
  final List<String> briefs = <String>[];

  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async {
    briefs.add(brief);
    return ChatTurn(
      reply: "Let's not push through that — here's what I'd change.",
      intent: CoachIntent(kind: CoachIntent.adaptWeek, request: message),
    );
  }
}

/// Records what it was asked to adapt, and answers with [revision].
///
/// [validRevision] takes a kilometre off a session still to come: a change the
/// validator lets through. [wildRevision] is nonsense it must refuse.
///
/// Deliberately a plain [PlanClient] rather than a `WeekAwarePlanClient`. The
/// shell now hands the adaptation what has already happened this week, and a
/// client that cannot be told is the case that must keep working — every other
/// stand-in in the app is one.
class _AdaptRecorder implements PlanClient {
  _AdaptRecorder(this.revision);

  final TrainingWeek? Function(TrainingWeek week) revision;
  final List<String> requests = <String>[];

  @override
  Future<TrainingWeek?> proposeAdaptation({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
  }) async {
    requests.add(request);
    return revision(week);
  }

  @override
  Future<PlanSkeleton?> proposeSkeleton({
    required RunnerProfile profile,
    List<String> violations = const <String>[],
  }) async => null;

  @override
  Future<TrainingWeek?> proposeWeek({
    required SkeletonWeek slot,
    required RunnerProfile profile,
    List<String> violations = const <String>[],
    int? raceWeekday,
  }) async => null;
}

/// A revision the validator accepts: a kilometre off a session the runner has
/// **not** already run.
///
/// This used to move a kilometre between the week's two easy days, which was
/// fine while a revision could touch any day it liked. It cannot any more.
/// `_proposeFromChat` hands the adaptation what has already happened this week,
/// and `session_already_done` refuses a revision that moves or resizes a
/// session somebody went out and did — so the old fixture was proposing exactly
/// the thing the rule exists to stop. On a Friday, `someRuns()` lands on the
/// plan's Monday and Thursday, and Thursday is one of the two easy days.
///
/// Nor can it simply pick two *other* easy days. How much of the week is still
/// ahead depends on the day the test runs — five sessions on a Monday, one by
/// Sunday — so any fixture needing two free days of a particular kind is right
/// some days and broken the rest. This changes a single session instead: the
/// last one still to come, which on every weekday is the long run. A sore calf
/// is the right reason to shorten it, which is what the tests below ask for.
///
/// **Weekdays, not dates, and that is the safe comparison.** Every run
/// `someRuns()` seeds is strictly before today, so one falling inside this week
/// necessarily falls on an earlier weekday: everything from today onward is
/// unrun by construction. Going the other way — deriving weekdays from the run
/// offsets — is the trap, because a run four days ago can belong to *last*
/// week, and ruling out this week's Thursday for it would leave a Monday run of
/// the suite with nothing it is allowed to change.
TrainingWeek? validRevision(TrainingWeek week) {
  final ahead =
      week.runs.where((s) => s.weekday >= DateTime.now().weekday).toList()
        ..sort((a, b) => a.weekday.compareTo(b.weekday));
  if (ahead.isEmpty) return null;

  final last = ahead.last;
  return TrainingWeek(
    skeletonIndex: week.skeletonIndex,
    sessions: <PlannedSession>[
      for (final s in week.sessions)
        if (!identical(s, last))
          s
        else
          PlannedSession(
            weekday: s.weekday,
            kind: s.kind,
            distanceMeters: s.distanceMeters - 1000,
          ),
    ],
  );
}

/// A week no validator should accept: one enormous session, nothing else.
TrainingWeek? wildRevision(TrainingWeek week) => TrainingWeek(
  skeletonIndex: week.skeletonIndex,
  sessions: <PlannedSession>[
    const PlannedSession(
      weekday: 1,
      kind: SessionKind.long,
      distanceMeters: 300000,
    ),
  ],
);

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  RunnerProfile aProfile() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime.now().add(const Duration(days: 112)),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  /// Two runs, yesterday and four days ago. The brief test reads "yesterday"
  /// off the first, so these dates are load-bearing — see [ranWeekdays].
  List<RunSummary> someRuns() => <RunSummary>[
    RunSummary(
      startedAt: DateTime.now().subtract(const Duration(days: 1)),
      duration: const Duration(minutes: 32),
      distanceMeters: 6000,
      avgPaceSecondsPerKm: 320,
    ),
    RunSummary(
      startedAt: DateTime.now().subtract(const Duration(days: 4)),
      duration: const Duration(minutes: 55),
      distanceMeters: 10000,
      avgPaceSecondsPerKm: 330,
    ),
  ];

  /// Mounts the app on the Coach tab over a seeded plan, and asks the coach for
  /// a change the way a runner would: by typing it.
  Future<(_AdaptingChat, _AdaptRecorder, PlanStore, StoredPlan)> ask(
    WidgetTester tester,
    String message, {
    required TrainingWeek? Function(TrainingWeek) revision,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = DriftPlanStore(db);
    final plan = await PlanRepository(store: store).create(aProfile());
    final chat = _AdaptingChat();
    final planClient = _AdaptRecorder(revision);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          // Already agreed, and the disclaimer already read: what the coach
          // asks before it sends anything is pinned in
          // the_coach_asks_before_anything_leaves_test.dart.
          aiConsent: InMemoryAiConsentStore.granted(),
          disclaimer: InMemoryDisclaimerStore(acknowledged: true),
          // The coach is the paid half now (ADR-0030), so a test that
          // opens it has to say it bought one. Pinned rather than read:
          // these are tests about conversations, and where a tier comes
          // from belongs to entitlement_repository_test.dart.
          access: CoachAccess.subscribed,
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
          historySource: () async => someRuns(),
          chatClient: chat,
          planClient: planClient,
          planStore: store,
          initialTab: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The coach is a floating mark now, so the conversation has to be opened
    // before there is anything to type into — which is the real flow, not a
    // detour around it.
    await tester.tap(find.byType(CoachButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), message);
    await tester.tap(find.byIcon(Icons.arrow_upward).last);
    await tester.pumpAndSettle();

    return (chat, planClient, store, plan);
  }

  // The load-bearing one. A change asked for in conversation must travel the
  // same road as one typed into the adjust sheet: propose → validate → diff →
  // approve. The chat hands over a sentence; it never writes a plan.
  testWidgets('a change asked for in chat goes through the adaptation path', (
    tester,
  ) async {
    final (_, planClient, store, plan) = await ask(
      tester,
      'my calf is sore, can we move today’s run',
      revision: validRevision,
    );

    expect(
      planClient.requests,
      <String>['my calf is sore, can we move today’s run'],
      reason: 'the runner’s own words reached the adaptation service',
    );

    // The diff is on screen — inside the conversation, not in a sheet thrown
    // over it — and nothing has been written yet.
    expect(find.byType(ProposalCard), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
    final before = await store.loadWeek(plan, 1);
    expect(
      before!.sessions.map((s) => s.distanceMeters).toList(),
      (await PlanRepository(store: DriftPlanStore(db)).weekFor(
        plan,
        plan.skeleton.weeks[0],
      )).sessions.map((s) => s.distanceMeters).toList(),
    );

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final after = await store.loadWeek(plan, 1);
    expect(
      after!.sessions.map((s) => s.distanceMeters).toList(),
      isNot(before.sessions.map((s) => s.distanceMeters).toList()),
      reason: 'approving is what writes the week, not the model saying so',
    );
    // The decision is recorded in the transcript rather than announced and
    // lost: next week, when they wonder why the week changed, it is still here.
    expect(find.text('Applied — your week is updated'), findsOneWidget);
    expect(find.text('Apply'), findsNothing);
  });

  // The validator is the gate, not the chat. A proposal it rejects must leave
  // the runner's week exactly as it was, with a reason rather than a silence.
  testWidgets('a revision the validator refuses never reaches the plan', (
    tester,
  ) async {
    final (_, _, store, plan) = await ask(
      tester,
      'give me a 300 km week',
      revision: wildRevision,
    );

    // Said plainly in the conversation, and said *specifically*. The coach
    // offered a change; the runner is entitled to know not just that it did
    // not survive the validator but which of their own constraints it hit —
    // "try telling me what you want differently" is advice that cannot work
    // when the wording was never the problem.
    expect(
      find.textContaining("I couldn't work that change out"),
      findsNothing,
      reason: 'the generic line is for a model that returned nothing at all',
    );
    expect(find.textContaining('long run'), findsOneWidget);
    expect(find.byType(ProposalCard), findsNothing);
    expect(find.text('Apply'), findsNothing);

    final week = await store.loadWeek(plan, 1);
    expect(
      week!.sessions.any((s) => s.distanceMeters > 100000),
      isFalse,
      reason: 'nothing the validator rejected got anywhere near disk',
    );
  });

  // CoachBrief had no caller until the chat existed. Its whole job is to hand
  // the model prose it can use, computed from stored runs and the stored plan.
  testWidgets('the coach is briefed from the plan and the run log', (
    tester,
  ) async {
    final (chat, _, _, _) = await ask(
      tester,
      'how am I doing',
      revision: validRevision,
    );

    expect(chat.briefs, hasLength(1));
    final brief = chat.briefs.single;
    expect(brief, contains('of a 42 km block'));
    expect(brief, contains('Their last run was yesterday'));
    expect(
      brief,
      contains('16 km in total'),
      reason:
          'the seven-day total counts every run, not the shell’s cached few',
    );
    expect(
      brief,
      isNot(contains('{')),
      reason: 'the brief is prose for a reader, not a struct to be quoted',
    );
  });

  // The join, not the pieces. `planHistoryLine` is tested on its own and so is
  // `loadHistory`, and neither would have caught the shell simply not passing
  // one to the other — which is the shape of every bug this feature could have.
  testWidgets('the brief carries what they trained for before', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Two plans, so the first is history by the time the second exists.
    final store = DriftPlanStore(db);
    await PlanRepository(
      store: store,
      newId: () => 'plan-old',
    ).create(aProfile());
    await PlanRepository(
      store: store,
      newId: () => 'plan-new',
    ).create(aProfile());

    final chat = _AdaptingChat();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          aiConsent: InMemoryAiConsentStore.granted(),
          disclaimer: InMemoryDisclaimerStore(acknowledged: true),
          // The coach is the paid half now (ADR-0030), so a test that
          // opens it has to say it bought one. Pinned rather than read:
          // these are tests about conversations, and where a tier comes
          // from belongs to entitlement_repository_test.dart.
          access: CoachAccess.subscribed,
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
          historySource: () async => someRuns(),
          chatClient: chat,
          planClient: _AdaptRecorder(validRevision),
          planStore: store,
          initialTab: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CoachButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'how am I doing');
    await tester.tap(find.byIcon(Icons.arrow_upward).last);
    await tester.pumpAndSettle();

    expect(chat.briefs, isNotEmpty);
    expect(
      chat.briefs.single,
      contains('one plan before this'),
      reason: 'every plan was on disk and the coach read every runner as new',
    );
  });

  // Declining leaves the week alone and says so in place, rather than removing
  // the offer as though it had never been made.
  testWidgets('a change the runner turns down is recorded, not erased', (
    tester,
  ) async {
    final (_, _, store, plan) = await ask(
      tester,
      'can we move today',
      revision: validRevision,
    );

    final before = await store.loadWeek(plan, 1);
    await tester.tap(find.text('Not this time'));
    await tester.pumpAndSettle();

    expect(find.text('Left as it was'), findsOneWidget);
    expect(find.text('Apply'), findsNothing);

    final after = await store.loadWeek(plan, 1);
    expect(
      after!.sessions.map((s) => s.distanceMeters).toList(),
      before!.sessions.map((s) => s.distanceMeters).toList(),
    );
  });
}
