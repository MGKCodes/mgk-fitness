import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/auth/data/fake_auth.dart';
import 'package:mgk_lift/src/features/auth/domain/account.dart';
import 'package:mgk_lift/src/features/coaching/data/supabase_coach.dart';
import 'package:mgk_lift/src/features/coaching/domain/ai_consent.dart';
import 'package:mgk_lift/src/features/coaching/domain/coach.dart';
import 'package:mgk_lift/src/features/coaching/domain/consent_gate.dart';
import 'package:mgk_lift/src/features/coaching/presentation/ai_consent_sheet.dart';
import 'package:mgk_lift/src/features/coaching/presentation/coach_sheet.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';
import 'package:mgk_lift/src/features/legal/domain/disclaimer_store.dart';
import 'package:mgk_lift/src/features/planning/data/supabase_coach_planner.dart';
import 'package:mgk_lift/src/features/planning/domain/coach_planner.dart';
import 'package:mgk_lift/src/features/planning/domain/intake_flow.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_intake.dart';
import 'package:mgk_lift/src/features/settings/domain/coach_preference.dart';
import 'package:mgk_lift/src/features/settings/domain/unit_preferences.dart';
import 'package:mgk_lift/src/features/settings/presentation/settings_screen.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

/// The `coach` Edge Function, as far as the clients can see it: every body it
/// was sent, and one answer.
class _Functions implements FunctionsClient {
  final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];

  /// The refusal to answer with, as the function's status and body.
  ({int status, Object? body})? refuse;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #invoke) {
      final body = invocation.namedArguments[#body] as Map<String, dynamic>;
      bodies.add(Map<String, dynamic>.of(body));
      final refusal = refuse;
      if (refusal != null) {
        return Future<FunctionResponse>.error(
          FunctionException(status: refusal.status, details: refusal.body),
        );
      }
      return Future<FunctionResponse>.value(
        FunctionResponse(
          status: 200,
          data: <String, dynamic>{
            'reply': 'Noted.',
            'extracted': <String, Object?>{},
            'options': <Object?>[],
          },
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

/// Somebody signed in, and nothing else.
class _Auth implements GoTrueClient {
  @override
  User? get currentUser => User(
    id: 'lifter-a',
    appMetadata: const <String, dynamic>{},
    userMetadata: const <String, dynamic>{},
    aud: 'authenticated',
    createdAt: '2026-10-29T08:00:00Z',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A client with nothing behind it but [functions] and a signed-in user.
/// Anything else the clients reached for would fail the test loudly.
class _Client implements SupabaseClient {
  _Client(this.functions);

  @override
  final FunctionsClient functions;

  @override
  final GoTrueClient auth = _Auth();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A coach that records what reached it.
class _Coach implements CoachService {
  final List<String> asked = <String>[];

  @override
  Future<String> ask(String message, {required String conversationId}) async {
    asked.add(message);
    return 'Noted.';
  }
}

Session _session() => Session(
  id: 's1',
  name: 'Push',
  startedAt: DateTime(2026, 10, 29, 18),
  exercises: const <SessionExercise>[],
);

/// **Lift asks before its coach sends anything** (issue #10).
///
/// Lift 2.0.0's coach switch was on until somebody turned it off, which is
/// not a yes, and lived on the phone, where the coach's server could not
/// check it. These pin the three places the question now stands: in the
/// clients, which refuse on their own; around them, where the shell asks
/// wherever a request comes from; and at the doors, where it is asked before
/// anything is typed.
void main() {
  late _Functions functions;

  setUp(() => functions = _Functions());

  final refusal = throwsA(
    isA<CoachException>().having(
      (e) => e.failure,
      'failure',
      CoachFailure.consentRequired,
    ),
  );
  final planRefusal = throwsA(
    isA<PlanException>().having(
      (e) => e.failure,
      'failure',
      PlanFailure.consentRequired,
    ),
  );

  group('the clients refuse on their own', () {
    test('a message, with no yes, is never sent', () async {
      final coach = SupabaseCoach(
        _Client(functions),
        consent: InMemoryAiConsentStore(),
      );

      await expectLater(coach.ask('Hi', conversationId: 'c1'), refusal);
      expect(functions.bodies, isEmpty);
    });

    test('nor the intake, a week, or a swap', () async {
      final planner = SupabaseCoachPlanner(
        _Client(functions),
        consent: InMemoryAiConsentStore(),
      );

      await expectLater(
        planner.intake(
          progress: const IntakeProgress(),
          history: const <PlannerTurn>[],
        ),
        planRefusal,
      );
      await expectLater(
        planner.plan(
          intake: const PlanIntake(),
          weekdays: const <int>[1, 3, 5],
          catalogue: const <String>['Bench press'],
        ),
        planRefusal,
      );
      await expectLater(
        planner.swap(message: 'No bench free', session: _session()),
        planRefusal,
      );
      expect(functions.bodies, isEmpty);
    });

    test('with a yes, the message goes', () async {
      final coach = SupabaseCoach(
        _Client(functions),
        consent: InMemoryAiConsentStore.granted(),
      );

      expect(await coach.ask('Hi', conversationId: 'c1'), 'Noted.');
      expect(functions.bodies, hasLength(1));
    });

    test('a store that cannot answer is a no', () async {
      final coach = SupabaseCoach(_Client(functions), consent: _Unanswerable());

      await expectLater(coach.ask('Hi', conversationId: 'c1'), refusal);
      expect(functions.bodies, isEmpty);
    });
  });

  group('when the server finds no yes on the account', () {
    test(
      'the coach says so, and the phone stops believing it had one',
      () async {
        final consent = InMemoryAiConsentStore.granted();
        final coach = SupabaseCoach(_Client(functions), consent: consent);
        functions.refuse = (
          status: 403,
          body: <String, dynamic>{'error': 'consent_required'},
        );

        await expectLater(coach.ask('Hi', conversationId: 'c1'), refusal);
        expect(
          await consent.isGranted(),
          isFalse,
          reason:
              'so the next request asks rather than meeting the same refusal',
        );
      },
    );

    test('and the planner too', () async {
      final consent = InMemoryAiConsentStore.granted();
      final planner = SupabaseCoachPlanner(
        _Client(functions),
        consent: consent,
      );
      functions.refuse = (
        status: 403,
        body: <String, dynamic>{'error': 'consent_required'},
      );

      await expectLater(
        planner.swap(message: 'No bench free', session: _session()),
        planRefusal,
      );
      expect(await consent.isGranted(), isFalse);
    });

    test('a 403 that says anything else is still the server\'s', () async {
      final consent = InMemoryAiConsentStore.granted();
      final coach = SupabaseCoach(_Client(functions), consent: consent);
      functions.refuse = (status: 403, body: null);

      await expectLater(
        coach.ask('Hi', conversationId: 'c1'),
        throwsA(
          isA<CoachException>().having(
            (e) => e.failure,
            'failure',
            CoachFailure.serverError,
          ),
        ),
      );
      expect(await consent.isGranted(), isTrue);
    });
  });

  group('the shell asks wherever a request comes from', () {
    test('no from the question is no request', () async {
      final inner = _Coach();
      final coach = ConsentGatedCoach(inner, askFirst: () async => false);

      await expectLater(coach.ask('Hi', conversationId: 'c1'), refusal);
      expect(inner.asked, isEmpty);
    });

    test('yes lets it through', () async {
      final inner = _Coach();
      final coach = ConsentGatedCoach(inner, askFirst: () async => true);

      expect(await coach.ask('Hi', conversationId: 'c1'), 'Noted.');
      expect(inner.asked, <String>['Hi']);
    });

    test('a swap mid-session asks too', () async {
      var asked = 0;
      final planner = ConsentGatedPlanner(
        SupabaseCoachPlanner(
          _Client(functions),
          consent: InMemoryAiConsentStore(),
        ),
        askFirst: () async {
          asked++;
          return false;
        },
      );

      await expectLater(
        planner.swap(message: 'No bench free', session: _session()),
        planRefusal,
      );
      expect(asked, 1);
      expect(functions.bodies, isEmpty);
    });
  });

  group('the coach mark', () {
    Future<void> pumpShell(
      WidgetTester tester, {
      required AiConsentStore consent,
      Account? account = const Account(id: 'u', email: 'a@b.com'),
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LiftShell(
            coach: FakeCoach(),
            auth: FakeAuth(account: account),
            isEntitled: true,
            disclaimers: InMemoryDisclaimerStore(acknowledged: true),
            aiConsent: consent,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tapTheMark(WidgetTester tester) async {
      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();
    }

    testWidgets('asks before the coach opens', (tester) async {
      final consent = InMemoryAiConsentStore();
      await pumpShell(tester, consent: consent);

      await tapTheMark(tester);
      expect(find.byType(AiConsentSheet), findsOneWidget);
      expect(find.byType(CoachSheet), findsNothing);

      await tester.tap(find.text(AiConsentSheet.agreeLabel));
      await tester.pumpAndSettle();
      expect(find.byType(CoachSheet), findsOneWidget);
      expect(consent.grants, 1);
    });

    testWidgets('Not now opens nothing, records nothing, and asks again', (
      tester,
    ) async {
      final consent = InMemoryAiConsentStore();
      await pumpShell(tester, consent: consent);

      await tapTheMark(tester);
      await tester.tap(find.text(AiConsentSheet.notNowLabel));
      await tester.pumpAndSettle();
      expect(find.byType(CoachSheet), findsNothing);
      expect(consent.grants, 0);

      await tapTheMark(tester);
      expect(find.byType(AiConsentSheet), findsOneWidget);
    });

    testWidgets('once agreed, it is not asked again', (tester) async {
      await pumpShell(tester, consent: InMemoryAiConsentStore.granted());

      await tapTheMark(tester);
      expect(find.byType(AiConsentSheet), findsNothing);
      expect(find.byType(CoachSheet), findsOneWidget);
    });

    testWidgets('signed out, there is no account to keep an answer on', (
      tester,
    ) async {
      final consent = InMemoryAiConsentStore();
      await pumpShell(tester, consent: consent, account: null);
      // The launch reads it once, for Settings to say where things stand.
      final before = consent.reads;

      await tapTheMark(tester);
      expect(find.byType(AiConsentSheet), findsNothing);
      expect(consent.reads, before, reason: 'the mark did not ask at all');
    });
  });

  group('the switch in Settings', () {
    testWidgets('on with no yes yet says the coach will ask', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            initial: const UnitPreferences(),
            store: InMemoryUnitPreferences(),
            useCoach: true,
            coachConsented: false,
            onUseCoachChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('On. Your coach asks before anything is sent.'),
        findsOneWidget,
      );
    });

    testWidgets('off takes the yes back', (tester) async {
      tester.view.physicalSize = const Size(1080, 4200);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final consent = InMemoryAiConsentStore.granted();
      await tester.pumpWidget(
        MaterialApp(
          home: LiftShell(
            coach: FakeCoach(),
            auth: FakeAuth(
              account: const Account(id: 'u', email: 'a@b.com'),
            ),
            coachPreference: InMemoryCoachPreference(),
            aiConsent: consent,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(consent.withdrawals, 1);
      expect(await consent.isGranted(), isFalse);
    });
  });
}

/// A store that cannot say, as a broken file or a missing plugin would.
class _Unanswerable implements AiConsentStore {
  @override
  Future<bool> isGranted() async => throw StateError('unreadable');

  @override
  Future<void> grant() async {}

  @override
  Future<void> withdraw() async {}

  @override
  Future<void> refusedByAccount() async {}
}
