import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../domain/previous_performance.dart';
import '../domain/session.dart';
import '../domain/session_summary.dart';
import '../domain/workout_library.dart';
import 'save_workout_prompt.dart';

/// What a session was, shown once, immediately after it ends.
///
/// **This is the screen that was missing.** Finishing a session popped straight
/// back to Track, so the last thing a lifter saw of an hour's work was the
/// button that ended it. Everything they had just done was in the database and
/// nowhere on screen, and the only way to look at it was to go and find the
/// session again on Profile.
///
/// It reads as a record rather than a celebration. The totals are the same four
/// the running header carried — so the numbers a lifter watched climb are the
/// numbers they land on, rather than a different four appearing at the end —
/// and the breakdown below is what was actually logged, set by set.
///
/// **Pushed with `pushReplacement`, not on top.** The session screen underneath
/// is showing a session that no longer exists: its clock would tick, and its
/// Finish button would call `finish()` on a recorder with nothing open. Backing
/// out of this therefore lands on Track, which is where the lifter is going
/// anyway.
class SessionSummaryScreen extends StatefulWidget {
  const SessionSummaryScreen({
    super.key,
    required this.session,
    this.massUnit = MassUnit.kilograms,
    this.log = const <Session>[],
    this.library,
    this.onOpenCoach,
  });

  /// The session as it was finished. Must have ended — see [SessionSummary.of].
  final Session session;

  /// What the lifter works in. Storage stays kilograms regardless.
  final MassUnit massUnit;

  /// The finished sessions **before** this one, which is what makes a personal
  /// best possible to detect and what "last time" is read from. An empty log is
  /// a real state — a first session — and reads as no bests and no comparisons
  /// rather than as an error.
  final List<Session> log;

  /// Where a workout would be saved. **Null hides the offer entirely**, which
  /// covers all four reasons not to make it: a build with no on-device
  /// database, a session with nothing in it, one already saved from the button
  /// in the running list, and one that was started *from* the library and
  /// therefore already has its workout. The session screen decides which of
  /// those applies and passes null; this screen only draws.
  final WorkoutLibrary? library;

  /// Opens the coach. **Null hides the action** rather than showing one that
  /// leads nowhere — there is no coach in a free or offline build, the same
  /// rule the coach mark itself follows.
  final VoidCallback? onOpenCoach;

  @override
  State<SessionSummaryScreen> createState() => _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends State<SessionSummaryScreen> {
  late final SessionSummary _summary = SessionSummary.of(
    widget.session,
    log: widget.log,
  );

  /// The name field of the save dialog. Owned here rather than built with the
  /// dialog — see [promptToSaveWorkout] for why that distinction is not
  /// cosmetic.
  final TextEditingController _nameField = TextEditingController();

  /// Set once the workout has been kept, so the offer becomes a statement.
  /// Leaving the button there would invite a second copy of the same workout.
  String? _savedAs;

  @override
  void dispose() {
    _nameField.dispose();
    super.dispose();
  }

  /// **The save offer lives here rather than as a dialog before this screen.**
  ///
  /// It used to fire the instant Finish was tapped: a naming dialog was the
  /// first — and until this screen existed, the only — thing a lifter saw of
  /// the session they had just ended. That put a modal question in front of the
  /// answer, and the question is one the session screen's own note already
  /// says needs the answer first: *saving is something you decide about the
  /// shape of a session after seeing it.* The summary is where the shape is
  /// now, so this is where the offer belongs.
  ///
  /// It is also cheaper to decline. A dialog costs a tap to dismiss whether or
  /// not it was wanted; a button on a screen somebody was going to read anyway
  /// costs nothing to ignore.
  Future<void> _save() async {
    final library = widget.library;
    if (library == null) return;
    final name = await promptToSaveWorkout(
      context,
      library: library,
      field: _nameField,
      suggestedName: widget.session.name,
      movements: workoutMovementsOf(widget.session),
    );
    if (name == null || !mounted) return;
    setState(() => _savedAs = name);
  }

  /// Leaves the summary, then opens the coach.
  ///
  /// **In that order.** The coach is a sheet over whatever surface you were on,
  /// and its gates — sign in, or the paid tier — redirect rather than refuse.
  /// Opening it from on top of this screen would put those redirects behind the
  /// summary, where a lifter would see the tap do nothing at all. Popping first
  /// also matches what the action means: the record has been read, and the
  /// conversation is the next thing rather than a layer over it.
  void _openCoach() {
    final open = widget.onOpenCoach;
    if (open == null) return;
    Navigator.of(context).maybePop();
    open();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: PhotoBackdrop(
        image: 'assets/images/backgrounds/hero_home.webp',
        scrim: ScrimStrength.quiet,
        child: SafeArea(
          child: Column(
            children: <Widget>[
              _Header(
                onBack: () => Navigator.of(context).maybePop(),
                summary: _summary,
                massUnit: widget.massUnit,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  children: <Widget>[
                    _Bests(summary: _summary, massUnit: widget.massUnit),
                    const SizedBox(height: AppSpacing.lg),
                    const SectionLabel('What you did'),
                    const SizedBox(height: AppSpacing.sm),
                    for (final exercise in widget.session.exercises)
                      _MovementCard(
                        exercise: exercise,
                        massUnit: widget.massUnit,
                        // Excludes this session, or "last time" would be the
                        // sets immediately above it on the same card.
                        previous: PreviousPerformance.of(
                          widget.log,
                          exercise.name,
                          excludeSessionId: widget.session.id,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.xl),
                    // Back to Track is the primary, not the coach. This screen
                    // is read and then left, and leaving is the one action
                    // every build has — the coach is absent from a free or
                    // offline one, and the silver fill belongs on something
                    // that is always there.
                    PrimaryButton(
                      label: 'Back to Track',
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    if (widget.onOpenCoach != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton(
                        onPressed: _openCoach,
                        child: const Text('Talk it over with your coach'),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    if (_savedAs != null)
                      Center(
                        child: Text(
                          // Not the snackbar's words. That one has already
                          // said "X is in your workouts" and is on its way
                          // out; this is what stays, and two widgets saying
                          // the same sentence is one thing said twice.
                          'Saved as $_savedAs.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else if (widget.library != null)
                      Center(
                        child: AppTextButton(
                          label: 'Save to your workouts',
                          onPressed: _save,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which session this was, and the four totals.
///
/// **The same four the running header carried, in the same two-by-two grid.**
/// Four across collided at 390pt on that header — "1410 kg" and the set count
/// shared a cell and rendered as `1410 kg3` — and the fix was the grid rather
/// than the type, because `shrinkToFit` cannot help when the box itself is too
/// narrow. Repeating the layout here is not tidiness: it is the same four
/// numbers at the same width, so it is the same collision.
///
/// Fixed rather than scrolling with the breakdown. The name and the totals are
/// the answer to "what did I just do"; scrolling to the third movement should
/// not take them off screen.
class _Header extends StatelessWidget {
  const _Header({
    required this.onBack,
    required this.summary,
    required this.massUnit,
  });

  /// Goes back to Track. Safe and unguarded: the session is finished and
  /// written, and nothing on this screen is in flight.
  final VoidCallback onBack;

  final SessionSummary summary;
  final MassUnit massUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconButton(
                onPressed: onBack,
                icon: Icons.arrow_back,
                color: AppColors.textSecondary,
                tooltip: 'Back to Track',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Where the running screen says "In progress". No date
                    // under it: the lifter finished this four seconds ago, and
                    // telling them which day it was is the app filling space.
                    const SectionLabel('Session complete'),
                    const SizedBox(height: 2),
                    Text(
                      summary.name,
                      style: theme.textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: StatBlock(
                        // "Duration", not "Elapsed": nothing is elapsing any
                        // more.
                        label: 'Duration',
                        value: _clock(summary.duration),
                        shrinkToFit: true,
                      ),
                    ),
                    Expanded(
                      child: StatBlock(
                        label: 'Volume',
                        value: summary.volume == Mass.zero
                            ? '—'
                            : summary.volume.label(massUnit),
                        shrinkToFit: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: StatBlock(
                        label: 'Sets',
                        value: '${summary.workingSets}',
                        shrinkToFit: true,
                      ),
                    ),
                    Expanded(
                      child: StatBlock(
                        label: 'Movements',
                        value: '${summary.movements}',
                        shrinkToFit: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _clock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

/// What went past a previous best, or the one line saying nothing did.
///
/// **A session with no personal best is the ordinary session, not a failed
/// one.** Most training is not a record and is not supposed to be, so the
/// absence gets one quiet line and no panel, no empty-state illustration and no
/// encouragement — anything larger would make the ordinary case look like a
/// problem the screen is apologising for.
///
/// It is a line rather than silence, though, and that is the deliberate part.
/// Rendering nothing at all leaves two different facts looking identical: "we
/// compared, and nothing beat your best" and "we did not look". The first is
/// information; the second is what a lifter assumes when a section they have
/// seen before is missing.
class _Bests extends StatelessWidget {
  const _Bests({required this.summary, required this.massUnit});

  final SessionSummary summary;
  final MassUnit massUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bests = summary.personalBests;

    if (bests.isEmpty) {
      return Text(
        summary.hasEstimate
            ? 'No new bests today.'
            // The other silence, said plainly. A session worked entirely above
            // twelve reps produces no estimate at all — see
            // TrainingStats.estimateOneRepMax — and reporting that as "no new
            // bests" would be claiming a comparison that was never made.
            : 'No best to compare today — a one-rep max can only be '
                  'estimated up to 12 reps.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionLabel(bests.length == 1 ? 'New best' : 'New bests'),
        const SizedBox(height: AppSpacing.sm),
        for (final best in bests)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      // The one status colour on the screen, on the one thing
                      // that is a status rather than a figure (ADR-0009).
                      const Icon(
                        Icons.trending_up,
                        size: 18,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          best.movement,
                          style: theme.textTheme.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // The set that happened, then the estimate — in that order,
                  // because the first is a fact and the second is a fitted
                  // line. "Around" rather than a flat claim for the same
                  // reason: Epley is an estimate and saying so is the
                  // difference between a record and an invention.
                  Text(
                    '${best.weight.label(massUnit)} × ${best.reps} '
                    '— around ${best.estimate.label(massUnit)} for one',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Past ${best.previous.label(massUnit)}, '
                    'set ${_shortDate(best.previousOn)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One movement, and the sets that actually happened on it.
///
/// **Completed sets only.** A row that was added and never ticked is a set the
/// lifter did not do, and a record of a session that lists it is not a record
/// of the session. A movement where none of them were ticked says so rather
/// than disappearing — it was in the session, and quietly dropping it would
/// make the movement count above disagree with the list.
///
/// Warm-ups are shown and marked `W`, the same marker the running row carries.
/// They are excluded from the volume and the set count above, so listing them
/// unmarked would put four ticked sets under a header saying three, which is
/// the exact contradiction the marker was added to the live screen to fix.
class _MovementCard extends StatelessWidget {
  const _MovementCard({
    required this.exercise,
    required this.massUnit,
    required this.previous,
  });

  final SessionExercise exercise;
  final MassUnit massUnit;

  /// What they did on this movement last time, or null if they never have.
  /// Null renders nothing rather than "no history" — a first session should not
  /// be a screen full of blanks.
  final PreviousPerformance? previous;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logged = exercise.sets.where((s) => s.isCompleted).toList();
    final last = previous;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              exercise.name,
              style: theme.textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (last != null) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                'Last time · ${_shortDate(last.on)} · '
                '${_setLabel(last.best, massUnit)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            if (logged.isEmpty)
              Text(
                'Nothing logged',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              )
            else
              for (final set in logged)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: <Widget>[
                      // The same 28pt marker column the live set row uses, so
                      // the numbers line up between the screen you logged on
                      // and the screen you read back.
                      SizedBox(
                        width: 28,
                        child: Text(
                          exercise.labelFor(set),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textTertiary,
                            fontWeight: set.setType == SetType.working
                                ? FontWeight.w400
                                : FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _setLabel(set, massUnit),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// `85 kg × 6`, or `10 reps` where there was no load.
///
/// An unweighted set is a real one — a press-up, a chin-up before anybody adds
/// a belt — and `0 kg × 10` reads as a bug rather than as bodyweight.
String _setLabel(SessionSet set, MassUnit unit) => set.weightKg == 0
    ? '${set.reps} reps'
    : '${Mass.kilograms(set.weightKg).label(unit)} × ${set.reps}';

String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
