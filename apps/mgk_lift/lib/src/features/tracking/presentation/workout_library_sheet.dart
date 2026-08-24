import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../data/exercise_lookup.dart';
import '../domain/workout_library.dart';
import 'premade_library_sheet.dart';
import 'workout_builder_screen.dart';

/// **Your workouts** — the library, and the thing a session is started from.
///
/// Replaces `Use a template` in the empty state of a session. The action there
/// used to open the fifteen app-provided premades and tip one into the blank
/// session; it now opens this, which lists what *this lifter* has saved. The
/// premades are still reachable — one tap further in, as something you add to
/// this list rather than something you start from.
///
/// Three ways in, all of them arriving at the same rows:
///
///   * **Add a ready-made one** — [PremadeLibrarySheet], the fifteen and the
///     eight splits.
///   * **Build one** — [WorkoutBuilderScreen], a name and movements off the
///     266-entry catalogue.
///   * **Save the one you just did** — from the active session, which is the
///     path that needs no decision in advance and is therefore the one most
///     people will use.
///
/// The empty state leads with the first of those. Somebody who has just opened
/// a tracker has nothing to save and no idea what to build, which is the
/// empty-state problem the premades were ported for in the first place.
class WorkoutLibrarySheet extends StatefulWidget {
  const WorkoutLibrarySheet({
    super.key,
    required this.library,
    required this.lookup,
  });

  final WorkoutLibrary library;

  /// The 266-movement catalogue, for the builder's search. Passed down rather
  /// than constructed here so a test can hand over a small one.
  final ExerciseLookup lookup;

  /// Returns the workout to start, or null if the sheet was dismissed without
  /// picking one — including when it was only used to add or build something.
  static Future<SavedWorkout?> show(
    BuildContext context, {
    required WorkoutLibrary library,
    required ExerciseLookup lookup,
  }) {
    return showModalBottomSheet<SavedWorkout>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WorkoutLibrarySheet(library: library, lookup: lookup),
    );
  }

  @override
  State<WorkoutLibrarySheet> createState() => _WorkoutLibrarySheetState();
}

class _WorkoutLibrarySheetState extends State<WorkoutLibrarySheet> {
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

  Future<void> _addFromPremades() async {
    await PremadeLibrarySheet.show(context, library: widget.library);
    if (!mounted) return;
    // Reload unconditionally rather than on the returned count. The sheet can
    // be closed by the system back gesture, which reports nothing, and a
    // library that has silently not refreshed is worse than one extra read.
    await _load();
  }

  Future<void> _build() async {
    final built = await Navigator.of(context).push<SavedWorkout>(
      MaterialPageRoute<SavedWorkout>(
        builder: (_) => WorkoutBuilderScreen(
          library: widget.library,
          lookup: widget.lookup,
        ),
      ),
    );
    if (!mounted || built == null) return;
    await _load();
  }

  Future<void> _confirmRemove(SavedWorkout workout) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete ${workout.name}?'),
        content: const Text(
          'The sessions you did from it stay in your log. Only the saved '
          'workout goes.',
        ),
        actions: <Widget>[
          AppTextButton(
            label: 'Keep it',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.library.remove(workout.id);
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final saved = _saved;

    return SizedBox(
      height: media.size.height * 0.85,
      child: GlassSurface(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SheetHandle(),
            const SectionLabel('Your workouts'),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Pick one to fill this session. Everything is editable once '
              'it is in.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: switch (saved) {
                // Null is "not read yet", empty is "you have none". They look
                // nothing alike and must not share a widget — a spinner where
                // the empty state belongs tells a new lifter to wait for
                // something that is never coming.
                null => const Center(child: CircularProgressIndicator()),
                final List<SavedWorkout> list when list.isEmpty => _Empty(
                  onAddFromPremades: _addFromPremades,
                  onBuild: _build,
                ),
                final List<SavedWorkout> list => ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                  children: <Widget>[
                    for (final workout in list)
                      _SavedRow(
                        workout: workout,
                        onStart: () => Navigator.of(context).pop(workout),
                        onDelete: () => _confirmRemove(workout),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: _addFromPremades,
                      icon: const Icon(Icons.library_add_outlined),
                      label: const Text('Add a ready-made one'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: _build,
                      icon: const Icon(Icons.add),
                      label: const Text('Build one'),
                    ),
                  ],
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Nothing saved yet.
///
/// Leads with the premades rather than the builder, because a blank builder is
/// the same blank page the library was meant to solve. Building your own is
/// there for the lifter who already knows what they want, which is not the
/// person this state exists for.
class _Empty extends StatelessWidget {
  const _Empty({required this.onAddFromPremades, required this.onBuild});

  final VoidCallback onAddFromPremades;
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Nothing saved yet',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Start from one of ours, build your own, or save a session '
              'once you have done it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Add a ready-made one',
              onPressed: onAddFromPremades,
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(onPressed: onBuild, child: const Text('Build one')),
          ],
        ),
      ),
    );
  }
}

/// One saved workout: tap the card to start it, the bin to delete it.
class _SavedRow extends StatelessWidget {
  const _SavedRow({
    required this.workout,
    required this.onStart,
    required this.onDelete,
  });

  final SavedWorkout workout;
  final VoidCallback onStart;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = workout.movementCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onStart,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    workout.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // The movements themselves, not a count on its own.
                    // "6 movements" is not enough to tell a Push from a Pull
                    // in a list of six saved workouts.
                    count == 0
                        ? 'No movements yet'
                        : workout.movements.take(3).join(' · ') +
                              (count > 3 ? ' + ${count - 3} more' : ''),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            AppIconButton(
              icon: Icons.delete_outline,
              onPressed: onDelete,
              tooltip: 'Delete ${workout.name}',
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
