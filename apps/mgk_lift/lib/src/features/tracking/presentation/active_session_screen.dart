import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../data/exercise_lookup.dart';
import '../domain/previous_performance.dart';
import '../domain/rest_timer.dart';
import '../../planning/domain/coach_planner.dart';
import '../../planning/domain/planned_movement.dart';
import '../../planning/presentation/swap_sheet.dart';
import '../domain/session.dart';
import '../domain/session_recorder.dart';
import 'exercise_card.dart';
import 'exercise_picker_sheet.dart';
import 'rest_bar.dart';
import 'template_picker_sheet.dart';

/// The screen you are looking at while standing at a rack.
///
/// Everything here is designed around one fact: **the lifter is between sets and
/// does not want to be here.** So the common path is a single tap on the tick —
/// weight and reps are already carried forward, and typing is the exception.
///
/// No spinner blocks a set being logged. Every write goes to the on-device
/// database and returns; the network is not consulted and cannot fail here.
class ActiveSessionScreen extends StatefulWidget {
  const ActiveSessionScreen({
    super.key,
    required this.recorder,
    required this.session,
    this.massUnit = MassUnit.kilograms,
    this.lookup,
    this.onFinished,
    this.planner,
    this.log = const <Session>[],
    this.onSwapped,
    this.startRestOnOpen = false,
    this.now,
  });

  final SessionRecorder recorder;

  /// The session as it stood when this screen opened. Kept fresh from here on.
  final Session session;

  /// What the lifter works in. Storage stays kilograms regardless — this only
  /// decides what the fields show and how a typed number is read.
  final MassUnit massUnit;

  /// The 266-movement catalogue, for form images and muscle groups. Injected so
  /// a test can pass a small one instead of loading the lot.
  final ExerciseLookup? lookup;

  /// Called after a session is finished or discarded, so the caller can reload.
  final VoidCallback? onFinished;

  /// The coach, for swapping a movement mid-session. Null hides the action.
  final CoachPlanner? planner;

  /// Finished sessions, so a suggested replacement's target can be derived from
  /// what this lifter has actually lifted.
  final List<Session> log;

  /// Reports a swap that was accepted, so the plan can record that they did
  /// something other than what it asked for. Without this the plan would go on
  /// claiming a movement they replaced.
  final void Function(String replaced, PlannedMovement with_)? onSwapped;

  /// Opens already resting. **For the preview harness only** — rest is never
  /// restored from disk, so a screenshot of the bar is otherwise unreachable
  /// without driving a tap.
  @visibleForTesting
  final bool startRestOnOpen;

  /// What "now" is, for the elapsed clock. Injected so a test or the preview
  /// harness can pin it — same convention as [PhotosSurface.now].
  ///
  /// **Without this the harness could not show this screen at all.** Its
  /// sessions start at a frozen `previewNow`, while the clock read the real
  /// one, so the header rendered the gap between the two: `307:25:40` and
  /// climbing by a day every day. A screenshot of the loudest number on the
  /// screen was therefore never reviewable, and got quietly worse with age.
  ///
  /// Null means the real clock, which is every case outside a test.
  final DateTime? now;

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  late Session _session = widget.session;
  late final ExerciseLookup _lookup = widget.lookup ?? ExerciseLookup();

  /// Ticks the elapsed clock. Display only — the duration is derived from
  /// `startedAt` when the session is finished, so a dropped tick costs a second
  /// on screen and nothing in the data.
  Timer? _clock;
  late DateTime _now = widget.now ?? DateTime.now();

  /// The rest since the last set was ticked. Null when nothing is resting —
  /// either none has started, or the lifter dismissed it.
  ///
  /// Held on the screen rather than in the session, because rest is not part of
  /// what happened: it is not written to the database, and reopening a recovered
  /// session should not resume a countdown from an hour ago.
  RestTimer? _rest;

  /// Whether the buzz for this rest has already gone off, so a timer sitting at
  /// zero does not vibrate once a second until it is dismissed.
  bool _restAlerted = false;

  /// How long the next rest runs for. Starts at the default and follows the
  /// lifter's adjustments — see [_adjustRest].
  Duration _restLength = RestTimer.defaultRest;

  /// Exercises the lifter has opened or closed **by hand**, keyed by id.
  ///
  /// Only the overrides are stored, not the state of every card. A finished
  /// movement collapses on its own; this records the cases where the lifter
  /// disagreed, so ticking a set elsewhere cannot silently shut a card they
  /// deliberately opened.
  final Map<String, bool> _expanded = <String, bool>{};

  /// Collapsed unless the lifter said otherwise. See [_expanded].
  bool _isCollapsed(SessionExercise e) => !(_expanded[e.id] ?? !e.isComplete);

  void _toggleCollapsed(SessionExercise e) =>
      setState(() => _expanded[e.id] = _isCollapsed(e));

  @override
  void initState() {
    super.initState();
    if (widget.startRestOnOpen) _startRest();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      // A pinned clock stays pinned. Ticking it would walk the elapsed time
      // forward from the frozen start and undo the point of injecting it.
      setState(() => _now = widget.now ?? DateTime.now());
      _alertIfRestOver();
    });
  }

  /// Buzzes once, the moment rest runs out.
  ///
  /// Haptics rather than a sound or a notification: a gym is loud, the phone is
  /// usually face-down on a bench, and a buzz is the one signal that survives
  /// both without needing a permission prompt.
  ///
  /// **This only fires while the app is in the foreground.** A backgrounded
  /// Flutter app has no ticker, so a lifter who pockets their phone gets the
  /// right time when they look — see [RestTimer] — but no buzz. Doing that
  /// properly needs a scheduled local notification, which is a plugin and a
  /// permission, and is not here yet.
  void _alertIfRestOver() {
    final rest = _rest;
    if (rest == null || _restAlerted || !rest.isDoneAt(_now)) return;
    _restAlerted = true;
    // The one occasion in this app that earns AppHaptics' stated exception:
    // something the app did on its own, for somebody who cannot look. The
    // vocabulary existed and this call site predated it — it was the only raw
    // HapticFeedback left in either app.
    unawaited(AppHaptics.milestone());
  }

  /// Starts rest, from now.
  ///
  /// Called when a set is ticked *complete* — un-ticking one is a correction to
  /// the log, not the end of a set, and starting a countdown for it would be
  /// the app misreading what happened.
  void _startRest() {
    setState(() {
      // From the same clock the bar is read against. Starting rest at the real
      // now while `_now` is pinned would show a countdown that has already run
      // out by days, which is how a pinned clock leaks into a second surface.
      _rest = RestTimer(startedAt: _now, duration: _restLength);
      _restAlerted = false;
    });
  }

  /// Adjusts the running rest, and remembers the new length for the next one.
  ///
  /// Both, deliberately. Someone adding thirty seconds between every set means
  /// it, and asking again each time is the app refusing to learn something it
  /// has been told four times. It is kept for the session only — persisting it,
  /// and having a different default per movement, both want a settings column
  /// that does not exist yet.
  void _adjustRest(Duration by) {
    final rest = _rest;
    if (rest == null) return;
    setState(() {
      _rest = rest.extendedBy(by, _now);
      final next = _restLength + by;
      _restLength = next < _minRest ? _minRest : next;
      // Lengthening a finished rest makes it unfinished, so the buzz is owed
      // again.
      if (!_rest!.isDoneAt(_now)) _restAlerted = false;
    });
  }

  /// Below this, rest is not a rest. Stops repeated −30s taps from setting the
  /// remembered length to zero and silently disabling the feature.
  static const Duration _minRest = Duration(seconds: 15);

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _apply(Future<Session> Function() change) async {
    final updated = await change();
    if (!mounted) return;
    setState(() => _session = updated);
  }

  @override
  Widget build(BuildContext context) {
    final canFinish = _session.completedSets > 0;

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
                name: _session.name,
                elapsed: _session.elapsedAt(_now),
                volumeKg: _session.volumeKg,
                massUnit: widget.massUnit,
                completedSets: _session.completedSets,
                movements: _session.exercises.length,
                canFinish: canFinish,
                onFinish: _finish,
              ),
              Expanded(
                child: _session.exercises.isEmpty
                    ? _EmptyState(
                        onAdd: _addExercise,
                        onUseTemplate: _useTemplate,
                        onDiscard: _confirmDiscard,
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.sm,
                          AppSpacing.lg,
                          AppSpacing.xxl,
                        ),
                        children: <Widget>[
                          for (final exercise in _session.exercises)
                            // Animated, because ticking the last set collapses
                            // the card under the lifter's finger. A jump cut
                            // there reads as the card having been deleted; the
                            // transition shows it folding into its summary.
                            AnimatedSize(
                              key: ValueKey<String>(exercise.id),
                              duration: AppMotion.fast,
                              curve: AppMotion.standard,
                              alignment: Alignment.topCenter,
                              child: ExerciseCard(
                                exercise: exercise,
                                catalogue: _lookup.find(exercise.name),
                                massUnit: widget.massUnit,
                                // Excludes the session in progress, or the
                                // first set logged today would immediately
                                // become "last time".
                                previous: PreviousPerformance.of(
                                  widget.log,
                                  exercise.name,
                                  excludeSessionId: _session.id,
                                ),
                                isCollapsed: _isCollapsed(exercise),
                                onToggleCollapsed: () =>
                                    _toggleCollapsed(exercise),
                                onSwap: widget.planner == null
                                    ? null
                                    : () => _swap(exercise),
                                onAddSet: () => _apply(
                                  () => widget.recorder.addSet(exercise.id),
                                ),
                                onRemove: () => _apply(
                                  () => widget.recorder.removeExercise(
                                    exercise.id,
                                  ),
                                ),
                                onToggle: (set) {
                                  // Only on completion. Un-ticking is a
                                  // correction to the log, not the end of a
                                  // set.
                                  if (!set.isCompleted) _startRest();
                                  unawaited(
                                    _apply(
                                      () => widget.recorder.updateSet(
                                        set.id,
                                        isCompleted: !set.isCompleted,
                                      ),
                                    ),
                                  );
                                },
                                onCycleSetType: (set) => _apply(
                                  () => widget.recorder.updateSet(
                                    set.id,
                                    setType: set.setType.next,
                                  ),
                                ),
                                onRemoveSet: (set) => _apply(
                                  () => widget.recorder.removeSet(set.id),
                                ),
                                onEdit: (set, reps, weight) => _apply(
                                  () => widget.recorder.updateSet(
                                    set.id,
                                    reps: reps,
                                    weightKg: weight,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: AppSpacing.sm),
                          OutlinedButton.icon(
                            onPressed: _addExercise,
                            icon: const Icon(Icons.add),
                            label: const Text('Add exercise'),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          // Destructive, so it sits at the bottom of the list
                          // rather than in the chrome — you have to go looking
                          // for it, and you pass everything you would lose on
                          // the way.
                          Center(
                            child: AppTextButton(
                              label: 'Discard session',
                              onPressed: _confirmDiscard,
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.danger,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),

              // Below the list, above the system inset. Takes a strip rather
              // than covering anything: the log stays reachable while resting,
              // which is exactly when someone notices they typed 8 instead of 6.
              if (_rest != null)
                RestBar(
                  timer: _rest!,
                  now: _now,
                  onAdjust: _adjustRest,
                  onDismiss: () => setState(() => _rest = null),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Fills an empty session from a ready-made one.
  ///
  /// Adds the movements and stops there — no sets, no numbers. A template says
  /// what to do, not what to lift, and pre-filling weights would be the app
  /// asserting something only the lifter knows.
  ///
  /// **A planned session is different, and deliberately so.** `SessionFromPlan`
  /// does fill in the weights, because those came from this lifter's own logged
  /// sets rather than from a list written for nobody in particular — and where
  /// the coach could not derive one, it leaves the field blank exactly as this
  /// does. Both rules hold; they are about different things.
  Future<void> _useTemplate() async {
    final template = await TemplatePickerSheet.show(context);
    if (template == null) return;
    for (final name in template.exercises) {
      await _apply(() => widget.recorder.addExercise(name));
    }
  }

  /// Asks the coach for something else, and applies what the lifter picks.
  ///
  /// The old movement is removed and the new one added in its place, with its
  /// sets seeded the same way a planned session's are — reps in, weight in when
  /// the coach could derive one and blank when it could not.
  Future<void> _swap(SessionExercise exercise) async {
    final planner = widget.planner;
    if (planner == null) return;

    final choice = await SwapSheet.show(
      context,
      planner: planner,
      session: _session,
      movement: exercise.name,
      log: widget.log,
      unit: widget.massUnit,
    );
    if (choice == null || !mounted) return;

    await _apply(() => widget.recorder.removeExercise(exercise.id));
    await _apply(() => widget.recorder.addExercise(choice.name));

    final added = _session.exercises.last;
    for (var i = 0; i < choice.sets; i++) {
      final set = i < added.sets.length
          ? added.sets[i]
          : (await widget.recorder.addSet(added.id)).exercises
                .firstWhere((SessionExercise e) => e.id == added.id)
                .sets
                .last;
      await _apply(
        () => widget.recorder.updateSet(
          set.id,
          reps: choice.reps,
          weightKg: choice.target?.kilograms,
        ),
      );
    }

    widget.onSwapped?.call(exercise.name, choice);
  }

  Future<void> _addExercise() async {
    final name = await ExercisePickerSheet.show(context, lookup: _lookup);
    if (name == null || name.trim().isEmpty) return;
    await _apply(() => widget.recorder.addExercise(name.trim()));
  }

  Future<void> _finish() async {
    await widget.recorder.finish();
    if (!mounted) return;
    widget.onFinished?.call();
    Navigator.of(context).pop();
  }

  Future<void> _confirmDiscard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Discard this session?'),
        content: const Text(
          'Everything you have logged in it is deleted. This cannot be undone.',
        ),
        actions: <Widget>[
          AppTextButton(
            label: 'Keep going',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.recorder.discard();
    if (!mounted) return;
    widget.onFinished?.call();
    Navigator.of(context).pop();
  }
}

/// Session name, the three numbers, and **Finish**.
///
/// Finish lives here rather than as a full-width slab pinned to the bottom. That
/// slab read as the screen's purpose — the thing you came to press — when
/// actually it is what you do once, at the end, after logging everything. It
/// also fought the nav bar for the same edge. Up here it is present, reachable
/// with a thumb, and clearly a session-level action rather than a set-level one.
class _Header extends StatelessWidget {
  const _Header({
    required this.onBack,
    required this.name,
    required this.elapsed,
    required this.volumeKg,
    required this.massUnit,
    required this.completedSets,
    required this.movements,
    required this.canFinish,
    required this.onFinish,
  });

  /// Leaves the session running and goes back.
  ///
  /// **The only way off this screen used to be Finish or Discard**, and Finish
  /// is disabled until a set is ticked — so a lifter who opened a session by
  /// accident had to find "Discard session" at the foot of a list to escape.
  /// The Android system back gesture worked and nothing on screen said so.
  ///
  /// Backing out is safe and non-destructive: every change is already
  /// persisted, the session stays open, and Track offers to resume it. That is
  /// why this needs no confirmation, and why it is an arrow rather than a
  /// dialog.
  final VoidCallback onBack;

  final String name;
  final Duration elapsed;

  /// Canonical kilograms. Summed before rounding, then rendered once — adding
  /// rounded pounds and converting back is how a total drifts from its parts.
  final double volumeKg;

  final MassUnit massUnit;
  final int completedSets;

  /// How many movements are in the session. The only figure here that is not
  /// purely retrospective — it is the one a lifter reads to judge what is
  /// left rather than what is done.
  final int movements;

  final bool canFinish;
  final VoidCallback onFinish;

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
                tooltip: 'Back — the session stays open',
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
                    const SectionLabel('In progress'),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: theme.textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton(
                // Nothing ticked is not a session. Finishing would put an empty
                // row in the log and an empty card in the cross-app feed.
                onPressed: canFinish ? onFinish : null,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                ),
                child: const Text('Finish'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // **A card, not a strip.** These three sat directly on the
          // background under the title, and read as a compressed row of
          // numbers rather than as the session's state — nothing grouped them,
          // so they competed with the movement cards below instead of
          // introducing them. On its own ground the block says "this is the
          // session so far", which is what it is.
          //
          // Movements joins them because three figures in a card looks like a
          // card missing one, and because it is the figure that answers "how
          // much is left" — the other three only say what has happened.
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: StatBlock(
                    label: 'Elapsed',
                    value: _clock(elapsed),
                    // Crosses an hour and gains two characters. A Text in a
                    // bounded Expanded clips silently, so the session would
                    // simply appear to lose its hours.
                    shrinkToFit: true,
                  ),
                ),
                Expanded(
                  child: StatBlock(
                    label: 'Volume',
                    value: volumeKg == 0
                        ? '—'
                        : Mass.kilograms(volumeKg).label(massUnit),
                    shrinkToFit: true,
                  ),
                ),
                Expanded(
                  child: StatBlock(
                    label: 'Sets',
                    value: '$completedSets',
                    shrinkToFit: true,
                  ),
                ),
                Expanded(
                  child: StatBlock(
                    label: 'Movements',
                    value: '$movements',
                    shrinkToFit: true,
                  ),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onAdd,
    required this.onUseTemplate,
    required this.onDiscard,
  });

  final VoidCallback onAdd;

  /// Fills the session from a ready-made one. The first session is the hardest
  /// — a blank card list asks someone to remember what a push day is before
  /// they can log anything.
  final VoidCallback onUseTemplate;

  /// Discard has to be reachable **here too**, not only from the populated
  /// list. Without it, a session started by accident had no exit: Finish is
  /// disabled with nothing logged, and backing out leaves it open forever, so
  /// Track then offers to resume a session that never happened.
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'The clock is running',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Add the first movement when you get to it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            // **Adding a movement is the primary, not the template picker.**
            // These were the other way round, which made the loudest action on
            // a blank session the one the "Lift templates are the coach's
            // grounding layer, not a user-facing library" decision says should
            // not be a user-facing library at all. Loudness is the half of that
            // decision this screen owns; whether the picker survives is item 3
            // of docs/roadmap.md and is not settled here.
            PrimaryButton(label: 'Add exercise', onPressed: onAdd),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: onUseTemplate,
              child: const Text('Use a template'),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextButton(
              label: 'Discard session',
              onPressed: onDiscard,
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            ),
          ],
        ),
      ),
    );
  }
}
