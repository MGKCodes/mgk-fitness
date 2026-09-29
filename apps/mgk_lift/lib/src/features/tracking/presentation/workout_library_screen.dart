import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../sync/presentation/backup_scheduler.dart';
import '../data/exercise_lookup.dart';
import '../domain/session.dart';
import '../domain/workout_library.dart';
import 'premade_library_sheet.dart';
import 'workout_editor_screen.dart';
import 'workout_preview_sheet.dart';

/// **Your workouts** — the lifter's library, and what a session starts from.
///
/// A screen, not the sheet it replaced. The sheet was reachable only from
/// inside an empty session — so browsing your own workouts started the clock
/// first — and it was a fixed 85% of the screen, half empty with three rows in
/// it. This is reached from Track as well, and does everything a library
/// should: preview, start, edit, duplicate, delete with Undo, build one, and
/// add the ready-made ones.
///
/// Pops with the workout the lifter chose to start, or null.
class WorkoutLibraryScreen extends StatefulWidget {
  const WorkoutLibraryScreen({
    super.key,
    required this.library,
    required this.lookup,
    this.log = const <Session>[],
    this.startLabel = 'Start',
    this.blockedReason,
    this.backup,
  });

  final WorkoutLibrary library;
  final ExerciseLookup lookup;

  /// For "last done", and the picker's recent movements.
  final List<Session> log;

  /// See [WorkoutPreviewSheet.startLabel].
  final String startLabel;

  /// See [WorkoutPreviewSheet.blockedReason].
  final String? blockedReason;

  /// Where backup stands, for the mark on a row not yet backed up. Null is a
  /// build with no server.
  final ValueListenable<BackupStatus>? backup;

  static Future<SavedWorkout?> open(
    BuildContext context, {
    required WorkoutLibrary library,
    required ExerciseLookup lookup,
    List<Session> log = const <Session>[],
    String startLabel = 'Start',
    String? blockedReason,
    ValueListenable<BackupStatus>? backup,
  }) => Navigator.of(context).push<SavedWorkout>(
    MaterialPageRoute<SavedWorkout>(
      builder: (_) => WorkoutLibraryScreen(
        library: library,
        lookup: lookup,
        log: log,
        startLabel: startLabel,
        blockedReason: blockedReason,
        backup: backup,
      ),
    ),
  );

  @override
  State<WorkoutLibraryScreen> createState() => _WorkoutLibraryScreenState();
}

class _WorkoutLibraryScreenState extends State<WorkoutLibraryScreen> {
  List<SavedWorkout>? _saved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await widget.library.all();
    if (!mounted) return;
    setState(() => _saved = saved);
  }

  void _say(String message, {String? action, VoidCallback? onAction}) =>
      AppToast.show(context, message, actionLabel: action, onAction: onAction);

  Future<void> _preview(SavedWorkout workout) async {
    final action = await WorkoutPreviewSheet.show(
      context,
      workout: workout,
      lastDone: lastDone(workout.id, widget.log),
      startLabel: widget.startLabel,
      blockedReason: widget.blockedReason,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case WorkoutAction.start:
        Navigator.of(context).pop(workout);
      case WorkoutAction.edit:
        await _edit(workout);
      case WorkoutAction.duplicate:
        final copy = await widget.library.save(
          name: uniqueWorkoutName(workout.name, <String>[
            for (final w in _saved ?? const <SavedWorkout>[]) w.name,
          ]),
          movements: workout.movements,
        );
        await _load();
        _say('${copy.name} added.');
      case WorkoutAction.delete:
        await _delete(workout);
    }
  }

  Future<void> _edit(SavedWorkout? workout) async {
    await Navigator.of(context).push<SavedWorkout>(
      MaterialPageRoute<SavedWorkout>(
        builder: (_) => WorkoutEditorScreen(
          library: widget.library,
          lookup: widget.lookup,
          workout: workout,
          log: widget.log,
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _delete(SavedWorkout workout) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete ${workout.name}?'),
        content: const Text(
          'The sessions you did from it stay in your log. Only the saved '
          'workout goes.',
        ),
        actions: <Widget>[
          AppTextButton(
            label: 'Keep it',
            onPressed: () => Navigator.of(dialog).pop(false),
          ),
          AppTextButton(
            label: 'Delete',
            onPressed: () => Navigator.of(dialog).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.library.remove(workout.id);
    await _load();
    if (!mounted) return;
    _say(
      '${workout.name} deleted.',
      action: 'Undo',
      onAction: () async {
        await widget.library.restore(workout.id);
        await _load();
      },
    );
  }

  Future<void> _browse() async {
    await PremadeLibrarySheet.show(context, library: widget.library);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saved = _saved;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Row(
                children: <Widget>[
                  AppIconButton(
                    icon: Icons.arrow_back,
                    tooltip: 'Back',
                    color: AppColors.textSecondary,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const SectionLabel('Library'),
                        Text(
                          'Your workouts',
                          style: theme.textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (saved) {
                // Null is "not read yet", empty is "you have none". A spinner
                // where the empty state belongs tells a new lifter to wait for
                // something that is never coming.
                null => const Center(child: CircularProgressIndicator()),
                final List<SavedWorkout> list when list.isEmpty => _Empty(
                  onBrowse: _browse,
                  onBuild: () => _edit(null),
                ),
                final List<SavedWorkout> list => ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  children: <Widget>[
                    for (final (i, workout) in list.indexed)
                      Entrance(
                        index: i,
                        child: _WorkoutRow(
                          workout: workout,
                          lastDone: lastDone(workout.id, widget.log),
                          onTap: () => _preview(workout),
                          backup: widget.backup,
                        ),
                      ),
                  ],
                ),
              },
            ),
          ],
        ),
      ),
      // In the bar slot so "Push deleted. Undo" sits above these rather than
      // over them.
      bottomNavigationBar: saved == null || saved.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: AppOutlinedButton(
                        onPressed: () => _edit(null),
                        icon: Icons.add,
                        label: 'Build one',
                        expand: true,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AppOutlinedButton(
                        onPressed: _browse,
                        icon: Icons.library_add_outlined,
                        label: 'Ready-made',
                        expand: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _WorkoutRow extends StatelessWidget {
  const _WorkoutRow({
    required this.workout,
    required this.lastDone,
    required this.onTap,
    this.backup,
  });

  final SavedWorkout workout;
  final DateTime? lastDone;
  final VoidCallback onTap;
  final ValueListenable<BackupStatus>? backup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    workout.name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    workoutLine(workout, lastDone),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    // The movements themselves: "6 movements" does not tell a
                    // Push from a Pull in a list of six saved workouts.
                    workout.movementNames.take(3).join(' · ') +
                        (workout.movementCount > 3
                            ? ' + ${workout.movementCount - 3} more'
                            : ''),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // A quiet mark on a workout this phone has and the server does
            // not — only for somebody signed in, for whom that is news. Signed
            // out, every row would carry it, which says nothing.
            if (backup case final backup?)
              ValueListenableBuilder<BackupStatus>(
                valueListenable: backup,
                builder: (context, status, _) =>
                    status.state == BackupState.signedOut ||
                        status.isBackedUp(workout.id)
                    ? const SizedBox.shrink()
                    : const Padding(
                        padding: EdgeInsets.only(right: AppSpacing.xs),
                        child: Tooltip(
                          message: 'Not backed up yet',
                          child: Icon(
                            Icons.cloud_off_outlined,
                            size: 16,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
              ),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Nothing saved yet — leading with the ready-made ones, because a blank
/// builder is the same blank page the library was meant to solve.
class _Empty extends StatelessWidget {
  const _Empty({required this.onBrowse, required this.onBuild});

  final VoidCallback onBrowse;
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            'Nothing saved yet',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Start from one of ours, build your own, or save a session once '
            'you have done it.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(label: 'Browse ready-made', onPressed: onBrowse),
          const SizedBox(height: AppSpacing.sm),
          AppOutlinedButton(
            label: 'Build one',
            onPressed: onBuild,
            expand: true,
          ),
        ],
      ),
    );
  }
}
