import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../data/exercise_lookup.dart';
import '../domain/session.dart';
import '../domain/session_recorder.dart';
import 'exercise_card.dart';
import 'exercise_picker_sheet.dart';
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
  DateTime _now = DateTime.now();

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
    _clock = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

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
                name: _session.name,
                elapsed: _session.elapsedAt(_now),
                volumeKg: _session.volumeKg,
                massUnit: widget.massUnit,
                completedSets: _session.completedSets,
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
                                isCollapsed: _isCollapsed(exercise),
                                onToggleCollapsed: () =>
                                    _toggleCollapsed(exercise),
                                onAddSet: () => _apply(
                                  () => widget.recorder.addSet(exercise.id),
                                ),
                                onRemove: () => _apply(
                                  () => widget.recorder.removeExercise(
                                    exercise.id,
                                  ),
                                ),
                                onToggle: (set) => _apply(
                                  () => widget.recorder.updateSet(
                                    set.id,
                                    isCompleted: !set.isCompleted,
                                  ),
                                ),
                                onToggleWarmup: (set) => _apply(
                                  () => widget.recorder.updateSet(
                                    set.id,
                                    setType: set.isWarmup
                                        ? SetType.working
                                        : SetType.warmup,
                                  ),
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
                            child: TextButton(
                              onPressed: _confirmDiscard,
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.danger,
                              ),
                              child: const Text('Discard session'),
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

  /// Fills an empty session from a ready-made one.
  ///
  /// Adds the movements and stops there — no sets, no numbers. A template says
  /// what to do, not what to lift, and pre-filling weights would be the app
  /// asserting something only the lifter knows.
  Future<void> _useTemplate() async {
    final template = await TemplatePickerSheet.show(context);
    if (template == null) return;
    for (final name in template.exercises) {
      await _apply(() => widget.recorder.addExercise(name));
    }
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
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep going'),
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
    required this.name,
    required this.elapsed,
    required this.volumeKg,
    required this.massUnit,
    required this.completedSets,
    required this.canFinish,
    required this.onFinish,
  });

  final String name;
  final Duration elapsed;

  /// Canonical kilograms. Summed before rounding, then rendered once — adding
  /// rounded pounds and converting back is how a total drifts from its parts.
  final double volumeKg;

  final MassUnit massUnit;
  final int completedSets;
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
          Row(
            children: <Widget>[
              Expanded(
                child: StatBlock(label: 'Elapsed', value: _clock(elapsed)),
              ),
              Expanded(
                child: StatBlock(
                  label: 'Volume',
                  value: volumeKg == 0
                      ? '—'
                      : Mass.kilograms(volumeKg).label(massUnit),
                ),
              ),
              Expanded(
                child: StatBlock(label: 'Sets', value: '$completedSets'),
              ),
            ],
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
            PrimaryButton(label: 'Use a template', onPressed: onUseTemplate),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: onAdd,
              child: const Text('Add exercise'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: onDiscard,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.danger,
              ),
              child: const Text('Discard session'),
            ),
          ],
        ),
      ),
    );
  }
}
