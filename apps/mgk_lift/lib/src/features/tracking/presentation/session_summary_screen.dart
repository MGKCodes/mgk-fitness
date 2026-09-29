import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../sync/presentation/backup_messages.dart';
import '../../sync/presentation/backup_scheduler.dart';
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
    this.offerSave = true,
    this.templateId,
    this.lesson,
    this.backup,
    this.onOpenCoach,
    this.onEdit,
    this.onDelete,
  });

  /// Opened from the log rather than from Finish: the same layout, read, with
  /// **Edit** and **Delete** where Finish's actions were. Either being set is
  /// what makes it the history's view of the session.
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  bool get fromHistory => onEdit != null || onDelete != null;

  /// The session as it was finished. Must have ended — see [SessionSummary.of].
  final Session session;

  /// What the lifter works in. Storage stays kilograms regardless.
  final MassUnit massUnit;

  /// The finished sessions **before** this one, which is what makes a personal
  /// best possible to detect and what "last time" is read from. An empty log is
  /// a real state — a first session — and reads as no bests and no comparisons
  /// rather than as an error.
  final List<Session> log;

  /// The lifter's saved workouts — where this session could be saved, and
  /// where the workout it came from learns from it. Null is a build with no
  /// on-device database, and hides both.
  final WorkoutLibrary? library;

  /// Whether to offer "Save to your workouts". The session screen decides:
  /// not for a session with nothing in it, one already saved from the button in
  /// the running list, or one started from the library — which already has its
  /// workout, and teaches it instead ([lesson]).
  final bool offerSave;

  /// The saved workout this session was started from, if any.
  final String? templateId;

  /// What the session did to that workout — see [TemplateUpdate]. Applied here
  /// on arrival, with Undo; asked about instead when the workout changed while
  /// the session ran; offered as a new workout when it was deleted meanwhile.
  final TemplateUpdate? lesson;

  /// Whether this session is backed up, said under the totals. Null is a
  /// build with no server, where there is nothing to say beyond the log.
  final BackupHooks? backup;

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

  /// Where the workout's lesson stands. See [_learn].
  _Lesson _lesson = _Lesson.none;

  /// The workout as it was before the lesson was applied — what Undo puts
  /// back — or, when the lesson is waiting to be asked about, as it is now.
  SavedWorkout? _workout;

  @override
  void initState() {
    super.initState();
    _learn();
  }

  @override
  void dispose() {
    _nameField.dispose();
    super.dispose();
  }

  /// **The workout learns from the session** — decision D1: applied, not
  /// asked, with Undo on this screen, so a movement removed today does not
  /// have to be removed again next week.
  ///
  /// Applied only when the workout is exactly as it was when the session
  /// started. If it changed meanwhile — edited here or on another device — the
  /// session's changes were made against a workout that no longer exists, so
  /// the lifter is asked instead of having one edit silently beat the other.
  /// If it was deleted, the lesson is offered as a new workout.
  Future<void> _learn() async {
    final library = widget.library;
    final id = widget.templateId;
    final lesson = widget.lesson;
    if (library == null || id == null || lesson == null || lesson.isEmpty) {
      return;
    }
    final current = await library.byId(id);
    if (!mounted) return;
    if (current == null) {
      setState(() => _lesson = _Lesson.missing);
      return;
    }
    if (!_same(current.movements, lesson.before)) {
      setState(() {
        _workout = current;
        _lesson = _Lesson.changedMeanwhile;
      });
      return;
    }
    await library.update(current.copyWith(movements: lesson.after));
    if (!mounted) return;
    setState(() {
      _workout = current;
      _lesson = _Lesson.applied;
    });
  }

  Future<void> _undoLesson() async {
    final library = widget.library;
    final before = _workout;
    if (library == null || before == null) return;
    await library.update(before);
    if (mounted) setState(() => _lesson = _Lesson.undone);
  }

  Future<void> _applyAnyway() async {
    final library = widget.library;
    final current = _workout;
    final lesson = widget.lesson;
    if (library == null || current == null || lesson == null) return;
    await library.update(current.copyWith(movements: lesson.after));
    if (mounted) setState(() => _lesson = _Lesson.appliedOnRequest);
  }

  Future<void> _saveLessonAsNew() async {
    final library = widget.library;
    final lesson = widget.lesson;
    if (library == null || lesson == null) return;
    final name = await promptToSaveWorkout(
      context,
      library: library,
      field: _nameField,
      suggestedName: widget.session.name,
      movements: lesson.after,
    );
    if (name == null || !mounted) return;
    setState(() {
      _savedAs = name;
      _lesson = _Lesson.none;
    });
  }

  static bool _same(List<TemplateMovement> a, List<TemplateMovement> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
                // From the log, the date is the point: which Tuesday it was.
                label: widget.fromHistory
                    ? _dayLabel(widget.session.startedAt)
                    : 'Session complete',
                backTooltip: widget.fromHistory ? 'Back' : 'Back to Track',
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
                    if (widget.backup case final backup?) ...<Widget>[
                      Entrance(
                        child: _BackupLine(
                          hooks: backup,
                          session: widget.session,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    Entrance(
                      index: 1,
                      child: _Bests(
                        summary: _summary,
                        massUnit: widget.massUnit,
                      ),
                    ),
                    if (_lesson != _Lesson.none) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      Entrance(
                        index: 2,
                        child: _LessonCard(
                          lesson: _lesson,
                          workoutName: _workout?.name ?? widget.session.name,
                          change: widget.lesson?.describe() ?? '',
                          onUndo: _undoLesson,
                          onApply: _applyAnyway,
                          onKeep: () =>
                              setState(() => _lesson = _Lesson.keptAsItWas),
                          onSaveAsNew: _saveLessonAsNew,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    const SectionLabel('What you did'),
                    const SizedBox(height: AppSpacing.sm),
                    for (final (i, exercise)
                        in widget.session.exercises.indexed)
                      Entrance(
                        index: 3 + i,
                        child: _MovementCard(
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
                      ),
                    const SizedBox(height: AppSpacing.xl),
                    if (widget.fromHistory) ...<Widget>[
                      if (widget.onEdit != null)
                        AppOutlinedButton(
                          label: 'Edit session',
                          icon: Icons.edit_outlined,
                          onPressed: widget.onEdit,
                          expand: true,
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      if (widget.onDelete != null)
                        Center(
                          child: AppTextButton(
                            label: 'Delete session',
                            onPressed: widget.onDelete,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.danger,
                            ),
                          ),
                        ),
                    ] else ...<Widget>[
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
                        AppOutlinedButton(
                          label: 'Talk it over with your coach',
                          onPressed: _openCoach,
                          expand: true,
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
                      else if (widget.library != null && widget.offerSave)
                        Center(
                          child: AppTextButton(
                            label: 'Save to your workouts',
                            onPressed: _save,
                          ),
                        ),
                    ],
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
    this.label = 'Session complete',
    this.backTooltip = 'Back to Track',
  });

  final String label;
  final String backTooltip;

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
                tooltip: backTooltip,
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
                    SectionLabel(label),
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
                      // The totals count up to their value as the summary
                      // arrives — the session adding itself up.
                      child: summary.volume == Mass.zero
                          ? const StatBlock(
                              label: 'Volume',
                              value: '—',
                              shrinkToFit: true,
                            )
                          : StatBlock.counting(
                              label: 'Volume',
                              count: summary.volume.kilograms,
                              format: (kg) =>
                                  Mass.kilograms(kg).label(massUnit),
                              shrinkToFit: true,
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: StatBlock.counting(
                        label: 'Sets',
                        count: summary.workingSets.toDouble(),
                        format: (n) => '${n.round()}',
                        shrinkToFit: true,
                      ),
                    ),
                    Expanded(
                      child: StatBlock.counting(
                        label: 'Movements',
                        count: summary.movements.toDouble(),
                        format: (n) => '${n.round()}',
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
        for (final (i, best) in bests.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            // Lands rather than appears: grows in on a spring, a beat after
            // the totals — the one moment on this screen that is news.
            child: _Lands(
              delay: AppMotion.stagger * (4 + i),
              // Felt once, as the first best lands — not per card.
              onLand: i == 0 ? () => unawaited(AppHaptics.commit()) : null,
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

/// Where the workout's lesson stands.
enum _Lesson {
  /// Nothing to say: not from a workout, or nothing changed.
  none,

  /// Applied on arrival; Undo is offered.
  applied,

  /// Undone; the workout is as it was.
  undone,

  /// The workout changed while the session ran; the lifter is asked.
  changedMeanwhile,

  /// Asked, and they said update it.
  appliedOnRequest,

  /// Asked, and they said keep it.
  keptAsItWas,

  /// The workout was deleted while the session ran.
  missing,
}

/// The one line about the workout this session came from — what changed in it,
/// and the way back.
/// Where this session stands: on this phone at once, then backed up — or why
/// not, with the one thing that would fix it.
///
/// **Live.** Finish is a checkpoint, and the run it starts lands a couple of
/// seconds after this screen does; the line changes under the lifter's eyes
/// rather than asking them to come back and check.
class _BackupLine extends StatelessWidget {
  const _BackupLine({required this.hooks, required this.session});

  final BackupHooks hooks;
  final Session session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<BackupStatus>(
      valueListenable: hooks.status,
      builder: (context, status, _) {
        final message = sessionBackupMessage(
          status,
          sessionId: session.id,
          finishedAt: session.endedAt ?? session.startedAt,
        );
        final backedUp = message.text == 'Backed up.';
        final icon = backedUp
            ? Icons.cloud_done_outlined
            : status.retrying || status.state == BackupState.expired
            ? Icons.cloud_off_outlined
            : Icons.smartphone_outlined;
        final action = switch (message.action) {
          BackupAction.retry when hooks.onRetry != null => AppTextButton(
            label: 'Retry',
            onPressed: hooks.onRetry,
          ),
          BackupAction.signIn when hooks.onSignIn != null => AppTextButton(
            label: 'Sign in',
            onPressed: hooks.onSignIn,
          ),
          _ => null,
        };
        return AnimatedSwitcher(
          duration: AppMotion.fast,
          child: Row(
            key: ValueKey<String>(message.text),
            children: <Widget>[
              Icon(icon, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message.text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              ?action,
            ],
          ),
        );
      },
    );
  }
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({
    required this.lesson,
    required this.workoutName,
    required this.change,
    required this.onUndo,
    required this.onApply,
    required this.onKeep,
    required this.onSaveAsNew,
  });

  final _Lesson lesson;
  final String workoutName;

  /// `removed Cable Fly, added Dips`.
  final String change;

  final VoidCallback onUndo;
  final VoidCallback onApply;
  final VoidCallback onKeep;
  final VoidCallback onSaveAsNew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String text, List<Widget> actions) = switch (lesson) {
      _Lesson.applied => (
        '$workoutName updated — $change.',
        <Widget>[AppTextButton(label: 'Undo', onPressed: onUndo)],
      ),
      _Lesson.undone => ('$workoutName kept as it was.', const <Widget>[]),
      _Lesson.changedMeanwhile => (
        '$workoutName changed while you trained. Update it with today\'s '
            'changes — $change?',
        <Widget>[
          AppTextButton(label: 'Keep it', onPressed: onKeep),
          AppTextButton(
            label: 'Update',
            onPressed: onApply,
            style: TextButton.styleFrom(foregroundColor: AppColors.textPrimary),
          ),
        ],
      ),
      _Lesson.appliedOnRequest => ('$workoutName updated.', const <Widget>[]),
      _Lesson.keptAsItWas => ('$workoutName kept as it was.', const <Widget>[]),
      _Lesson.missing => (
        '$workoutName was deleted while you trained. Keep today\'s version as '
            'a new workout?',
        <Widget>[AppTextButton(label: 'Save as new', onPressed: onSaveAsNew)],
      ),
      _Lesson.none => ('', const <Widget>[]),
    };
    return AppCard(
      color: AppColors.elevated,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.bookmark_outline,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ],
          ),
          if (actions.isNotEmpty)
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
        ],
      ),
    );
  }
}

/// Grows its child in on a spring, once, after [delay] — for a new best.
/// Still under reduced motion.
class _Lands extends StatefulWidget {
  const _Lands({required this.child, this.delay = Duration.zero, this.onLand});

  final Widget child;
  final Duration delay;

  /// Called once, as it starts to grow — with the animation, not on a timer
  /// of its own, so nothing is left pending if the screen goes first.
  final VoidCallback? onLand;

  @override
  State<_Lands> createState() => _LandsState();
}

class _LandsState extends State<_Lands> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.slow + widget.delay,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.delay.inMicroseconds /
          (AppMotion.slow + widget.delay).inMicroseconds,
      1,
      curve: AppMotion.snappy,
    ),
  );
  bool _started = false;
  bool _landed = false;

  void _watch() {
    if (_landed || _t.value <= 0) return;
    _landed = true;
    widget.onLand?.call();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _c.addListener(_watch);
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      // Still, and still felt: reduced motion does not change haptics.
      _c.value = 1;
      return;
    }
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    builder: (context, child) => Opacity(
      opacity: _c.value == 0 ? 0 : _t.value.clamp(0, 1),
      child: Transform.scale(scale: 0.9 + 0.1 * _t.value, child: child),
    ),
    child: widget.child,
  );
}

/// `Tuesday 23 Sep` — the day a past session happened.
String _dayLabel(DateTime d) {
  const days = <String>[
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', //
    'Sunday',
  ];
  const months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
}
