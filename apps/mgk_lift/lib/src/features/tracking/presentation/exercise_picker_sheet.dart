import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../data/exercise_lookup.dart';
import '../domain/exercise.dart';
import 'exercise_thumb.dart';

/// Picks the movements to add — **several at once, recent first**.
///
/// This replaced a bare text field. A text field is not wrong — a lifter must
/// always be able to type "smith machine incline press, feet up" — but making it
/// the *only* way wasted the 266-movement library and its form images, and made
/// every session start with spelling.
///
/// Three changes from the first version, each from the 2026-09-28 audit:
///
/// * **Many at a time.** Building a six-movement session meant opening this six
///   times. Tap to select; the button at the foot adds them all, in the order
///   they were tapped.
/// * **What you actually do, first.** The catalogue opened at "Ab Rollout On
///   Knees With Barbell". The movements this lifter has worked lead the list.
/// * **No keyboard until it is asked for.** Search took focus on open, the
///   keyboard rose, and the sheet — 85% of the screen plus the keyboard — grew
///   under the status bar with its handle and title behind it. Seen on the
///   emulator. The sheet now sits inside the safe area and sizes around the
///   keyboard when search is tapped.
///
/// And from the redesign (11): chips for muscle group and equipment, with
/// search or without, because "something for triceps with a cable" is how a
/// lifter standing at a free station actually thinks.
class ExercisePickerSheet extends StatefulWidget {
  const ExercisePickerSheet({
    super.key,
    required this.lookup,
    this.recent = const <String>[],
    this.room,
    this.replacing,
  });

  final ExerciseLookup lookup;

  /// The movement being swapped out, when this picks its replacement rather
  /// than adding to the session. One tap chooses and closes: a replacement is
  /// one movement, and a confirm button under a single choice is a second tap
  /// that asks nothing.
  final String? replacing;

  /// Names this lifter has worked, most recent first. See
  /// `PreviousPerformance.recentNames`.
  final List<String> recent;

  /// How many more movements the caller can take, or null for no limit. At the
  /// limit, a further tap says so instead of selecting.
  final int? room;

  /// Returns the chosen names in the order they were chosen, or null if the
  /// sheet was dismissed without adding anything.
  static Future<List<String>?> show(
    BuildContext context, {
    required ExerciseLookup lookup,
    List<String> recent = const <String>[],
    int? room,
    String? replacing,
  }) {
    return showGlassSheet<List<String>>(
      context: context,
      maxHeightFactor: 0.94,
      // Its own messenger, so "room for 2 more" shows in the sheet rather
      // than behind it. The sheet already sits above the keyboard, so the
      // scaffold must not make room for it a second time.
      builder: (_) => ScaffoldMessenger(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          body: ExercisePickerSheet(
            lookup: lookup,
            recent: recent,
            room: room,
            replacing: replacing,
          ),
        ),
      ),
    );
  }

  @override
  State<ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<ExercisePickerSheet> {
  final TextEditingController _query = TextEditingController();
  late List<Exercise> _results = widget.lookup.search('');
  String? _muscleGroup;
  String? _equipment;

  /// Chosen names, in the order they were tapped — the order they are added.
  final List<String> _chosen = <String>[];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) => setState(_refresh);

  void _refresh() {
    _results = widget.lookup.search(
      _query.text,
      muscleGroup: _muscleGroup,
      equipment: _equipment,
    );
  }

  /// The chip already on clears it: one tap in, one tap out.
  void _pickMuscleGroup(String group) => setState(() {
    _muscleGroup = _muscleGroup == group ? null : group;
    _refresh();
  });

  void _pickEquipment(String kind) => setState(() {
    _equipment = _equipment == kind ? null : kind;
    _refresh();
  });

  /// True when what they typed is not already a catalogue name — the only case
  /// where offering "add your own" is useful rather than noise.
  bool get _canAddCustom {
    final typed = _query.text.trim();
    return typed.isNotEmpty && widget.lookup.find(typed) == null;
  }

  void _toggle(String name) {
    if (widget.replacing != null) {
      // Choosing the movement already there is not a swap; closing says so.
      Navigator.of(context).pop(<String>[name]);
      return;
    }
    setState(() {
      if (_chosen.remove(name)) return;
      final room = widget.room;
      if (room != null && _chosen.length >= room) {
        if (ScaffoldMessenger.maybeOf(context) != null) {
          AppToast.show(
            context,
            room == 0
                ? 'This session is full.'
                : 'This session has room for $room more.',
          );
        }
        return;
      }
      _chosen.add(name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Recent is for the open list. Once anything narrows it, what is shown is
    // what was asked for.
    final searching =
        _query.text.trim().isNotEmpty ||
        _muscleGroup != null ||
        _equipment != null;
    // A recent movement may be one the lifter typed, with no catalogue entry
    // and so no image — the same first-class case the session card handles.
    final recent = <(String, Exercise?)>[
      for (final name in widget.recent) (name, widget.lookup.find(name)),
    ];

    // The glass sheet puts this above the keyboard and inside the safe area;
    // it fills whatever that leaves, up to its ceiling.
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: constraints.maxHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SheetHandle(),
                    SectionLabel(
                      widget.replacing == null
                          ? 'Add exercises'
                          : 'Replace ${widget.replacing}',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _query,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: _onQueryChanged,
                      onTapOutside: (_) =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                      decoration: InputDecoration(
                        hintText: 'Search movements, muscles, equipment',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true,
                        fillColor: AppColors.bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _ChipRow(
                      label: 'Muscle group',
                      options: ExerciseLookup.muscleGroups,
                      selected: _muscleGroup,
                      onTap: _pickMuscleGroup,
                    ),
                    _ChipRow(
                      label: 'Equipment',
                      options: ExerciseLookup.equipment,
                      selected: _equipment,
                      onTap: _pickEquipment,
                    ),
                    if (_canAddCustom) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      _CustomRow(
                        name: _query.text.trim(),
                        chosen: _chosen.contains(_query.text.trim()),
                        onTap: () => _toggle(_query.text.trim()),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  children: <Widget>[
                    if (!searching && recent.isNotEmpty) ...<Widget>[
                      const SectionLabel('Recent'),
                      const SizedBox(height: AppSpacing.xs),
                      for (final (name, catalogue) in recent)
                        _ExerciseRow(
                          name: name,
                          catalogue: catalogue,
                          chosen: _chosen.contains(name),
                          onTap: () => _toggle(name),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      const SectionLabel('All movements'),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    if (_results.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xl,
                        ),
                        child: Text(
                          _query.text.trim().isEmpty
                              ? 'Nothing here with both of those.'
                              : 'Nothing matches that.\nAdd it as your own '
                                    'movement.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      )
                    else
                      for (final e in _results)
                        _ExerciseRow(
                          name: e.name,
                          catalogue: e,
                          chosen: _chosen.contains(e.name),
                          onTap: () => _toggle(e.name),
                        ),
                  ],
                ),
              ),
              // The one action, at the thumb's end of the sheet. It names the
              // count, so what is about to happen is on the button. Not when
              // replacing, where the tap on a row is the choice.
              if (widget.replacing == null)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: PrimaryButton(
                      label: switch (_chosen.length) {
                        0 => 'Choose movements',
                        1 => 'Add 1 movement',
                        final n => 'Add $n movements',
                      },
                      onPressed: _chosen.isEmpty
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop(List<String>.of(_chosen)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.name,
    required this.catalogue,
    required this.chosen,
    required this.onTap,
  });

  final String name;
  final Exercise? catalogue;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressScale(
      // A list scrolled as often as it is tapped: the settle, not the tick,
      // so a drag does not stutter across the screen.
      haptic: false,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: <Widget>[
              ExerciseThumb(asset: catalogue?.startImage, size: 44),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      name,
                      style: theme.textTheme.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      catalogue?.subtitle ?? 'Your own movement',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: AppMotion.fast,
                child: Icon(
                  chosen ? Icons.check_circle : Icons.add_circle_outline,
                  key: ValueKey<bool>(chosen),
                  size: 22,
                  color: chosen
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The escape hatch: whatever they typed, added as-is.
class _CustomRow extends StatelessWidget {
  const _CustomRow({
    required this.name,
    required this.chosen,
    required this.onTap,
  });

  final String name;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PressScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              Icon(
                chosen ? Icons.check_circle : Icons.add,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Add "$name" as your own',
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One filter's chips, in a row that scrolls sideways. At most one is on.
class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.label,
    required this.options,
    required this.selected,
    required this.onTap,
  });

  /// For a screen reader: what the row filters by.
  final String label;
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: label,
      child: SizedBox(
        height: 44,
        // Built whole rather than lazily: fifteen chips at most, and a lazy
        // row leaves the ones past the edge out of the tree until scrolled.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (final (i, option) in options.indexed) ...<Widget>[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                _FilterChip(
                  label: option,
                  selected: option == selected,
                  onTap: () => onTap(option),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: PressScale(
        haptic: false,
        onTap: onTap,
        // 44 to tap around a 34 chip, the same rule as the small pill.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: AnimatedContainer(
            duration: AppMotion.fast,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : AppColors.bg,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                maxLines: 1,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected
                      ? AppColors.onPrimary
                      : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
