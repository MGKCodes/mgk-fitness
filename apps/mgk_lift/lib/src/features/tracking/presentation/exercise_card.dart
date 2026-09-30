import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../domain/exercise.dart';
import '../domain/previous_performance.dart';
import '../domain/session.dart';
import 'exercise_thumb.dart';

/// Which of a set's two numbers a field edits.
enum SetField { weight, reps }

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
    required this.onCommit,
    this.focusFor,
    this.onCycleSetType,
    this.onSetMenu,
    this.onRemoveSet,
    this.onSwap,
    this.onRejected,
    this.previous,
    this.isCollapsed = false,
    this.onToggleCollapsed,
    this.onOpenStats,
  });

  final SessionExercise exercise;

  /// The catalogue entry, when this movement is one of the 266 that ship. Null
  /// for something the lifter typed themselves, which is a first-class case:
  /// the card simply carries no image and no subtitle.
  final Exercise? catalogue;

  /// What they did on this movement last time, or null if they never have.
  ///
  /// Null renders nothing rather than "no history" — a first session should
  /// not be a screen full of blanks telling somebody what they have not done
  /// yet.
  final PreviousPerformance? previous;

  final MassUnit massUnit;

  /// Adds a set. The button is disabled, with its reason under it, once the
  /// movement holds [SessionLimits.setsPerMovement].
  final VoidCallback onAddSet;

  final VoidCallback onRemove;
  final void Function(SessionSet set) onToggle;

  /// A field's value, handed over when the lifter **leaves** the field — not
  /// per keystroke. Weight is already in kilograms. Null means "unchanged".
  ///
  /// Per keystroke, typing `102.5` was five writes and five full reads of the
  /// session, each rebuilding the screen under a field still being typed in.
  final void Function(SessionSet set, int? reps, double? weightKg) onCommit;

  /// The focus node for one field, owned by the screen so it can move focus
  /// between fields — the keyboard bar's previous and next — and flush a field
  /// before anything reads its value. Null lets each field own its own.
  final FocusNode Function(SessionSet set, SetField field)? focusFor;

  /// Advances a set to the next [SetType]. Null makes the marker read-only,
  /// which is right for anything showing a finished session.
  final void Function(SessionSet set)? onCycleSetType;

  /// Opens the set's menu — its type, and Remove. The long-press on the label.
  final void Function(SessionSet set)? onSetMenu;

  /// Removes one set. Null hides the gesture entirely rather than leaving a
  /// swipe that springs back — the same absent-rather-than-inert rule the
  /// coach mark follows.
  final void Function(SessionSet set)? onRemoveSet;

  /// Asks the coach for something else instead of this movement. **Null hides
  /// the action entirely** rather than showing one that opens a sheet with
  /// nothing behind it — there is no coach in a free or offline build.
  final VoidCallback? onSwap;

  /// Told when a keystroke was refused for passing a limit, with the words to
  /// say about it. The field refuses; the screen says why.
  final ValueChanged<String>? onRejected;

  /// Shows the one-line summary instead of the set rows. Decided by the screen,
  /// not here, so the lifter's manual expand survives a rebuild.
  final bool isCollapsed;

  /// Null leaves the card permanently expanded — the right behaviour for a
  /// caller that has no state to remember the toggle in.
  final VoidCallback? onToggleCollapsed;

  /// Opens the movement's stats (R9), from its picture and name. Only on the
  /// open card: on a folded one, a tap unfolds it.
  final VoidCallback? onOpenStats;

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

    // The set a lifter is about to do: the first one not yet ticked. It is the
    // loud row — see [SetRow.isNext].
    final next = exercise.sets
        .where((s) => !s.isCompleted)
        .map((s) => s.id)
        .firstOrNull;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: _Opens(
                    onTap: onOpenStats,
                    label: exercise.name,
                    child: Row(
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
                                // The best line available: what it trains,
                                // or — for a movement they typed — what they
                                // have done on it.
                                catalogue?.subtitle ??
                                    (top == null
                                        ? 'Your own movement'
                                        : 'Best today · ${Mass.kilograms(top.weightKg).label(massUnit)} × ${top.reps}'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                              ),
                              if (previous != null) ...<Widget>[
                                const SizedBox(height: 2),
                                Text(
                                  _previousLabel(previous!, massUnit),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
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
                _removable(
                  set,
                  SetRow(
                    key: ValueKey<String>('row-${set.id}'),
                    set: set,
                    label: exercise.labelFor(set),
                    isNext: set.id == next,
                    massUnit: massUnit,
                    onToggle: () => onToggle(set),
                    onCommit: (reps, weight) => onCommit(set, reps, weight),
                    weightFocus: focusFor?.call(set, SetField.weight),
                    repsFocus: focusFor?.call(set, SetField.reps),
                    onCycleSetType: onCycleSetType == null
                        ? null
                        : () => onCycleSetType!(set),
                    onLongPressLabel: onSetMenu == null
                        ? null
                        : () => onSetMenu!(set),
                    onRejected: onRejected,
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: AppTextButton(
                // Disabled at the limit rather than refusing the tap: a button
                // that springs and then does nothing is worse than one that
                // plainly cannot be pressed — and the line under it says why.
                onPressed: exercise.canAddSet ? onAddSet : null,
                icon: Icons.add,
                label: exercise.sets.isEmpty ? 'Add first set' : 'Add set',
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                ),
              ),
            ),
            if (!exercise.canAddSet)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: Text(
                  '${SessionLimits.setsPerMovement} sets is the most one '
                  'movement holds.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Swipe to remove, **from anywhere on the row**.
  ///
  /// It used to work only from the 28px label column: a `TextField` claims a
  /// horizontal drag for text selection, so a swipe starting over either
  /// number never reached this. The fields now ignore the pointer until they
  /// are focused — a tap focuses them, a drag passes through — so the whole
  /// row is the handle, as it was in the shipped app.
  ///
  /// End-to-start only. A gesture that fires in both directions on a row this
  /// dense goes off by accident while scrolling a long session. The long-press
  /// menu on the label is the second way in, for anybody who never finds the
  /// swipe; either way, Undo follows.
  Widget _removable(SessionSet set, Widget row) {
    final remove = onRemoveSet;
    if (remove == null) return row;
    return Dismissible(
      key: ValueKey<String>(set.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => remove(set),
      background: const _RemoveSetBackground(),
      child: row,
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
          width: _labelWidth,
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

/// The label column: wide enough to be a real tap target, since tapping it
/// cycles the set's type and holding it opens the set's menu.
const double _labelWidth = 32;

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

/// One set. The tick is the primary control: weight and reps are already
/// carried forward, so the common path between sets is a single tap.
class SetRow extends StatelessWidget {
  const SetRow({
    super.key,
    required this.set,
    required this.massUnit,
    required this.onToggle,
    required this.onCommit,
    String? label,
    this.isNext = false,
    this.weightFocus,
    this.repsFocus,
    this.onCycleSetType,
    this.onLongPressLabel,
    this.onRejected,
  }) : label = label ?? '';

  final SessionSet set;

  /// What the first column reads — `W`, `D`, `F` or the set's number among the
  /// working sets. See [SessionExercise.labelFor].
  final String label;

  final MassUnit massUnit;
  final VoidCallback onToggle;

  /// **The loud row.** The set a lifter is about to do lifts one step up the
  /// surface ladder with white numbers; everything else recedes.
  ///
  /// It was the other way round: a *done* set took the lighter `elevated` fill
  /// and white numbers, while the set still to do was the dimmest thing in the
  /// card — and the comment on that code said done sets should recede. The
  /// suite's rule (`mgk_ui` README) is that focus is elevation, and focus is
  /// the set you are on.
  final bool isNext;

  /// Advances the set to the next [SetType]. Null makes the marker read-only,
  /// which is right for anything showing a finished session.
  final VoidCallback? onCycleSetType;

  /// Opens the set's menu. Null leaves the label tap-only.
  final VoidCallback? onLongPressLabel;

  /// Reports a changed field on the way out of it — reps as typed, weight in
  /// **kilograms**. Conversion happens here, the one point where a typed number
  /// becomes a stored one, so nothing below the UI ever sees a pound.
  final void Function(int? reps, double? weightKg) onCommit;

  final FocusNode? weightFocus;
  final FocusNode? repsFocus;
  final ValueChanged<String>? onRejected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = set.isCompleted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        decoration: BoxDecoration(
          color: isNext ? AppColors.elevated : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 2,
        ),
        child: Row(
          children: <Widget>[
            // `W` rather than a number for a warm-up. Tap cycles the type; hold
            // opens the set's menu.
            //
            // Without the marker the screen contradicts itself: a warm-up is
            // ticked like any other set but counts toward neither the volume
            // nor the set count, so a lifter sees four ticks above a header
            // reading three and has no way to tell which one was discounted.
            SizedBox(
              width: _labelWidth,
              child: PressScale(
                enabled: onCycleSetType != null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onCycleSetType,
                  onLongPress: onLongPressLabel,
                  // Semantics rather than a Tooltip: a tooltip's own
                  // long-press trigger beat this one's in the gesture arena,
                  // so holding the label showed a hint instead of the menu.
                  child: Semantics(
                    button: true,
                    label:
                        'Set $label. Tap to mark as ${set.setType.next.label}',
                    onLongPressHint: "Open this set's menu",
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isNext
                              ? AppColors.textSecondary
                              : AppColors.textTertiary,
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
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: SetNumberField(
                value: set.weightKg == 0
                    ? ''
                    : _trim(
                        Mass.kilograms(set.weightKg).displayValue(massUnit),
                      ),
                field: SetField.weight,
                massUnit: massUnit,
                emphasised: isNext,
                done: done,
                focusNode: weightFocus,
                onRejected: onRejected,
                onCommit: (text) =>
                    onCommit(null, weightFromText(text, massUnit)),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: SetNumberField(
                value: set.reps == 0 ? '' : '${set.reps}',
                field: SetField.reps,
                massUnit: massUnit,
                emphasised: isNext,
                done: done,
                focusNode: repsFocus,
                onRejected: onRejected,
                onCommit: (text) => onCommit(repsFromText(text), null),
              ),
            ),
            SizedBox(
              width: 44,
              // The check springs in — the one moment in a set worth a
              // flourish — and the circle it replaces shrinks away.
              child: AnimatedSwitcher(
                duration: AppMotion.base,
                switchInCurve: AppMotion.snappy,
                switchOutCurve: AppMotion.exit,
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: AppIconButton(
                  key: ValueKey<bool>(done),
                  onPressed: onToggle,
                  icon: done ? Icons.check_circle : Icons.circle_outlined,
                  size: 24,
                  color: done
                      ? AppColors.success
                      : (isNext
                            ? AppColors.textSecondary
                            : AppColors.textTertiary),
                  tooltip: done ? 'Mark not done' : 'Mark done',
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : '$v';
}

/// Reps, as the field holds them. Empty is zero — "not entered".
int repsFromText(String text) => int.tryParse(text.trim()) ?? 0;

/// Kilograms, from what the field holds in [unit].
///
/// The field cannot hold more than the limit **in its own unit**, but 2,204.6 lb
/// converts to a hair over 1,000 kg in floating point; that hair is rounding,
/// not a heavier bar, so it is settled back onto the limit here rather than
/// refused downstream.
double weightFromText(String text, MassUnit unit) {
  final typed = double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;
  final kg = Mass.inUnit(typed, unit).kilograms;
  return kg > SessionLimits.maxWeightKg && kg < SessionLimits.maxWeightKg + 0.01
      ? SessionLimits.maxWeightKg
      : kg;
}

/// A bare number. No suffix and no label — the column header says what it is,
/// which is what lets the row stay this quiet.
///
/// ## Saving is leaving
///
/// The value goes to storage when the field **loses focus** — a tap elsewhere,
/// the keyboard bar, a tick, the app going to the background — and not on
/// every keystroke. Typing `102.5` used to be five writes; it is now one.
///
/// ## A tap focuses; a drag passes through
///
/// Until it has focus the field ignores the pointer, and a tap on it asks for
/// focus. That is what lets a swipe that starts over a number reach the row's
/// Dismissible — a `TextField` claims horizontal drags for text selection.
///
/// ## What it refuses
///
/// Reps take digits only, up to [SessionLimits.maxReps]. Weight takes one
/// decimal separator — a comma is read as a point — two decimal places, and
/// up to [SessionLimits.maxWeightKg] in the lifter's unit. A refused keystroke
/// leaves the field as it was and tells [onRejected] why; nothing is clamped.
class SetNumberField extends StatefulWidget {
  const SetNumberField({
    super.key,
    required this.value,
    required this.field,
    required this.massUnit,
    required this.onCommit,
    this.done = false,
    this.emphasised = false,
    this.focusNode,
    this.onRejected,
  });

  /// What storage holds, formatted. The field shows it whenever it is not
  /// being typed into.
  final String value;

  final SetField field;
  final MassUnit massUnit;

  /// The text, on the way out of the field — only when it changed.
  final ValueChanged<String> onCommit;

  final bool done;

  /// The row is the set a lifter is on; its numbers are the loud ones.
  final bool emphasised;

  /// Owned by the screen when it needs to move focus between fields.
  final FocusNode? focusNode;

  final ValueChanged<String>? onRejected;

  @override
  State<SetNumberField> createState() => _SetNumberFieldState();
}

class _SetNumberFieldState extends State<SetNumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  FocusNode? _own;

  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(SetNumberField old) {
    super.didUpdateWidget(old);
    final oldNode = old.focusNode ?? _own;
    if (oldNode != _focus) {
      oldNode?.removeListener(_onFocusChange);
      _focus.addListener(_onFocusChange);
    }
    // Only when the value changed underneath us and the field is not being
    // typed into — otherwise the text would jump mid-entry.
    if (!_focus.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  void _onFocusChange() {
    if (!mounted) return;
    if (_focus.hasFocus) {
      // Selected on arrival, so the common edit — a new number — is typing
      // over the old one rather than deleting it first.
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      _commit();
    }
    // The pointer gate follows focus.
    setState(() {});
  }

  /// Hands the text over if it changed.
  ///
  /// Straight away when the framework is between frames, which is almost
  /// always; deferred by a microtask when focus is lost *during* a frame — a
  /// focused field being unmounted — because the screen's response is a
  /// `setState`, and the tree is locked mid-frame.
  void _commit() {
    final text = _controller.text;
    if (text == widget.value) return;
    final commit = widget.onCommit;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      commit(text);
    } else {
      scheduleMicrotask(() => commit(text));
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _own?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focused = _focus.hasFocus;
    final reps = widget.field == SetField.reps;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: focused ? null : _focus.requestFocus,
      child: IgnorePointer(
        ignoring: !focused,
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          keyboardType: reps
              ? TextInputType.number
              : const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            if (reps)
              RepsInputFormatter(onRejected: widget.onRejected)
            else
              WeightInputFormatter(
                widget.massUnit,
                onRejected: widget.onRejected,
              ),
          ],
          textAlign: TextAlign.center,
          // Tapping anywhere else puts the field — and so the keyboard — away.
          // Flutter does not do this on a phone by default, and the iOS
          // number pad has no key to do it either, so without this the only
          // way to close the keyboard was to leave the screen.
          onTapOutside: (_) => _focus.unfocus(),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: widget.emphasised || focused
                ? AppColors.textPrimary
                : AppColors.textSecondary,
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
        ),
      ),
    );
  }
}

/// Digits only, three at most, and never past [SessionLimits.maxReps].
///
/// The field used to allow `.` — a decimal keyboard, and a formatter letting
/// digits and points through — so `8.5` was typeable and saved as 0 reps.
class RepsInputFormatter extends TextInputFormatter {
  const RepsInputFormatter({this.onRejected});

  final ValueChanged<String>? onRejected;

  static final RegExp _digits = RegExp(r'^\d{0,3}$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (!_digits.hasMatch(text)) return oldValue;
    if (text.isNotEmpty && int.parse(text) > SessionLimits.maxReps) {
      onRejected?.call('Reps stop at ${SessionLimits.maxReps}.');
      return oldValue;
    }
    return newValue;
  }
}

/// One decimal separator, two places, and never past the weight limit in the
/// lifter's own unit.
///
/// **A comma is a decimal point.** A European keyboard types `102,5`; the old
/// filter let digits and points through and silently dropped the comma, which
/// saved 1,025 kg. And a second point (`10..5`) used to parse as nothing and
/// save 0 kg. Both are now either read correctly or refused.
class WeightInputFormatter extends TextInputFormatter {
  WeightInputFormatter(this.unit, {this.onRejected});

  final MassUnit unit;
  final ValueChanged<String>? onRejected;

  static final RegExp _shape = RegExp(r'^\d{0,4}(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Same length either way, so the caret stays where the lifter put it.
    final text = newValue.text.replaceAll(',', '.');
    if (!_shape.hasMatch(text)) return oldValue;
    final value = double.tryParse(text) ?? 0;
    final max = Mass.kilograms(SessionLimits.maxWeightKg).inDisplayUnit(unit);
    if (value > max + 1e-9) {
      onRejected?.call(
        'Weights stop at ${Mass.kilograms(SessionLimits.maxWeightKg).label(unit)}.',
      );
      return oldValue;
    }
    return newValue.copyWith(text: text);
  }
}

/// "Last time · 12 Aug · 60 kg × 10, 8, 8"
///
/// The weight is stated once and then only when it changes, which is the
/// shorthand every lifting log uses and the reason the line stays scannable at
/// a glance. Spelling the unit out on every set turns three sets into a
/// sentence nobody reads mid-rack.
///
/// Capped at four sets. Past that the line is longer than the card is wide and
/// the ellipsis is doing the work anyway; the full history belongs on Profile.
String _previousLabel(PreviousPerformance previous, MassUnit unit) {
  final parts = <String>[];
  double? last;
  for (final set in previous.sets.take(4)) {
    if (set.weightKg == last) {
      parts.add('${set.reps}');
    } else {
      parts.add('${Mass.kilograms(set.weightKg).label(unit)} × ${set.reps}');
      last = set.weightKg;
    }
  }
  final more = previous.sets.length > 4 ? '…' : '';
  return 'Last time · ${_shortDate(previous.on)} · ${parts.join(', ')}$more';
}

String _shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The card's picture and name, as the way to the movement's stats. Plain
/// when there is nowhere to go.
class _Opens extends StatelessWidget {
  const _Opens({required this.onTap, required this.label, required this.child});

  final VoidCallback? onTap;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tap = onTap;
    if (tap == null) return child;
    return Semantics(
      button: true,
      hint: 'Shows $label over time',
      onTap: tap,
      child: PressScale(
        haptic: false,
        onTap: tap,
        child: ColoredBox(color: Colors.transparent, child: child),
      ),
    );
  }
}
