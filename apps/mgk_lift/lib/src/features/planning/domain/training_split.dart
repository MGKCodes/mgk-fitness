/// The shape of a training week, named.
///
/// ## Chosen by arithmetic, never by the model
///
/// The same rule the load limit follows: a property the app can decide exactly
/// is not asked of something that answers in prose. `surfaces.ts` already
/// forbids the chat coach from writing training out — *"no session lists, no
/// weekly schedules, no splits… anything you lay out here is a second version
/// of their training that nobody checked"* — and this is what lets the coach
/// name one anyway. It names a value that was computed and validated, not a
/// week it invented mid-sentence.
///
/// ## Why days is the whole input
///
/// A split sounds like a training philosophy and is really a scheduling
/// wrapper. The evidence is unhelpful to anyone selling one: volume-equated,
/// training frequency has close to no independent effect on hypertrophy — its
/// benefit is that it lets more weekly volume fit. Twice-weekly beats
/// once-weekly mostly in untrained lifters, and the useful target is roughly
/// 12–20 hard sets per muscle per week.
///
/// So the real question is "how do we fit that many sets into the days you
/// have", which is arithmetic on one number. Goal does not change the shape of
/// the week; it changes the rep ranges inside it.
///
/// See the meta-analyses in docs/coach-profile.md's sources.
enum TrainingSplit {
  /// Two or three days. Every session touches everything, because at this
  /// frequency a split would leave a muscle group trained once a week — the one
  /// arrangement the evidence is consistently against.
  fullBody(
    name: 'Full body',
    shape: <String>['Full body A', 'Full body B', 'Full body C'],
    why:
        'At two or three days a week, splitting the body up means training '
        'each part once. Hitting everything each session gets you two or three '
        'exposures a week instead, which is the difference that actually shows.',
  ),

  /// Four days. Two exposures each, and enough room per session to do real
  /// volume without a two-hour workout.
  upperLower(
    name: 'Upper / Lower',
    shape: <String>['Upper', 'Lower', 'Upper', 'Lower'],
    why:
        'Four days splits cleanly in half: everything twice a week, and short '
        'enough sessions that the last movement still gets your attention.',
  ),

  /// Five or six days. Three groupings, run through twice.
  pushPullLegs(
    name: 'Push / Pull / Legs',
    shape: <String>['Push', 'Pull', 'Legs', 'Push', 'Pull', 'Legs'],
    why:
        'Five or six days is enough to run three groupings twice. Each session '
        'is short, everything still gets hit twice, and nothing competes with '
        'anything else on the day.',
  );

  const TrainingSplit({
    required this.name,
    required this.shape,
    required this.why,
  });

  /// What the lifter sees it called.
  final String name;

  /// The week, in order. Trimmed to the days actually available.
  final List<String> shape;

  /// One paragraph, written down rather than generated, for the same reason
  /// the knowledge files are: advice that shapes training should be reviewable
  /// and diffable, not produced fresh and slightly differently every time.
  final String why;

  /// The rule, whole. Deliberately total and deliberately dull.
  static TrainingSplit forDays(int days) => switch (days) {
    <= 3 => TrainingSplit.fullBody,
    4 => TrainingSplit.upperLower,
    _ => TrainingSplit.pushPullLegs,
  };

  /// The week as it will actually run, for the days there are.
  List<String> weekFor(int days) => <String>[
    for (var i = 0; i < days; i++) shape[i % shape.length],
  ];
}
