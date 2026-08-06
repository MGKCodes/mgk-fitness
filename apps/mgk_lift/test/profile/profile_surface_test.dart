import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/profile/presentation/profile_surface.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_ui/mgk_ui.dart';

Session session(
  DateTime day, {
  String name = 'Evening session',
  String exercise = 'Barbell Bench Press',
  List<SessionSet> sets = const <SessionSet>[],
}) => Session(
  id: day.toIso8601String() + exercise,
  name: name,
  startedAt: day,
  endedAt: day.add(const Duration(hours: 1)),
  exercises: <SessionExercise>[
    SessionExercise(id: 'e$exercise', name: exercise, orderIndex: 0, sets: sets),
  ],
);

SessionSet done(double kg, int reps) => SessionSet(
  id: 's$kg-$reps',
  setNumber: 1,
  weightKg: kg,
  reps: reps,
  isCompleted: true,
);

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('an empty log explains itself rather than showing zeroes', (
    WidgetTester tester,
  ) async {
    // Six stat blocks reading 0 is a worse first impression than one sentence
    // saying what will appear here.
    await tester.pumpWidget(wrap(const ProfileSurface()));
    await tester.pumpAndSettle();

    expect(find.text('Nothing logged yet'), findsOneWidget);
    expect(find.text('SESSIONS'), findsNothing);
  });

  testWidgets('headline figures are folds over the log', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ProfileSurface(
          now: DateTime(2026, 8, 6),
          log: <Session>[
            session(DateTime(2026, 8, 3), sets: <SessionSet>[done(100, 5)]),
            session(
              DateTime(2026, 8, 5),
              exercise: 'Barbell Back Squat',
              sets: <SessionSet>[done(120, 5)],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scoped to the stat block: "SESSIONS" now appears twice on this screen,
    // once as the headline count and once heading the most-trained column.
    expect(
      find.descendant(
        of: find.byType(StatBlock),
        matching: find.text('SESSIONS'),
      ),
      findsOneWidget,
    );
    expect(find.text('2'), findsWidgets);
    // 100x5 + 120x5 = 1100 kg, shown as tonnes past four figures.
    expect(find.text('1.1 t'), findsOneWidget);
  });

  testWidgets('the streak explains what a week means', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ProfileSurface(
          now: DateTime(2026, 8, 6),
          log: <Session>[
            session(DateTime(2026, 8, 3), sets: <SessionSet>[done(100, 5)]),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 week in a row'), findsOneWidget);
  });

  testWidgets('no streak says how to start one, and from when', (
    WidgetTester tester,
  ) async {
    // "A week counts from Monday" is worth saying out loud, because Liftio's
    // weeks ran Thursday to Wednesday and nobody could have known.
    await tester.pumpWidget(
      wrap(
        ProfileSurface(
          now: DateTime(2026, 8, 20),
          log: <Session>[
            session(DateTime(2026, 6, 1), sets: <SessionSet>[done(100, 5)]),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No streak running'), findsOneWidget);
    expect(
      find.textContaining('A week counts from Monday'),
      findsOneWidget,
    );
  });

  testWidgets('most-trained ranks by sessions, not by sets', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ProfileSurface(
          now: DateTime(2026, 8, 6),
          log: <Session>[
            session(DateTime(2026, 8, 3), sets: <SessionSet>[done(100, 5)]),
            session(DateTime(2026, 8, 4), sets: <SessionSet>[done(100, 5)]),
            session(
              DateTime(2026, 8, 5),
              exercise: 'Barbell Back Squat',
              sets: <SessionSet>[done(120, 5), done(120, 5), done(120, 5)],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MOST TRAINED'), findsOneWidget);
    // Squat has more sets; bench appears in more sessions and should lead.
    final bench = tester.getTopLeft(find.text('Barbell Bench Press')).dy;
    final squat = tester.getTopLeft(find.text('Barbell Back Squat')).dy;
    expect(bench, lessThan(squat));
  });

  testWidgets('the session count is labelled, not left as a bare number', (
    WidgetTester tester,
  ) async {
    // A bare "2" beside a movement name could be sessions, sets or kilos.
    await tester.pumpWidget(
      wrap(
        ProfileSurface(
          now: DateTime(2026, 8, 6),
          log: <Session>[
            session(DateTime(2026, 8, 3), sets: <SessionSet>[done(100, 5)]),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SESSIONS'), findsWidgets);
  });

  group('most-trained bars', () {
    // A bar is a comparison. Found by screenshotting Profile: with a short log
    // every movement has been done once, so every bar was full — three
    // identical full-width rules that read as dividers and said nothing.

    testWidgets('are absent when everything shown has the same count', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ProfileSurface(
            now: DateTime(2026, 8, 6),
            log: <Session>[
              session(DateTime(2026, 8, 3), sets: <SessionSet>[done(100, 5)]),
              session(
                DateTime(2026, 8, 4),
                exercise: 'Barbell Back Squat',
                sets: <SessionSet>[done(120, 5)],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MOST TRAINED'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('are present as soon as there is something to compare', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ProfileSurface(
            now: DateTime(2026, 8, 6),
            log: <Session>[
              session(DateTime(2026, 8, 3), sets: <SessionSet>[done(100, 5)]),
              session(DateTime(2026, 8, 4), sets: <SessionSet>[done(100, 5)]),
              session(
                DateTime(2026, 8, 5),
                exercise: 'Barbell Back Squat',
                sets: <SessionSet>[done(120, 5)],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    });
  });

  testWidgets('the cross-app line is present once there is a log', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ProfileSurface(
          now: DateTime(2026, 8, 6),
          log: <Session>[
            session(DateTime(2026, 8, 3), sets: <SessionSet>[done(100, 5)]),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Runs you log in Run appear here too.'),
      findsOneWidget,
    );
  });
}
