import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/profile/presentation/profile_surface.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

Session session(
  DateTime day, {
  String name = 'Evening session',
  String exercise = 'Barbell Bench Press',
  List<SessionSet> sets = const <SessionSet>[],
}) => Session(
  id: day.toIso8601String() + exercise + name,
  name: name,
  startedAt: day,
  endedAt: day.add(const Duration(hours: 1)),
  exercises: <SessionExercise>[
    SessionExercise(
      id: 'e$exercise',
      name: exercise,
      orderIndex: 0,
      sets: sets,
    ),
  ],
);

SessionSet done(double kg, int reps) => SessionSet(
  id: 's$kg-$reps',
  setNumber: 1,
  weightKg: kg,
  reps: reps,
  isCompleted: true,
);

Widget wrap(Widget child) => MaterialApp(theme: AppTheme.dark, home: child);

/// The value a [StatBlock] with [label] shows.
Finder statValue(String label, String value) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(StatBlock)),
  matching: find.text(value),
);

void main() {
  // Profile is a tall scroller, and a sliver list only builds what it has
  // scrolled to. A phone-shaped width and a viewport tall enough for the whole
  // surface tests what a lifter scrolls through rather than its first screen.
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(400, 3000)
      ..devicePixelRatio = 1;
  });

  tearDown(() => binding.platformDispatcher.views.first.reset());

  group('laid out as Run\'s profile is', () {
    testWidgets('titled Profile in a bar, with the way to settings', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(ProfileSurface(now: DateTime(2026, 8, 24), onOpenSettings: () {})),
      );
      await tester.pumpAndSettle();

      expect(
        find.ancestor(
          of: find.text('Profile'),
          matching: find.byType(SliverAppBar),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Settings'), findsOneWidget);
      // A tab's root, with nothing behind it.
      expect(find.byType(BackButton), findsNothing);
      // The eyebrow-and-headline it had until Run's became the standard.
      expect(find.text('Your training'), findsNothing);
    });

    testWidgets('lifetime, records, the table, the year, then the log', (
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

      double top(String text) => tester.getTopLeft(find.text(text).first).dy;
      expect(top('LIFETIME'), lessThan(top('RECORDS')));
      expect(top('RECORDS'), lessThan(top('MOST TRAINED')));
      expect(top('MOST TRAINED'), lessThan(top('THE YEAR')));
      expect(top('THE YEAR'), lessThan(top('1 SESSION')));
    });
  });

  group('an empty log', () {
    // The layout renders either way, with dashes where the figures will be,
    // and the one sentence under the lifetime figures, as Run's does.

    testWidgets('holds the lifetime figures open and says what builds there', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap(ProfileSurface(now: DateTime(2026, 8, 24))));
      await tester.pumpAndSettle();

      expect(find.text('LIFETIME'), findsOneWidget);
      expect(find.text('— kg'), findsOneWidget);
      expect(
        find.textContaining('Log your first session and your totals'),
        findsOneWidget,
      );
      // No card announcing the emptiness, and no button: Run's has neither.
      expect(find.text('Nothing logged yet'), findsNothing);
      expect(find.byType(AppTextButton), findsNothing);
    });

    testWidgets('shows every heading it will fill', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap(ProfileSurface(now: DateTime(2026, 8, 24))));
      await tester.pumpAndSettle();

      for (final label in <String>[
        'LIFETIME',
        'SESSIONS',
        'TIME',
        'STREAK',
        'RECORDS',
        'HEAVIEST LIFT',
        'BIGGEST SESSION',
        'MOST TRAINED',
        'THE YEAR',
        'YOUR SESSIONS',
      ]) {
        expect(find.text(label), findsWidgets, reason: '$label is missing');
      }
      expect(find.byType(ActivityYearGrid), findsOneWidget);
    });

    testWidgets('draws dashes, not zeroes', (WidgetTester tester) async {
      // A lifter who has not trained has not scored zero; they have not
      // started.
      await tester.pumpWidget(wrap(ProfileSurface(now: DateTime(2026, 8, 24))));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsWidgets);
      expect(find.text('0'), findsNothing);
      expect(find.text('0 wk'), findsNothing);
      expect(find.text('0 kg'), findsNothing);
      expect(find.textContaining('0 days'), findsNothing);
    });

    testWidgets('holds the log open with two rows there is nothing to tap', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap(ProfileSurface(now: DateTime(2026, 8, 24))));
      await tester.pumpAndSettle();

      expect(find.text('Date  ·  time  ·  sets  ·  load'), findsNWidgets(2));
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });
  });

  group('lifetime', () {
    testWidgets('figures are folds over the log', (WidgetTester tester) async {
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

      expect(statValue('SESSIONS', '2'), findsOneWidget);
      expect(statValue('TIME', '2 h'), findsOneWidget);
      // 100x5 + 120x5 = 1100 kg, shown as tonnes past four figures.
      expect(find.text('1.1 t'), findsOneWidget);
    });

    testWidgets('the streak is counted in weeks', (WidgetTester tester) async {
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

      expect(statValue('STREAK', '1 wk'), findsOneWidget);
    });

    testWidgets('a lapsed streak is a dash', (WidgetTester tester) async {
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

      expect(statValue('STREAK', '—'), findsOneWidget);
    });
  });

  testWidgets('records are the heaviest set and the biggest session', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ProfileSurface(
          now: DateTime(2026, 8, 6),
          log: <Session>[
            session(
              DateTime(2026, 8, 3),
              sets: <SessionSet>[done(100, 5), done(80, 10)],
            ),
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

    expect(statValue('HEAVIEST LIFT', '120 kg'), findsOneWidget);
    // 100x5 + 80x10, more than the squat session's 600.
    expect(statValue('BIGGEST SESSION', '1300 kg'), findsOneWidget);
  });

  group('most trained', () {
    testWidgets('ranks by sessions, not by sets', (WidgetTester tester) async {
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

      // Set as Run sets "5K": a label, in capitals.
      final bench = tester.getTopLeft(find.text('BARBELL BENCH PRESS')).dy;
      final squat = tester.getTopLeft(find.text('BARBELL BACK SQUAT')).dy;
      expect(bench, lessThan(squat));
    });

    testWidgets('the count is labelled, not left as a bare number', (
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

      // Once over the lifetime count, once over the table's column.
      expect(find.text('SESSIONS'), findsNWidgets(2));
    });

    testWidgets('a row opens its movement', (WidgetTester tester) async {
      String? opened;
      await tester.pumpWidget(
        wrap(
          ProfileSurface(
            now: DateTime(2026, 8, 6),
            log: <Session>[
              session(DateTime(2026, 8, 3), sets: <SessionSet>[done(120, 6)]),
            ],
            onOpenMovement: (name) => opened = name,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('BARBELL BENCH PRESS'));
      await tester.pumpAndSettle();

      expect(opened, 'Barbell Bench Press');
    });

    testWidgets('with nowhere to open, the rows stay text', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ProfileSurface(
            now: DateTime(2026, 8, 6),
            log: <Session>[
              session(DateTime(2026, 8, 3), sets: <SessionSet>[done(120, 6)]),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.ancestor(
          of: find.text('BARBELL BENCH PRESS'),
          matching: find.byType(PressScale),
        ),
        findsNothing,
      );
    });
  });

  group('units', () {
    // Profile reporting kilograms while the session screen reports pounds is
    // the "two screens, two answers" fault the warm-up bug was.

    testWidgets('volume follows the chosen unit', (WidgetTester tester) async {
      final log = <Session>[
        session(DateTime(2026, 8, 3), sets: <SessionSet>[done(100, 5)]),
      ];

      await tester.pumpWidget(
        wrap(ProfileSurface(now: DateTime(2026, 8, 6), log: log)),
      );
      await tester.pumpAndSettle();
      expect(find.text('500 kg'), findsWidgets);

      await tester.pumpWidget(
        wrap(
          ProfileSurface(
            now: DateTime(2026, 8, 6),
            log: log,
            massUnit: MassUnit.pounds,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1102 lb'), findsWidgets);
      expect(find.text('500 kg'), findsNothing);
    });

    testWidgets('pounds are never reported in tonnes', (
      WidgetTester tester,
    ) async {
      // A short ton is 2,000 lb and nobody means that, so the lifetime figure
      // takes thousands separators rather than a unit no lifter uses.
      await tester.pumpWidget(
        wrap(
          ProfileSurface(
            now: DateTime(2026, 8, 6),
            massUnit: MassUnit.pounds,
            log: <Session>[
              for (var i = 0; i < 12; i++)
                session(
                  DateTime(2026, 8, 3),
                  exercise: 'Movement $i',
                  sets: <SessionSet>[done(100, 10)],
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('26,455 lb'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CountUp),
          matching: find.textContaining(' t'),
        ),
        findsNothing,
      );
    });
  });

  group('the year', () {
    testWidgets('is Run\'s grid, counting days trained and their load', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ProfileSurface(
            now: DateTime(2026, 8, 24),
            log: <Session>[
              session(DateTime(2026, 8, 17), sets: <SessionSet>[done(100, 5)]),
              session(DateTime(2026, 8, 19), sets: <SessionSet>[done(100, 5)]),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ActivityYearGrid), findsOneWidget);
      // Tonnes past four figures, as the lifetime total is.
      expect(find.text('2 days trained · 1.0 t'), findsOneWidget);
      expect(find.text('Trained'), findsOneWidget);
      expect(find.text('Rest'), findsOneWidget);
    });

    testWidgets('says day, not days, for one', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          ProfileSurface(
            now: DateTime(2026, 8, 24),
            log: <Session>[
              session(DateTime(2026, 8, 17), sets: <SessionSet>[done(100, 5)]),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 day trained · 500 kg'), findsOneWidget);
    });
  });

  group('the log', () {
    testWidgets('shows the recent sessions and hands over to all of them', (
      WidgetTester tester,
    ) async {
      var history = 0;
      await tester.pumpWidget(
        wrap(
          ProfileSurface(
            now: DateTime(2026, 8, 24),
            onOpenHistory: () => history++,
            log: <Session>[
              for (var i = 0; i < 7; i++)
                session(
                  DateTime(2026, 8, 20 - i),
                  name: 'Session $i',
                  sets: <SessionSet>[done(100, 5)],
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('7 SESSIONS'), findsOneWidget);
      expect(find.text('Session 0'), findsOneWidget);
      expect(find.text('Session 4'), findsOneWidget);
      expect(find.text('Session 5'), findsNothing);

      await tester.tap(find.text('See all'));
      expect(history, 1);
    });

    testWidgets('a session opens from its row', (WidgetTester tester) async {
      Session? opened;
      final only = session(
        DateTime(2026, 8, 20),
        name: 'Push',
        sets: <SessionSet>[done(100, 5)],
      );
      await tester.pumpWidget(
        wrap(
          ProfileSurface(
            now: DateTime(2026, 8, 24),
            log: <Session>[only],
            onOpenSession: (s) => opened = s,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 SESSION'), findsOneWidget);
      expect(find.textContaining('20 Aug'), findsOneWidget);
      await tester.tap(find.text('Push'));
      expect(opened, same(only));
    });
  });

  testWidgets('claims nothing about Run, which it does not read', (
    WidgetTester tester,
  ) async {
    // It once said "Runs you log in Run appear here too." Nothing in Lift
    // reads Run's data.
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

    expect(find.textContaining('Run'), findsNothing);
  });
}
