import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_lift/src/features/tracking/presentation/track_surface.dart';
import 'package:mgk_lift/main.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';
import 'package:mgk_lift/src/features/auth/data/fake_auth.dart';
import 'package:mgk_lift/src/features/auth/domain/account.dart';
import 'package:mgk_lift/src/features/coaching/data/supabase_coach.dart';
import 'package:mgk_lift/src/features/coaching/presentation/coach_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

void main() {
  trackContentTests();
  testWidgets('the shell opens on Track and takes its theme from mgk_ui', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MgkLiftApp());

    // SectionLabel uppercases its text — the eyebrow is a decision made once in
    // mgk_ui, not something each screen restates.
    expect(find.text('TODAY'), findsOneWidget);
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
    // With no log, Profile explains what will appear rather than showing six
    // stat blocks reading zero.
    expect(find.text('Nothing logged yet'), findsOneWidget);

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
    expect(find.text('Coach'), findsNothing);

    await tester.pumpWidget(MaterialApp(home: LiftShell(coach: FakeCoach())));
    await tester.pumpAndSettle();
    expect(find.text('Coach'), findsOneWidget);
  });

  testWidgets('the coach mark does not compete with the screen\'s own action', (
    WidgetTester tester,
  ) async {
    // Found by screenshotting Track: full-width, the mark sat directly under
    // "Start a session" as a second pill of the same size and weight, and the
    // eye could not tell which one was the point of the screen. The coach is
    // permanently available; it is not what you came here to do.
    await tester.pumpWidget(MaterialApp(home: LiftShell(coach: FakeCoach())));
    await tester.pumpAndSettle();

    final markWidth = tester.getSize(find.text('Coach')).width;
    final screenWidth = tester.getSize(find.byType(LiftShell)).width;
    expect(markWidth, lessThan(screenWidth / 2));
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
        find.text('Coach'),
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

    await tester.tap(find.text('Coach'));
    await tester.pumpAndSettle();
    expect(find.byType(CoachScreen), findsOneWidget);
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

    await tester.tap(find.text('Coach'));
    await tester.pumpAndSettle();

    expect(find.byType(CoachScreen), findsNothing);
    expect(find.text('Welcome back'), findsOneWidget);
  });

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

    await tester.tap(find.text('Coach'));
    await tester.pumpAndSettle();

    expect(find.byType(CoachScreen), findsNothing);
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

    expect(find.text('Push'), findsOneWidget);
    expect(find.textContaining('1 set in'), findsOneWidget);
    expect(find.textContaining('yesterday'), findsOneWidget);

    // The headline names the session instead of paraphrasing the card's label.
    // It read "Pick up where you were" directly above a card labelled "Where
    // you were" — the same phrase twice, the vaguer one larger.
    expect(find.text('Push is still open'), findsOneWidget);
    expect(
      find.textContaining('Pick up where you were'),
      findsNothing,
      reason: 'the headline must not restate the label below it',
    );
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

    expect(find.text('this week'), findsOneWidget);
    expect(find.text('week streak'), findsOneWidget);
    expect(find.text('last session'), findsOneWidget);
  });

  testWidgets('an empty log shows no figures rather than zeroes', (
    WidgetTester tester,
  ) async {
    // Three noughts on day one is worse than nothing: it reads as a scoreboard
    // somebody is already losing.
    await tester.pumpWidget(
      MaterialApp(home: TrackSurface(today: DateTime(2026, 8, 12))),
    );
    await tester.pumpAndSettle();
    expect(find.text('this week'), findsNothing);
  });
}
