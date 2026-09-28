import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../data/exercise_lookup.dart';
import '../domain/session.dart';
import '../domain/workout_library.dart';
import 'exercise_picker_sheet.dart';

/// Builds a workout from scratch and saves it to the library.
///
/// The third way into the library, after adding a premade and saving a session
/// you just did. Ported from Liftio's `create-template.tsx`, and deliberately
/// the same two fields it had: a name and an ordered list of movements. There
/// is nothing else a saved workout holds — no sets, no weights — for the reason
/// on [SavedWorkout.movements].
///
/// Movements come from [ExercisePickerSheet], the same picker the active
/// session uses. That is worth more than it sounds: it means a workout built
/// here can only contain movements the session screen can also render with a
/// form image, and anything typed by hand arrives on exactly the same terms it
/// would mid-session.
class WorkoutBuilderScreen extends StatefulWidget {
  const WorkoutBuilderScreen({
    super.key,
    required this.library,
    required this.lookup,
    this.initialName,
    this.initialMovements = const <String>[],
  });

  final WorkoutLibrary library;
  final ExerciseLookup lookup;

  /// Pre-fills the name. Unused today; the save-a-session path writes straight
  /// to the library rather than coming through here, because a lifter who has
  /// just finished training should not be handed a form.
  final String? initialName;

  final List<String> initialMovements;

  @override
  State<WorkoutBuilderScreen> createState() => _WorkoutBuilderScreenState();
}

class _WorkoutBuilderScreenState extends State<WorkoutBuilderScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName ?? '',
  );
  late final List<String> _movements = <String>[...widget.initialMovements];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Both halves are required, and the button says so by being disabled rather
  /// than by rejecting the tap. A workout with no name cannot be found again;
  /// one with no movements starts an empty session, which is the state the
  /// library exists to get somebody out of.
  bool get _canSave =>
      !_saving && _name.text.trim().isNotEmpty && _movements.isNotEmpty;

  Future<void> _addMovement() async {
    final names = await ExercisePickerSheet.show(
      context,
      lookup: widget.lookup,
      room: SessionLimits.movements - _movements.length,
    );
    if (names == null) return;
    setState(
      () => _movements.addAll(<String>[
        for (final n in names)
          if (n.trim().isNotEmpty) n.trim(),
      ]),
    );
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final saved = await widget.library.save(
      // Exactly what they typed. The `(2)` suffix is for names the *app*
      // chose — silently renaming something somebody has just written is
      // worse than letting them have two of them. See [uniqueWorkoutName].
      name: _name.text.trim(),
      movements: _movements,
    );
    if (!mounted) return;
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('New workout'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionLabel('Name'),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Push day, Leg day, Upper body',
                ),
                // Rebuilds so the save button follows the field. Without it
                // the button stays disabled until something else calls
                // setState, which reads as the screen having hung.
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: <Widget>[
                  const Expanded(child: SectionLabel('Movements')),
                  Text(
                    '${_movements.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: _movements.isEmpty
                    ? Center(
                        child: Text(
                          'Nothing in it yet.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        // Order is the whole content of a workout beyond its
                        // names — a push day that opens on lateral raises is
                        // a different session — so it has to be changeable
                        // without deleting and re-adding.
                        buildDefaultDragHandles: false,
                        itemCount: _movements.length,
                        onReorder: (from, to) => setState(() {
                          final target = to > from ? to - 1 : to;
                          _movements.insert(target, _movements.removeAt(from));
                        }),
                        itemBuilder: (context, i) => Padding(
                          key: ValueKey<String>('$i-${_movements[i]}'),
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: AppCard(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.sm,
                            ),
                            child: Row(
                              children: <Widget>[
                                Text(
                                  '${i + 1}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Text(
                                    _movements[i],
                                    style: theme.textTheme.bodyMedium,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                AppIconButton(
                                  icon: Icons.close,
                                  onPressed: () =>
                                      setState(() => _movements.removeAt(i)),
                                  tooltip: 'Remove ${_movements[i]}',
                                  color: AppColors.textSecondary,
                                  visualDensity: VisualDensity.compact,
                                ),
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Padding(
                                    padding: EdgeInsets.only(
                                      left: AppSpacing.xs,
                                    ),
                                    child: Icon(
                                      Icons.drag_handle,
                                      size: 20,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
              AppOutlinedButton(
                onPressed: _movements.length >= SessionLimits.movements
                    ? null
                    : _addMovement,
                icon: Icons.add,
                label: 'Add movements',
                expand: true,
              ),
              const SizedBox(height: AppSpacing.sm),
              PrimaryButton(
                label: 'Save to library',
                onPressed: _canSave ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
