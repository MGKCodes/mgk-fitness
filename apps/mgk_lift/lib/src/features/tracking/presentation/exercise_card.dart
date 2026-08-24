import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../domain/exercise.dart';
import '../domain/session.dart';
import 'exercise_thumb.dart';

/// One movement in the running session.
///
/// The first version of this was a name and a delete icon over two unlabelled
/// number boxes. It worked and looked like a spreadsheet. Three things fixed
/// that, and each is doing a job rather than decorating:
///
/// 1. **The form image.** Every catalogue movement ships with a start/end pair;
///    the start frame makes a card recognisable at a glance mid-set, when
///    nobody is reading.
/// 2. **`Chest · Barbell` under the name.** A bare "Bench press" tells a lifter
///    nothing they did not already know. The muscle group and the loading tell
///    them why it is in today's session.
/// 3. **Column headers instead of per-field suffixes.** `SET / KG / REPS` once
///    at the top lets the rows be bare numbers, which is what makes a long
///    exercise scannable — and it is what every serious tracker converged on.
///
/// ## Collapsing
///
/// Expanded, a card with three sets is around 350 logical pixels tall. A
/// six-movement template is therefore two thousand pixels of scrolling, and by
/// the fourth movement the one you are actually on is off screen — the worst
/// possible outcome for a screen used between sets.
///
/// So a movement whose sets are all ticked collapses to one line. What is left
/// is the record of what you did, which is all a finished movement owes you; the
/// space goes to the one you are on. Tapping it opens it again, because
/// "finished" is the app's guess and the lifter may want another set.
class ExerciseCard extends StatelessWidget {
  const ExerciseCard({
    super.key,
    required this.exercise,
    required this.catalogue,
    required this.massUnit,
    required this.onAddSet,
    required this.onRemove,
    required this.onToggle,
    required this.onEdit,
    this.onCycleSetType,
    this.onRemoveSet,
    this.onSwap,
    this.isCollapsed = false,
    this.onToggleCollapsed,
  });

  final SessionExercise exercise;

  /// The catalogue entry, when this movement is one of the 266 that ship. Null
  /// for something the lifter typed themselves, which is a first-class case:
  /// the card simply carries no image and no subtitle.
  final Exercise? catalogue;

  final MassUnit massUnit;
  final VoidCallback onAddSet;
  final VoidCallback onRemove;
  final void Function(SessionSet set) onToggle;
  final void Function(SessionSet set, int? reps, double? weightKg) onEdit;

  /// Switches a set between working and warm-up. Null leaves the markers
  /// read-only.
  /// Advances a set to the next [SetType]. Null makes the marker read-only,
  /// which is right for anything showing a finished session.
  final void Function(SessionSet set)? onCycleSetType;

  /// Removes one set. Null hides the gesture entirely rather than leaving a
  /// swipe that springs back — the same absent-rather-than-inert rule the
  /// coach mark follows.
  final void Function(SessionSet set)? onRemoveSet;

  /// Asks the coach for something else instead of this movement. **Null hides
  /// the action entirely** rather than showing one that opens a sheet with
  /// nothing behind it — there is no coach in a free or offline build.
  final VoidCallback? onSwap;

  /// Shows the one-line summary instead of the set rows. Decided by the screen,
  /// not here, so the lifter's manual expand survives a rebuild.
  final bool isCollapsed;

  /// Null leaves the card permanently expanded — the right behaviour for a
  /// caller that has no state to remember the toggle in.
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = exercise.topSet;

    if (isCollapsed) {
      return _CollapsedCard(
        exercise: exercise,
        massUnit: massUnit,
        onTap: onToggleCollapsed,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                ExerciseThumb(asset: catalogue?.startImage),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        exercise.name,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // The best line available: what it trains, or — for a
                        // movement they typed — what they have done on it.
                        catalogue?.subtitle ??
                            (top == null
                                ? 'Your own movement'
                                : 'Best today · ${Mass.kilograms(top.weightKg).label(massUnit)} × ${top.reps}'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onToggleCollapsed != null && exercise.sets.isNotEmpty)
                  AppIconButton(
                    onPressed: onToggleCollapsed,
                    icon: Icons.expand_less,
                    size: 20,
                    color: AppColors.textTertiary,
                    tooltip: 'Collapse ${exercise.name}',
                    visualDensity: VisualDensity.compact,
                  ),
                if (onSwap != null)
                  AppIconButton(
                    onPressed: onSwap,
                    icon: Icons.swap_horiz,
                    size: 18,
                    color: AppColors.textTertiary,
                    tooltip: 'Swap this out',
                    visualDensity: VisualDensity.compact,
                  ),
                AppIconButton(
                  onPressed: onRemove,
                  icon: Icons.close,
                  size: 18,
                  color: AppColors.textTertiary,
                  tooltip: 'Remove ${exercise.name}',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (exercise.sets.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              _ColumnHeaders(massUnit: massUnit),
              const SizedBox(height: AppSpacing.xs),
              for (final set in exercise.sets)
                if (onRemoveSet == null)
                  SetRow(
                    set: set,
                    massUnit: massUnit,
                    onToggle: () => onToggle(set),
                    onEdit: (reps, weight) => onEdit(set, reps, weight),
                    onCycleSetType: onCycleSetType == null
                        ? null
                        : () => onCycleSetType!(set),
                  )
                else
                  // **Swipe to remove, which is how the shipped app did it.**
                  // The row is already four controls wide — a marker, two
                  // number fields and a tick — and a fifth would have to steal
                  // width from the numbers, which are the point of the row.
                  //
                  // End-to-start only. A set is removed by pulling it away, and
                  // a gesture that fires in both directions on a row this dense
                  // goes off by accident while scrolling a long session.
                  //
                  // **Known limit, and it did not survive the port intact.**
                  // Liftio wrapped the same row in ReanimatedSwipeable and the
                  // whole row was draggable, because React Native's TextInput
                  // does not claim a horizontal pan. Flutter's TextField does,
                  // for text selection, so a drag started over the weight or
                  // reps field never reaches this Dismissible — proven by a
                  // test, and true under a real thumb for the same reason. The
                  // reliable start zone is the marker column at the leading
                  // edge. Starting over the tick at the trailing edge hangs
                  // pumpAndSettle outright, which is PressScale and Dismissible
                  // interacting and is not understood yet.
                  //
                  // So this is usable but narrower than it looks, and it has
                  // NOT been tried on a phone. If it proves fiddly there, the
                  // fallback is a long-press on the marker rather than a wider
                  // swipe, because there is no neutral width on this row to
                  // widen into.
                  Dismissible(
                    key: ValueKey<String>(set.id),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => onRemoveSet!(set),
                    background: const _RemoveSetBackground(),
                    child: SetRow(
                      set: set,
                      massUnit: massUnit,
                      onToggle: () => onToggle(set),
                      onEdit: (reps, weight) => onEdit(set, reps, weight),
                      onCycleSetType: onCycleSetType == null
                          ? null
                          : () => onCycleSetType!(set),
                    ),
                  ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAddSet,
                icon: const Icon(Icons.add, size: 16),
                label: Text(
                  exercise.sets.isEmpty ? 'Add first set' : 'Add set',
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A finished movement, in one line: what it was, and what you did on it.
///
/// Roughly a sixth the height of the expanded card. See [ExerciseCard] for why
/// that matters mid-session.
class _CollapsedCard extends StatelessWidget {
  const _CollapsedCard({
    required this.exercise,
    required this.massUnit,
    required this.onTap,
  });

  final SessionExercise exercise;
  final MassUnit massUnit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.check_circle, size: 18, color: AppColors.success),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                exercise.name,
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              exerciseSummary(exercise, massUnit),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(
              Icons.expand_more,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// `3 sets · 85 kg × 6` — the count, and the best of them.
///
/// Counts **working** sets, so a collapsed card agrees with the session header
/// and with Profile rather than being a fourth opinion on what a set is. A
/// movement of nothing but warm-ups therefore has none, and says so instead of
/// reading `0 sets`.
String exerciseSummary(SessionExercise exercise, MassUnit unit) {
  final working = exercise.workingSets.toList();
  if (working.isEmpty) return 'Warm-up only';
  final count = working.length == 1 ? '1 set' : '${working.length} sets';
  final top = exercise.topSet!;
  return '$count · ${Mass.kilograms(top.weightKg).label(unit)} × ${top.reps}';
}

/// `SET · KG · REPS` once per exercise, so the rows below can be bare numbers.
class _ColumnHeaders extends StatelessWidget {
  const _ColumnHeaders({required this.massUnit});

  final MassUnit massUnit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const SizedBox(
          width: 28,
          child: SectionLabel('Set', emphasis: LabelEmphasis.stat),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: SectionLabel(
            massUnit.suffix,
            emphasis: LabelEmphasis.stat,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        const Expanded(
          child: SectionLabel(
            'Reps',
            emphasis: LabelEmphasis.stat,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: 44),
      ],
    );
  }
}

/// What shows behind a set row as it is pulled away.
///
/// Danger-coloured and captioned. A bare red panel says something destructive
/// is about to happen without saying what, and on a screen where the adjacent
/// gesture edits a number, "what" is the part worth spelling out.
class _RemoveSetBackground extends StatelessWidget {
  const _RemoveSetBackground();

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.danger,
      borderRadius: BorderRadius.circular(AppRadius.chip),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Remove',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        const Icon(
          Icons.delete_outline,
          size: 18,
          color: AppColors.textPrimary,
        ),
      ],
    ),
  );
}

/// One working set. The tick is the primary control: weight and reps are
/// already carried forward, so the common path between sets is a single tap.
class SetRow extends StatelessWidget {
  const SetRow({
    super.key,
    required this.set,
    required this.massUnit,
    required this.onToggle,
    required this.onEdit,
    this.onCycleSetType,
  });

  final SessionSet set;
  final MassUnit massUnit;
  final VoidCallback onToggle;

  /// Advances the set to the next [SetType]. Null makes the marker read-only,
  /// which is right for anything showing a finished session.
  final VoidCallback? onCycleSetType;

  /// Reports the weight back in **kilograms**, whatever the lifter typed.
  /// Conversion happens here, the one point where a typed number becomes a
  /// stored one, so nothing below the UI ever sees a pound.
  final void Function(int? reps, double? weightKg) onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = set.isCompleted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // A completed set recedes: it is done, and the eye should go to the
          // one that is not.
          color: done ? AppColors.elevated : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: 2,
          ),
          child: Row(
            children: <Widget>[
              // `W` rather than a number for a warm-up, and tapping it toggles.
              //
              // Without the marker the screen contradicts itself: a warm-up is
              // ticked like any other set but counts toward neither the volume
              // nor the set count, so a lifter sees four ticks above a header
              // reading three and has no way to tell which one was discounted.
              SizedBox(
                width: 28,
                child: InkWell(
                  onTap: onCycleSetType,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  child: Tooltip(
                    message: 'Mark this as ${set.setType.next.label}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(
                        set.setType.marker ?? '${set.setNumber}',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textTertiary,
                          // Bold for anything that is not an ordinary working
                          // set, so a marked set is findable by weight rather
                          // than by reading each letter.
                          fontWeight: set.setType == SetType.working
                              ? FontWeight.w400
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _NumberField(
                  value: set.weightKg == 0
                      ? ''
                      : _trim(
                          Mass.kilograms(set.weightKg).displayValue(massUnit),
                        ),
                  onChanged: (v) => onEdit(
                    null,
                    Mass.inUnit(double.tryParse(v) ?? 0, massUnit).kilograms,
                  ),
                  done: done,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _NumberField(
                  value: set.reps == 0 ? '' : '${set.reps}',
                  onChanged: (v) => onEdit(int.tryParse(v) ?? 0, null),
                  done: done,
                ),
              ),
              SizedBox(
                width: 44,
                child: AppIconButton(
                  onPressed: onToggle,
                  icon: done ? Icons.check_circle : Icons.circle_outlined,
                  size: 24,
                  color: done ? AppColors.success : AppColors.textTertiary,
                  tooltip: done ? 'Mark not done' : 'Mark done',
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : '$v';
}

/// A bare number. No suffix and no label — the column header says what it is,
/// which is what lets the row stay this quiet.
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.value,
    required this.onChanged,
    required this.done,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool done;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    // Only when the value changed underneath us and the field is not being
    // typed into — otherwise the cursor jumps mid-entry.
    if (widget.value != _controller.text && !_focus.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: widget.done ? AppColors.textPrimary : AppColors.textSecondary,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.bg,
        hintText: '–',
        hintStyle: theme.textTheme.bodyLarge?.copyWith(
          color: AppColors.textTertiary,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}
