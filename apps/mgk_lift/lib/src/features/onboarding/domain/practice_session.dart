import 'package:mgk_units/mgk_units.dart';

import '../../tracking/domain/session.dart';

/// The session the walkthrough's practice set is logged in (ADR-0006).
///
/// One movement, laid out the way a saved workout opens: three sets of eight,
/// nothing ticked, so the first thing on the screen is a set ready to log
/// with one tap. **The catalogue's own name**, so the card has its picture
/// and its muscles, as a real one does.
///
/// **A weight a new lifter could put on a bar**: 40 kg, or 95 lb (the bar and
/// a 25 a side) for somebody who works in pounds, each a round number in its
/// own unit rather than one converted into the other. Practice, so nobody is
/// expected to lift it; the fields can be changed like any set's.
///
/// Held in memory only (`InMemorySessionRecorder`), never written anywhere:
/// see `LiftWalkthrough` for everything that keeps it out of the lifter's
/// training.
Session practiceSession(MassUnit unit, {DateTime? at}) {
  final weightKg = unit.isMetric
      ? kPracticeKilograms
      : Mass.pounds(kPracticePounds).kilograms;
  return Session(
    id: 'practice',
    name: kPracticeName,
    startedAt: at ?? DateTime.now(),
    exercises: <SessionExercise>[
      SessionExercise(
        id: 'practice-movement',
        name: kPracticeMovement,
        orderIndex: 0,
        sets: <SessionSet>[
          for (var n = 1; n <= kPracticeSets; n++)
            SessionSet(
              id: 'practice-set-$n',
              setNumber: n,
              reps: kPracticeReps,
              weightKg: weightKg,
            ),
        ],
      ),
    ],
  );
}

/// What the session screen's title reads.
const String kPracticeName = 'Practice';

const String kPracticeMovement = 'Barbell Bench Press';
const int kPracticeSets = 3;
const int kPracticeReps = 8;
const double kPracticeKilograms = 40;
const double kPracticePounds = 95;
