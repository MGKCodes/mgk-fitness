import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_lift/src/features/tracking/presentation/track_surface.dart';
import 'package:mgk_lift/main.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';
import 'package:mgk_lift/src/features/auth/data/fake_auth.dart';
import 'package:mgk_lift/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_lift/src/features/auth/domain/account.dart';
import 'package:mgk_lift/src/features/coaching/data/supabase_coach.dart';
import 'package:mgk_lift/src/features/coaching/presentation/coach_sheet.dart';
import 'package:mgk_lift/src/features/entitlement/domain/entitlement.dart';
import 'package:mgk_lift/src/features/purchases/domain/purchases.dart';
import 'package:mgk_lift/src/features/purchases/presentation/sales_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

void main() {
  trackContentTests();
  testWidgets('the shell opens on Track and takes its theme from mgk_ui', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MgkLiftApp());

    // SectionLabel uppercases its text — the eyebrow is a decision made once in
    // mgk_ui, not something each screen restates.
    // The Today card names the day, since the headline under it says what
    // today is for.
    expect(find.text('LIFT'), findsOneWidget);
    expect(
      find.textContaining(
        RegExp(
          r'^TODAY · (MONDAY|TUESDAY|WEDNESDAY|THURSDAY|FRIDAY|SATURDAY|SUNDAY) ',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Ready when you are'), findsOneWidget);

    // The font is the trap worth guarding: mgk_ui ships Inter as a package
    // font, so the family is `packages/mgk_ui/Inter`. Writing the bare string
    // 'Inter' resolves to nothing and falls back to the platform default —
    // wrong in a way only visible by eye, never by a crash.
    final BuildContext context = tester.element(
      find.text('Ready when you are'),
    );
    expect(
      Theme.of(context).textTheme.bodyMedium?.fontFamily,
      AppTheme.fontFamily,
    );
    expect(AppTheme.fontFamily, 'packages/mgk_ui/Inter');
  });

  testWidgets('all three surfaces are reachable from the bar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MgkLiftApp());

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    expect(find.text('Train with a coach'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    // With no log, Profile holds its figures open and says what will build
    // there, as Run's does, rather than showing blocks reading zero.
    expect(
      find.textContaining('Log your first session and your totals'),
      findsOneWidget,
    );

    await tester.tap(find.text('Track'));
    await tester.pumpAndSettle();
    expect(find.text('Ready when you are'), findsOneWidget);
  });

  testWidgets('the coach mark is absent until a coach exists', (
    WidgetTester tester,
  ) async {
    // The rule Run established: absent rather than inert. A mark that cannot
    // open anything is worse than no mark, so this is asserted rather than left
    // to reviewer memory.
    await tester.pumpWidget(const MaterialApp(home: LiftShell()));
    expect(find.byType(CoachButton), findsNothing);

    await tester.pumpWidget(MaterialApp(home: LiftShell(coach: FakeCoach())));
    await tester.pumpAndSettle();
    expect(find.byType(CoachButton), findsOneWidget);
  });

  testWidgets('the bar floats and shares its component with Run', (
    WidgetTester tester,
  ) async {
    // Both apps hand-wrote the same `NavigationBar` until 2026-09-08 and
    // neither knew the other had drifted; `mgk_ui` carried no navigation
    // widget at all. It floats now (ADR-0033), so it no longer reserves its
    // own height and the shell reserves for it instead — which is why the
    // Scaffold slot being empty is worth asserting rather than assuming.
    await tester.pumpWidget(const MaterialApp(home: LiftShell()));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingNavBar), findsOneWidget);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).bottomNavigationBar,
      isNull,
    );
    // Lift's first tab is Track, not Home. The component takes destinations as
    // data precisely so this stays true of one app and not the other.
    expect(find.text('Track'), findsOneWidget);
  });

  testWidgets('and the coach mark clears it rather than sitting on it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: LiftShell(coach: FakeCoach())));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byType(CoachButton)).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(FloatingNavBar)).top),
    );
  });

  testWidgets('the coach mark does not compete with the screen\'s own action', (
    WidgetTester tester,
  ) async {
    // Found by screenshotting Track: full-width, the mark sat directly under
    // "Start a session" as a second pill of the same size and weight, and the
    // eye could not tell which one was the point of the screen. The coach is
    // permanently available; it is not what you came here to do.
    //
    // Now the shared mark from mgk_ui — a 44px rounded square, which cannot
    // compete on width — so the assertion is a quarter rather than a half, and
    // it is the letter dropping the label that is really being pinned here.
    await tester.pumpWidget(MaterialApp(home: LiftShell(coach: FakeCoach())));
    await tester.pumpAndSettle();

    final markWidth = tester.getSize(find.byType(CoachButton)).width;
    final screenWidth = tester.getSize(find.byType(LiftShell)).width;
    expect(markWidth, lessThan(screenWidth / 4));
  });

  testWidgets('the coach mark floats over every surface, not just one', (
    WidgetTester tester,
  ) async {
    // This is the whole point of a mark rather than a dock (Run's ADR-0017):
    // a dock can only live on one screen, so the coach would be present on a
    // third of the app and absent from the rest.
    await tester.pumpWidget(MaterialApp(home: LiftShell(coach: FakeCoach())));
    await tester.pumpAndSettle();

    for (final String tab in <String>['Plan', 'Profile', 'Track']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(
        find.byType(CoachButton),
        findsOneWidget,
        reason: 'the coach mark vanished on $tab',
      );
    }
  });

  testWidgets('the mark opens the coach when the account can use it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LiftShell(
          coach: FakeCoach(),
          auth: FakeAuth(
            account: const Account(id: 'u', email: 'a@b.com'),
          ),
          isEntitled: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CoachButton));
    await tester.pumpAndSettle();
    expect(find.byType(CoachSheet), findsOneWidget);
  });

  testWidgets('signed out, the mark asks for an account before a message', (
    WidgetTester tester,
  ) async {
    // Sending first and being refused afterwards means the lifter typed
    // something for nothing, and the refusal lands on a screen with no route
    // to the thing that would fix it.
    await tester.pumpWidget(
      MaterialApp(
        home: LiftShell(coach: FakeCoach(), auth: FakeAuth()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CoachButton));
    await tester.pumpAndSettle();

    expect(find.byType(CoachSheet), findsNothing);
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  for (final signedIn in <bool>[false, true]) {
    testWidgets(
      'unsubscribed and ${signedIn ? 'signed in' : 'signed out'}, the mark '
      'opens the sales screen (R6)',
      (WidgetTester tester) async {
        // Nothing on the coach is free. The mark used to send the signed-out
        // to sign in and everybody else to the Plan tab, behind whatever
        // screen they were on; one screen sells now, from every door.
        await tester.pumpWidget(
          MaterialApp(
            home: LiftShell(
              coach: FakeCoach(),
              auth: FakeAuth(
                account: signedIn
                    ? const Account(id: 'u', email: 'a@b.com')
                    : null,
              ),
              entitlements: EntitlementGate(
                source: FakeEntitlements(Entitlement.none),
              ),
              purchases: FakePurchases(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(CoachButton));
        await tester.pumpAndSettle();

        expect(find.byType(SalesScreen), findsOneWidget);
        expect(find.byType(CoachSheet), findsNothing);
        expect(find.byType(SignInScreen), findsNothing);
      },
    );
  }

  testWidgets('on the free tier the mark goes to the offer, not a refusal', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LiftShell(
          coach: FakeCoach(),
          auth: FakeAuth(
            account: const Account(id: 'u', email: 'a@b.com'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CoachButton));
    await tester.pumpAndSettle();

    expect(find.byType(CoachSheet), findsNothing);
    expect(find.text('Train with a coach'), findsOneWidget);
  });
}

/// Item 5: Track used to tell a lifter nothing they did not already know.
void trackContentTests() {
  Session finished(String name, DateTime at, {int sets = 3}) => Session(
    id: 'x$name${at.day}',
    name: name,
    startedAt: at,
    endedAt: at.add(const Duration(hours: 1)),
    exercises: <SessionExercise>[
      SessionExercise(
        id: 'e$name',
        name: 'Barbell Bench Press',
        orderIndex: 0,
        sets: <SessionSet>[
          for (var i = 0; i < sets; i++)
            SessionSet(
              id: 's$name$i',
              setNumber: i + 1,
              reps: 5,
              weightKg: 80,
              isCompleted: true,
            ),
        ],
      ),
    ],
  );

  testWidgets('an interrupted session says what it was, not just that it is', (
    WidgetTester tester,
  ) async {
    // A different button label was not enough. This is the one state where the
    // lifter has genuinely lost their place.
    final now = DateTime(2026, 8, 12, 18);
    await tester.pumpWidget(
      MaterialApp(
        home: TrackSurface(
          today: now,
          openSession: Session(
            id: 'open',
            name: 'Push',
            startedAt: now.subtract(const Duration(days: 1)),
            exercises: <SessionExercise>[
              SessionExercise(
                id: 'e',
                name: 'Barbell Bench Press',
                orderIndex: 0,
                sets: <SessionSet>[
                  SessionSet(id: 's1', setNumber: 1, isCompleted: true),
                  SessionSet(id: 's2', setNumber: 2),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The headline is the session's own name, and the line under it says
    // how far in and since when.
    expect(find.text('Push'), findsOneWidget);
    expect(find.textContaining('1 set in'), findsOneWidget);
    expect(find.textContaining('Left open yesterday'), findsOneWidget);
    expect(find.text('Resume session'), findsOneWidget);
  });

  testWidgets('it reports recent training rather than nothing', (
    WidgetTester tester,
  ) async {
    final now = DateTime(2026, 8, 12);
    await tester.pumpWidget(
      MaterialApp(
        home: TrackSurface(
          today: now,
          log: <Session>[
            finished('Push', DateTime(2026, 8, 10)),
            finished('Pull', DateTime(2026, 8, 11)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The week as sessions and time in the gym (TR4), and the last session
    // under it. Streak, volume and the rest are Profile's.
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('2h 00m'), findsOneWidget);
    expect(find.text('LAST SESSION'), findsOneWidget);
    expect(find.text('WEEK STREAK'), findsNothing);
  });

  testWidgets('an empty log shows dashes rather than zeroes', (
    WidgetTester tester,
  ) async {
    // Noughts on day one are worse than nothing: they read as a scoreboard
    // somebody is already losing. The week is still drawn, as Run draws it,
    // because a front page of one card and empty space was the other failure.
    await tester.pumpWidget(
      MaterialApp(home: TrackSurface(today: DateTime(2026, 8, 12))),
    );
    await tester.pumpAndSettle();
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.text('—'), findsNWidgets(2));
  });
}
