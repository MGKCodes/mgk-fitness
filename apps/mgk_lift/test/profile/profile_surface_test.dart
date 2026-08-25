import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/profile/presentation/profile_surface.dart';
import 'package:mgk_lift/src/features/profile/presentation/year_activity_grid.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

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

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  // Profile is a tall scroller, and a `ListView` only builds what it has
  // scrolled to. The binding's default 800×600 surface used to hold the whole
  // screen; the activity grid and the personal-bests section put everything
  // below them off the bottom of it, where `find` cannot see them. A
  // phone-shaped width and a viewport tall enough for the whole surface tests
  // what a lifter scrolls through rather than only its first screen.
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(400, 2600)
      ..devicePixelRatio = 1;
  });

  tearDown(() => binding.platformDispatcher.views.first.reset());

  group('an empty log', () {
    // This screen used to swap its whole contents for one card, so the lifter
    // who most needed to know what the app tracks — the one who has not
    // started — was the only one who could not see it. The layout renders
    // either way now, with dashes where the figures will be.

    testWidgets('still says nothing is logged, and offers the one next step', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(ProfileSurface(onOpenTrack: () {}, now: DateTime(2026, 8, 24))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nothing logged yet'), findsOneWidget);
      expect(find.text('Log a session'), findsOneWidget);
      // One call to action. A screen with no data and two buttons has one too
      // many, because there is only one next step from any angle.
      expect(find.byType(AppTextButton), findsOneWidget);
    });

    testWidgets('the surface has a title, not a third section label', (
      WidgetTester tester,
    ) async {
      // It used to announce itself with the same SectionLabel component its own
      // subsections use, so the screen had no hierarchy: "Profile" and
      // "Personal bests" were set identically. Every other surface in the suite
      // pairs an eyebrow with a headline.
      await tester.pumpWidget(
        wrap(ProfileSurface(onOpenTrack: () {}, now: DateTime(2026, 8, 24))),
      );
      await tester.pumpAndSettle();

      final title = tester.widget<Text>(find.text('Your training'));
      final theme = Theme.of(
        tester.element(find.text('Your training')),
      ).textTheme;
      expect(title.style, theme.headlineSmall);
      // And it must not repeat the empty card's line, which is a fault this
      // very screen shipped for about ten minutes.
      expect(find.text('Nothing logged yet'), findsOneWidget);
    });

    testWidgets('shows every heading it will fill', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(const ProfileSurface(now: null, log: <Session>[])),
      );
      await tester.pumpAndSettle();

      for (final label in <String>[
        'SESSIONS',
        'VOLUME',
        'SETS',
        'TIME',
        'PER WEEK',
        'STREAK',
        'LAST 52 WEEKS',
        'PERSONAL BESTS',
        'MOST TRAINED',
      ]) {
        expect(find.text(label), findsWidgets, reason: '$label is missing');
      }
      expect(find.byType(YearActivityGrid), findsOneWidget);
    });

    testWidgets('draws dashes, not zeroes', (WidgetTester tester) async {
      // A lifter who has not trained has not scored zero — they have not
      // started. Six blocks reading 0 is a screen reporting six results.
      await tester.pumpWidget(wrap(const ProfileSurface(log: <Session>[])));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsWidgets);
      expect(find.text('0'), findsNothing);
      expect(find.text('0w'), findsNothing);
      expect(find.text('0 kg'), findsNothing);
    });

    testWidgets('leaves out the list of sessions it does not have', (
      WidgetTester tester,
    ) async {
      // The one section that stays hidden. "Most trained" and "Personal bests"
      // name things the app works out for a lifter, which is worth
      // advertising; a list of the sessions they have not done only repeats
      // the card at the top.
      await tester.pumpWidget(wrap(const ProfileSurface(log: <Session>[])));
      await tester.pumpAndSettle();

      expect(find.text('RECENT SESSIONS'), findsNothing);
    });
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
    expect(find.textContaining('A week counts from Monday'), findsOneWidget);
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
    //
    // `.last`, because both movements are also named in the personal-bests
    // section above this one — which is ranked by estimate rather than by
    // frequency, and is the whole reason the two sections both exist.
    final bench = tester.getTopLeft(find.text('Barbell Bench Press').last).dy;
    final squat = tester.getTopLeft(find.text('Barbell Back Squat').last).dy;
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

  group('units', () {
    // Profile reporting kilograms while the session screen reports pounds is
    // the same "two screens, two answers" fault the warm-up bug was.

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
      // A short tonne is 2,000 lb and nobody means that, so the headline
      // switches to thousands separators rather than a unit no lifter uses.
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

      // Scoped to the stat blocks. The screen now carries prose — the shading
      // caption, the Epley footnote — and a bare `textContaining(' t')` over
      // the whole surface tests the copy rather than the unit rule.
      expect(
        find.descendant(
          of: find.byType(StatBlock),
          matching: find.textContaining(' t'),
        ),
        findsNothing,
      );
      expect(find.text('26455 lb'), findsNothing);
      expect(find.text('26,455 lb'), findsOneWidget);
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

    expect(find.text('Runs you log in Run appear here too.'), findsOneWidget);
  });

  group('personal bests', () {
    // The estimator existed and Profile showed no bests at all. Worth knowing
    // before reading these: `estimateOneRepMax` is Epley capped at 12 reps and
    // returns null above it — deliberately stricter than Liftio's 30, because
    // a confidently wrong PB is worse than no PB. "No estimate" is therefore a
    // real state this surface has to render, not an error.

    testWidgets('an estimate carries the set it came from', (
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

      expect(find.text('PERSONAL BESTS'), findsOneWidget);
      expect(find.text('EST. 1RM'), findsOneWidget);
      // Epley: 120 × (1 + 6/30).
      expect(find.text('144 kg'), findsOneWidget);
      // A number a lifter can trace back to a session they remember is a
      // number they will believe.
      expect(find.text('120 kg × 6 · 3 Aug'), findsOneWidget);
    });

    testWidgets('the board is ranked by the estimate, not by frequency', (
      WidgetTester tester,
    ) async {
      // Two benches and one squat: bench leads "most trained", the heavier
      // squat leads the bests. The two sections answer different questions,
      // which is why the same names come out in a different order in each.
      await tester.pumpWidget(
        wrap(
          ProfileSurface(
            now: DateTime(2026, 8, 6),
            log: <Session>[
              session(DateTime(2026, 8, 3), sets: <SessionSet>[done(100, 3)]),
              session(DateTime(2026, 8, 4), sets: <SessionSet>[done(100, 3)]),
              session(
                DateTime(2026, 8, 5),
                exercise: 'Barbell Back Squat',
                sets: <SessionSet>[done(140, 3)],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('154 kg'), findsOneWidget);
      expect(find.text('110 kg'), findsOneWidget);

      final squatBest = tester
          .getTopLeft(find.text('Barbell Back Squat').first)
          .dy;
      final benchBest = tester
          .getTopLeft(find.text('Barbell Bench Press').first)
          .dy;
      expect(squatBest, lessThan(benchBest));

      final benchTrained = tester
          .getTopLeft(find.text('Barbell Bench Press').last)
          .dy;
      final squatTrained = tester
          .getTopLeft(find.text('Barbell Back Squat').last)
          .dy;
      expect(benchTrained, lessThan(squatTrained));
    });

    testWidgets('nothing under 12 reps says so rather than going blank', (
      WidgetTester tester,
    ) async {
      // Twenty reps is past the cap, so there is no estimate anywhere in this
      // log. A lifter doing bodyweight work and high-rep accessories reaches
      // this with a full log, and an empty gap would read as a bug.
      await tester.pumpWidget(
        wrap(
          ProfileSurface(
            now: DateTime(2026, 8, 6),
            log: <Session>[
              session(DateTime(2026, 8, 3), sets: <SessionSet>[done(60, 20)]),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PERSONAL BESTS'), findsOneWidget);
      expect(find.textContaining('No estimate yet'), findsOneWidget);
    });

    testWidgets('an unloaded movement produces no estimate either', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ProfileSurface(
            now: DateTime(2026, 8, 6),
            log: <Session>[
              session(
                DateTime(2026, 8, 3),
                exercise: 'Pull Up',
                sets: <SessionSet>[done(0, 8)],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('No estimate yet'), findsOneWidget);
    });

    testWidgets('the 12-rep rule is stated, not left to be worked out', (
      WidgetTester tester,
    ) async {
      // It is the reason a lift someone is proud of might not be on the list,
      // so it is said whether or not anything is missing.
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
        find.textContaining('Nothing over 12 reps counts'),
        findsOneWidget,
      );
      expect(find.textContaining('not a tested'), findsOneWidget);
    });

    testWidgets('a warm-up cannot set a personal best', (
      WidgetTester tester,
    ) async {
      // The same `workingSets` rule volume follows. Three empty-bar sets
      // before a heavy single are not the record.
      await tester.pumpWidget(
        wrap(
          ProfileSurface(
            now: DateTime(2026, 8, 6),
            log: <Session>[
              session(
                DateTime(2026, 8, 3),
                sets: <SessionSet>[
                  const SessionSet(
                    id: 'warm',
                    setNumber: 1,
                    weightKg: 200,
                    reps: 3,
                    isCompleted: true,
                    setType: SetType.warmup,
                  ),
                  done(100, 3),
                ],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('110 kg'), findsOneWidget);
      expect(find.text('220 kg'), findsNothing);
    });
  });

  group('streaks', () {
    testWidgets('the longest run sits beside the current one', (
      WidgetTester tester,
    ) async {
      // `longestWeekStreak` was folded on every build and shown nowhere. A
      // streak number on its own has no scale: one week is either a start or a
      // collapse, and only the pair says which.
      await tester.pumpWidget(
        wrap(
          ProfileSurface(
            now: DateTime(2026, 8, 24),
            log: <Session>[
              session(DateTime(2026, 8, 24), sets: <SessionSet>[done(100, 5)]),
              session(DateTime(2026, 1, 5), sets: <SessionSet>[done(100, 5)]),
              session(DateTime(2026, 1, 12), sets: <SessionSet>[done(100, 5)]),
              session(DateTime(2026, 1, 19), sets: <SessionSet>[done(100, 5)]),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('THIS RUN'), findsOneWidget);
      expect(find.text('LONGEST'), findsOneWidget);
      expect(find.text('1w'), findsWidgets);
      expect(find.text('3w'), findsOneWidget);
    });
  });

  group('the activity grid', () {
    testWidgets('is on the surface, counting the days in the window', (
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

      expect(find.text('LAST 52 WEEKS'), findsOneWidget);
      expect(find.byType(YearActivityGrid), findsOneWidget);
      expect(find.text('2 days trained · darker is longer'), findsOneWidget);
    });
  });
}
