import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/data/plan_client.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/adjust_reasons_sheet.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';

/// Records every message put to the coach. The reasons are pre-written
/// sentences, so what matters is that they arrive in the *conversation* — the
/// same place a typed one lands, and the place the transcript keeps.
class _RecordingChat implements CoachChatClient {
  final List<String> asked = <String>[];

  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async {
    asked.add(message);
    return const ChatTurn(reply: 'Noted.');
  }
}

/// Records what it was asked for and answers with [revision] — standing in for
/// the model, so these tests are about the road a request travels rather than
/// about what a model says.
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
  }) async => null;
}

/// Moves a kilometre between two easy days: the week still adds up, so the
/// validator lets it through.
TrainingWeek? validRevision(TrainingWeek week) {
  final sessions = week.sessions.toList();
  final easy = <int>[
    for (var i = 0; i < sessions.length; i++)
      if (sessions[i].kind == SessionKind.easy) i,
  ];
  if (easy.length < 2) return null;
  sessions[easy[0]] = PlannedSession(
    weekday: sessions[easy[0]].weekday,
    kind: SessionKind.easy,
    distanceMeters: sessions[easy[0]].distanceMeters - 1000,
  );
  sessions[easy[1]] = PlannedSession(
    weekday: sessions[easy[1]].weekday,
    kind: SessionKind.easy,
    distanceMeters: sessions[easy[1]].distanceMeters + 1000,
  );
  return TrainingWeek(skeletonIndex: week.skeletonIndex, sessions: sessions);
}

/// The category's loudest complaint is a plan that will not bend. Runio could
/// always bend one — but only for a runner willing to type a paragraph at the
/// coach. These cover the door onto that engine: it is on Home, it is one tap,
/// and it changes nothing without the runner's word.
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
  );

  final adjust = find.text('Not feeling it? Adjust this week');

  Future<_RecordingChat> pumpHome(
    WidgetTester tester, {
    bool withPlan = true,
    TrainingWeek? Function(TrainingWeek)? revision,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = DriftPlanStore(db);
    if (withPlan) await PlanRepository(store: store).create(aProfile());
    final chat = _RecordingChat();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
          historySource: () async => const [],
          chatClient: chat,
          planClient: _AdaptRecorder(revision ?? validRevision),
          planStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return chat;
  }

  testWidgets('Home offers a way to bend the week when there is a plan', (
    tester,
  ) async {
    await pumpHome(tester);
    expect(adjust, findsOneWidget);
  });

  testWidgets('and offers nothing to bend when there is no plan', (
    tester,
  ) async {
    await pumpHome(tester, withPlan: false);
    expect(
      adjust,
      findsNothing,
      reason: 'a runner with no plan has no week to adjust',
    );
  });

  testWidgets('the reasons are situations, not a text box', (tester) async {
    await pumpHome(tester);

    await tester.tap(adjust);
    await tester.pumpAndSettle();

    for (final reason in AdjustReasonsSheet.reasons) {
      expect(find.text(reason.label), findsOneWidget);
    }
    // The promise that makes it safe to tap one.
    expect(find.textContaining('Nothing moves until you say yes'), findsOne);
  });

  // The load-bearing one. A tapped reason is a sentence the runner did not have
  // to type, so it belongs in the conversation — where the coach can ask a
  // follow-up, and where the transcript keeps a record of what was agreed. The
  // first version of this opened a modal instead, which is the arrangement the
  // codebase had already moved away from (ADR-0017).
  testWidgets('picking a reason puts it to the coach, in the conversation', (
    tester,
  ) async {
    final chat = await pumpHome(tester);
    final pause = AdjustReasonsSheet.reasons.firstWhere(
      (r) => r.label == 'Pause the rest of this week',
    );

    await tester.tap(adjust);
    await tester.pumpAndSettle();
    await tester.tap(find.text(pause.label));
    await tester.pumpAndSettle();

    expect(
      chat.asked,
      <String>[pause.request],
      reason: 'the pre-written sentence reached the coach as a message',
    );
    // In the conversation, not a sheet over the top of it.
    expect(find.text(pause.request), findsWidgets);
  });

  testWidgets('"Never mind" says nothing to the coach at all', (tester) async {
    final chat = await pumpHome(tester);

    await tester.tap(adjust);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Never mind'));
    await tester.pumpAndSettle();

    expect(chat.asked, isEmpty);
  });
}
