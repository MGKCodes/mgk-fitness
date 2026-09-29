import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/workout_library.dart';

/// What can be done with a saved workout from its preview.
enum WorkoutAction { start, edit, duplicate, delete }

/// One saved workout, looked at before anything is done with it: what is in
/// it, set by set, and **Start**.
///
/// A row in the library used to start its workout on a tap, with three names
/// and "+ 1 more" to go on. The preview shows the whole thing — every movement
/// with its sets and reps — because a lifter choosing between a heavy and a
/// light Push needs to see which is which before the clock starts.
class WorkoutPreviewSheet extends StatelessWidget {
  const WorkoutPreviewSheet({
    super.key,
    required this.workout,
    this.lastDone,
    this.startLabel = 'Start',
    this.blockedReason,
  });

  final SavedWorkout workout;
  final DateTime? lastDone;

  /// `Start`, or `Use this workout` when the preview was opened to fill a
  /// session that is already running.
  final String startLabel;

  /// Why Start is not available, or null when it is — a session already open
  /// is resumed, never overwritten, so this says so rather than hiding Start.
  final String? blockedReason;

  static Future<WorkoutAction?> show(
    BuildContext context, {
    required SavedWorkout workout,
    DateTime? lastDone,
    String startLabel = 'Start',
    String? blockedReason,
  }) => showModalBottomSheet<WorkoutAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    ),
    builder: (_) => WorkoutPreviewSheet(
      workout: workout,
      lastDone: lastDone,
      startLabel: startLabel,
      blockedReason: blockedReason,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: ConstrainedBox(
        // As tall as the workout, up to most of the screen — principle 1.
        constraints: BoxConstraints(maxHeight: height * 0.85),
        child: Padding(
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
              // The name scrolls with the movements, so a long name at a large
              // text size cannot push Start off the sheet.
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    Text(workout.name, style: theme.textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      workoutLine(workout, lastDone),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    for (final (i, m) in workout.movements.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                        ),
                        child: Row(
                          children: <Widget>[
                            // At least 24 wide, so the names line up; wider
                            // when the text is, rather than breaking "10" in two.
                            ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 24),
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  right: AppSpacing.xs,
                                ),
                                child: Text(
                                  '${i + 1}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                m.name,
                                style: theme.textTheme.bodyMedium,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              prescription(m),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                                fontFeatures: const <FontFeature>[
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: startLabel,
                onPressed: blockedReason != null
                    ? null
                    : () => Navigator.of(context).pop(WorkoutAction.start),
              ),
              if (blockedReason != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  blockedReason!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              // A wrap, not a row: at a large text size the three did not fit
              // across a small phone.
              Wrap(
                alignment: WrapAlignment.center,
                children: <Widget>[
                  AppTextButton(
                    label: 'Edit',
                    onPressed: () =>
                        Navigator.of(context).pop(WorkoutAction.edit),
                  ),
                  AppTextButton(
                    label: 'Duplicate',
                    onPressed: () =>
                        Navigator.of(context).pop(WorkoutAction.duplicate),
                  ),
                  AppTextButton(
                    label: 'Delete',
                    onPressed: () =>
                        Navigator.of(context).pop(WorkoutAction.delete),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `3 × 8`, or `3 sets` when there is no rep target.
String prescription(TemplateMovement m) => m.repTarget == null
    ? '${m.sets} ${m.sets == 1 ? 'set' : 'sets'}'
    : '${m.sets} × ${m.repTarget}';

/// `6 movements · 18 sets · last done 23 Sep`, the line under a workout's name.
String workoutLine(SavedWorkout w, DateTime? lastDone) => <String>[
  '${w.movementCount} ${w.movementCount == 1 ? 'movement' : 'movements'}',
  '${w.setCount} ${w.setCount == 1 ? 'set' : 'sets'}',
  lastDone == null ? 'not done yet' : 'last done ${_shortDate(lastDone)}',
].join(' · ');

String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
