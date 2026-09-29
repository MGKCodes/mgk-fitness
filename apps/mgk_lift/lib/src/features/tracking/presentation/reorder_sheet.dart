import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/session.dart';

/// The session's movements, in an order the lifter can drag.
///
/// Every app the 2026-09-29 research compared lets a lifter reorder mid-
/// workout — the bench is taken, so incline goes first — and Lift's recorder
/// has always been able to (`moveExercise`), with nothing on screen that
/// reached it.
///
/// A sheet rather than drag handles on the cards: the cards are tall, full of
/// fields, and scroll under the lifter's thumb, which is the wrong surface to
/// start a long-press drag on. Here each row is one line.
class ReorderSheet extends StatefulWidget {
  const ReorderSheet({super.key, required this.exercises});

  final List<SessionExercise> exercises;

  /// Returns the new order as movement ids, or null when nothing moved.
  static Future<List<String>?> show(
    BuildContext context, {
    required List<SessionExercise> exercises,
  }) => showGlassSheet<List<String>>(
    context: context,
    builder: (_) => ReorderSheet(exercises: exercises),
  );

  @override
  State<ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends State<ReorderSheet> {
  late final List<SessionExercise> _order = List.of(widget.exercises);

  bool get _moved {
    for (var i = 0; i < _order.length; i++) {
      if (_order[i].id != widget.exercises[i].id) return true;
    }
    return false;
  }

  void _onReorder(int from, int to) {
    setState(() {
      // ReorderableListView reports the slot *before* removal.
      final target = to > from ? to - 1 : to;
      final item = _order.removeAt(from);
      _order.insert(target, item);
    });
  }

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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SheetHandle(),
          Text('Reorder', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Drag a movement by its handle. Logged sets move with it.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              itemCount: _order.length,
              onReorder: _onReorder,
              proxyDecorator: (child, _, _) => Material(
                color: AppColors.elevated,
                borderRadius: AppRadius.cardAll,
                child: child,
              ),
              itemBuilder: (context, i) {
                final e = _order[i];
                final done = e.sets.where((s) => s.isCompleted).length;
                return Padding(
                  key: ValueKey<String>(e.id),
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadius.cardAll,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  e.name,
                                  style: theme.textTheme.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '$done of ${e.sets.length} '
                                  '${e.sets.length == 1 ? 'set' : 'sets'} done',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: Semantics(
                              label: 'Drag to move ${e.name}',
                              child: const Padding(
                                padding: EdgeInsets.all(AppSpacing.sm),
                                child: Icon(
                                  Icons.drag_handle,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.of(
              context,
            ).pop(_moved ? <String>[for (final e in _order) e.id] : null),
          ),
        ],
      ),
    );
  }
}
