import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../stats/presentation/exercise_stats_screen.dart';
import '../../sync/presentation/backup_messages.dart';
import '../../sync/presentation/backup_scheduler.dart';
import '../data/exercise_lookup.dart';
import '../domain/previous_performance.dart';
import '../domain/session.dart';
import '../domain/session_summary.dart';

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
    this.backup,
    this.onOpenCoach,
    this.onEdit,
    this.onDelete,
    this.onOpenMovement,
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

  /// Whether this session is backed up, in the pill at the top. Null is a
  /// build with no server, where there is nothing to say beyond the log.
  final BackupHooks? backup;

  /// Opens the coach, from the mark. **Null hides the mark** rather than
  /// showing one that leads nowhere — there is no coach in an offline build.
  final VoidCallback? onOpenCoach;

  /// Opens a movement's stats (R9), from its name. Null opens them here, over
  /// this session and [log]; the shell passes its own, over the whole log as
  /// it changes, for a session opened from the history.
  final ValueChanged<String>? onOpenMovement;

  @override
  State<SessionSummaryScreen> createState() => _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends State<SessionSummaryScreen> {
  static final ExerciseLookup _lookup = ExerciseLookup();

  void _openMovement(String name) {
    final open = widget.onOpenMovement;
    if (open != null) return open(name);
    ExerciseStatsScreen.open(
      context,
      name: name,
      log: <Session>[widget.session, ...widget.log],
      catalogue: _lookup.find(name),
      massUnit: widget.massUnit,
    );
  }

  late final SessionSummary _summary = SessionSummary.of(
    widget.session,
    log: widget.log,
  );

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

  /// What the mark says as the summary arrives: the session's new bests (13,
  /// R7), then it closes. Null says nothing — most sessions set no best, and
  /// the mark is not there to fill the silence.
  /// Cleared once said, so the mark goes back to resting rather than holding
  /// a line nobody can see.
  late CoachLine? _bests = _bestsLine(_summary, widget.massUnit);

  static CoachLine? _bestsLine(SessionSummary summary, MassUnit unit) {
    final bests = summary.personalBests;
    if (bests.isEmpty) return null;
    if (bests.length == 1) {
      final b = bests.single;
      return CoachLine(
        headline: 'New best: ${b.movement}',
        detail:
            '${b.weight.label(unit)} × ${b.reps}, about ${b.estimate.label(unit)} '
            'for one. Past ${b.previous.label(unit)}.',
      );
    }
    final names = <String>[for (final b in bests) b.movement];
    return CoachLine(
      headline: '${bests.length} new bests',
      detail:
          '${names.take(names.length - 1).join(', ')} and ${names.last}, '
          'each past its best.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final backup = widget.backup;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final mark = widget.onOpenCoach != null && !widget.fromHistory;

    return Scaffold(
      backgroundColor: AppColors.bg,
      // The session's own light (R13): the screen it was logged on, ended.
      body: GlowBackdrop(
        child: Stack(
          children: <Widget>[
            SafeArea(
              bottom: false,
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
                    backTooltip: widget.fromHistory ? 'Back' : 'Done',
                    // At the top, where it is seen first (14): backing up, and
                    // then gone; or why not, with the one thing that fixes it.
                    backup: backup == null || widget.fromHistory
                        ? null
                        : _BackupPill(hooks: backup, session: widget.session),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.xxl +
                            bottom +
                            (mark ? kCoachMarkClearance : 0),
                      ),
                      children: <Widget>[
                        const SectionLabel('What you did'),
                        const SizedBox(height: AppSpacing.sm),
                        for (final (i, exercise)
                            in widget.session.exercises.indexed)
                          Entrance(
                            index: 1 + i,
                            child: _MovementCard(
                              exercise: exercise,
                              massUnit: widget.massUnit,
                              onOpenStats: () => _openMovement(exercise.name),
                              // Excludes this session, or "last time" would be
                              // the sets immediately above it on the same card.
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
                        ] else
                          // One way out (12). Nothing is left pending here any
                          // more — the workout was asked about at Finish — so
                          // the button says what the screen is: done.
                          PrimaryButton(
                            label: 'Done',
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // The mark, as on every other screen, saying the session's new
            // bests and closing (13, R7). It no longer has to count as Finish
            // (R4): a tap is the conversation, nothing more.
            if (mark)
              Positioned(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                bottom: AppSpacing.lg + bottom,
                child: CoachReveal(
                  note: _bests,
                  onTap: _openCoach,
                  onFinished: () {
                    if (mounted) setState(() => _bests = null);
                  },
                ),
              ),
          ],
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
    this.backTooltip = 'Done',
    this.backup,
  });

  final String label;
  final String backTooltip;

  /// Where backup stands, above the totals. Null says nothing.
  final Widget? backup;

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
                icon: backIcon(context),
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
          if (backup case final pill?) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Align(alignment: Alignment.centerLeft, child: pill),
          ],
          const SizedBox(height: AppSpacing.md),
          // On glass, and louder (12): one number leads — the load moved, or
          // the sets for a session with no load in it — and the other three sit
          // under it. The grid of four equal cells read as a form.
          GlassSurface(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionLabel(
                  summary.volume == Mass.zero ? 'Sets' : 'Volume',
                  emphasis: LabelEmphasis.stat,
                ),
                const SizedBox(height: AppSpacing.xs),
                CountUp(
                  value: summary.volume == Mass.zero
                      ? summary.workingSets.toDouble()
                      : summary.volume.kilograms,
                  format: (n) => summary.volume == Mass.zero
                      ? '${n.round()}'
                      : Mass.kilograms(n).label(massUnit),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w300,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
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
                    if (summary.volume != Mass.zero)
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

class _MovementCard extends StatelessWidget {
  const _MovementCard({
    required this.exercise,
    required this.massUnit,
    required this.previous,
    required this.onOpenStats,
  });

  final SessionExercise exercise;

  /// From the name: the movement over time.
  final VoidCallback onOpenStats;
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
            Semantics(
              button: true,
              hint: 'Shows ${exercise.name} over time',
              onTap: onOpenStats,
              child: PressScale(
                haptic: false,
                onTap: onOpenStats,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        exercise.name,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
              ),
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

/// Where this session stands, as a pill at the top of the summary (14).
///
/// *Backing up…*, then **gone** once it has: a line that says "Backed up."
/// for as long as the screen is open is a line nobody needs. On a failure, the
/// reason and the one thing that fixes it. Signed out, *Saved on this phone.*
/// and nothing more — the account card's rule, that it reports and does not
/// sell. The words are [sessionBackupMessage]'s.
///
/// **Live.** Finish is a checkpoint, and the run it starts lands a couple of
/// seconds after this screen does, so the pill changes under the lifter's eyes.
class _BackupPill extends StatelessWidget {
  const _BackupPill({required this.hooks, required this.session});

  final BackupHooks hooks;
  final Session session;

  /// The message without the reassurance every state opens with: the pill is
  /// what backup is doing, and the session being on the phone is the summary's
  /// whole premise.
  static String _short(String text) {
    const saved = 'Saved on this phone. ';
    return text.startsWith(saved) ? text.substring(saved.length) : text;
  }

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
        final done = message.text == 'Backed up.';
        final action = switch (message.action) {
          BackupAction.retry when hooks.onRetry != null => (
            'Retry',
            hooks.onRetry,
          ),
          BackupAction.signIn when hooks.onSignIn != null => (
            'Sign in',
            hooks.onSignIn,
          ),
          _ => null,
        };
        final trouble =
            status.retrying ||
            status.state == BackupState.expired ||
            status.state == BackupState.failed;
        return AnimatedSwitcher(
          duration: AppMotion.base,
          child: done
              ? const SizedBox(key: ValueKey<String>('done'))
              : GlassSurface(
                  key: ValueKey<String>(message.text),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    action == null ? AppSpacing.md : AppSpacing.xs,
                    AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        trouble
                            ? Icons.cloud_off_outlined
                            : status.state == BackupState.running
                            ? Icons.cloud_upload_outlined
                            : Icons.smartphone_outlined,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xs,
                          ),
                          child: Text(
                            _short(message.text),
                            style: theme.textTheme.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (action case (final label, final onTap))
                        AppTextButton(
                          label: label,
                          onPressed: onTap,
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
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
