import 'pace_model.dart';
import 'training_plan.dart';

/// What a session should *feel* like, and what it is for.
///
/// **The number was never the instruction.** A row that said "target 4:39 /km"
/// told a runner what to chase and nothing about whether they were doing the
/// session right — and a runner chasing 4:39 on an easy day is running their
/// easy days too hard, which is the most common way to stall a training block.
/// The effort is the instruction; the pace is how it happens to come out for
/// this runner today.
///
/// All of this is deterministic. The coach's *conversation* is the model's job;
/// the coach's *numbers* are Dart's, so a session brief can never quote a pace
/// the runner cannot actually run (docs/architecture/plan-generation.md).
class SessionEffort {
  const SessionEffort({
    required this.label,
    required this.cue,
    required this.feel,
    required this.purpose,
    required this.rpeLow,
    required this.rpeHigh,
  });

  /// The short name for the effort — what a runner would call it out loud.
  /// Shown where a pace used to be, so it reads as an instruction.
  final String label;

  /// Two or three words for the week list, where a full sentence will not fit.
  ///
  /// Deliberately *not* the label: a row reading "Easy / easy" spends a line of
  /// type saying nothing. The cue has to add what the session's name does not —
  /// "conversational" tells a runner how to run an easy run; "easy" does not.
  final String cue;

  /// How to tell, from the inside, that you are running it right. Deliberately
  /// framed around breathing and talking rather than a watch: those work on a
  /// hill, into a headwind, and on a bad night's sleep, and a pace does not.
  final String feel;

  /// Why this session is in the plan at all.
  final String purpose;

  /// Rate of perceived exertion, 1–10. The scale runners are actually taught,
  /// and the honest way to express effort — "40% pace" is not a unit of
  /// anything, since pace and effort are not proportional.
  final int rpeLow;
  final int rpeHigh;

  String get rpe => rpeLow == rpeHigh ? '$rpeLow/10' : '$rpeLow–$rpeHigh/10';
}

/// The effort for a session kind. Every kind has one, including rest.
SessionEffort effortFor(SessionKind kind) => switch (kind) {
  SessionKind.rest => const SessionEffort(
    label: 'Rest',
    cue: 'a training day you spend recovering',
    feel: 'Nothing. A rest day is a training day you spend recovering.',
    purpose:
        'Adaptation happens between the runs, not during them. The week is '
        'built around these as much as around the sessions.',
    rpeLow: 0,
    rpeHigh: 0,
  ),
  SessionKind.recovery => const SessionEffort(
    label: 'Very easy',
    cue: 'slower than feels natural',
    feel:
        'Slower than feels natural — you should finish half-wondering whether '
        'it counted. If you are pushing at all, ease off.',
    purpose:
        'Blood to the legs after a hard day, without asking anything of them. '
        'The whole point is that it costs you nothing.',
    rpeLow: 2,
    rpeHigh: 3,
  ),
  SessionKind.easy => const SessionEffort(
    label: 'Easy',
    cue: 'conversational the whole way',
    feel:
        'Conversational the whole way — full sentences, not gasped words. You '
        'should be able to breathe through your nose if you tried.',
    purpose:
        'This is the aerobic base, and most of your running lives here. '
        'Running easy days too hard is the single most common way a block '
        'stalls: too tired to run the hard days hard, too hard to recover.',
    rpeLow: 3,
    rpeHigh: 4,
  ),
  SessionKind.long => const SessionEffort(
    label: 'Easy, for longer',
    cue: 'easy effort, longer distance',
    feel:
        'The same conversational effort as an easy run. The distance does the '
        'work here, not the pace — if the last few kilometres are a fight, it '
        'started too fast.',
    purpose:
        'Time on your feet is what builds the endurance your goal is made of. '
        'It is the session that matters most, and the one most often ruined by '
        'running it too quickly.',
    rpeLow: 4,
    rpeHigh: 5,
  ),
  SessionKind.marathonPace => const SessionEffort(
    label: 'Steady',
    cue: 'controlled, race effort',
    feel:
        'Comfortable but purposeful — you could talk, but you would rather '
        'not. Controlled, never strained.',
    purpose:
        'Rehearses race effort while it is still cheap, so the pace feels '
        'familiar rather than new on the day.',
    rpeLow: 5,
    rpeHigh: 6,
  ),
  SessionKind.threshold => const SessionEffort(
    label: 'Comfortably hard',
    cue: 'comfortably hard, an hour’s worth',
    feel:
        'Hard but controlled — a few words at a time, not a sentence. The test '
        'is that you could hold it for about an hour if you had to.',
    purpose:
        'Raises the effort you can sustain before fatigue starts to build. '
        'Going faster than this turns a threshold session into a race, and you '
        'get less from it, not more.',
    rpeLow: 7,
    rpeHigh: 8,
  ),
  SessionKind.interval => const SessionEffort(
    label: 'Hard',
    cue: 'fast, and repeatable',
    feel:
        'Fast and repeatable. Every rep should feel strong — if the last one '
        'is falling apart, the first ones were too quick.',
    purpose:
        'Sharpens speed and running economy. Repeatability is the whole point, '
        'so the session is judged on the last rep, not the first.',
    rpeLow: 9,
    rpeHigh: 9,
  ),
  SessionKind.timeTrial => const SessionEffort(
    label: 'Race effort',
    cue: 'as hard as you can hold',
    feel:
        'Hard from the start and harder at the end. You are finding out where '
        'you are, not practising a pace — if you finish with plenty left, you '
        'went out too carefully.',
    purpose:
        'A repeated measurement. Without a race on the calendar this is how '
        'you know whether the training is working, which is why it is worth '
        'running properly rather than treating it as another session.',
    rpeLow: 9,
    rpeHigh: 10,
  ),
  SessionKind.strength => const SessionEffort(
    label: 'Strength',
    cue: 'whatever your session calls for',
    feel:
        'Whatever your session calls for. Leave something in the tank if you '
        'are running tomorrow.',
    purpose:
        'Strength work keeps you durable enough to keep running, which is what '
        'actually gets you to the start line. Runio schedules it; what is in '
        'it is up to you.',
    rpeLow: 0,
    rpeHigh: 0,
  ),
};

/// The pace band for a session kind, or null when the kind has no pace —
/// rest and strength — or the runner has no time trial to derive one from.
PaceBand? bandFor(SessionKind kind, TrainingPaces paces) => switch (kind) {
  SessionKind.rest || SessionKind.strength => null,
  SessionKind.recovery => paces.recoveryBand,
  // A long run is an easy run that goes on longer, so it shares the band. The
  // difference between them is the distance, not the effort.
  SessionKind.easy || SessionKind.long => paces.easyBand,
  SessionKind.marathonPace => paces.marathonBand,
  SessionKind.threshold => paces.thresholdBand,
  SessionKind.interval || SessionKind.timeTrial => paces.intervalBand,
};
