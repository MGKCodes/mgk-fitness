import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../data/exercise_lookup.dart';
import '../domain/previous_performance.dart';
import '../domain/session.dart';
import '../domain/workout_library.dart';
import 'exercise_picker_sheet.dart';

/// Builds a workout, or edits one — its name, its movements in order, and each
/// movement's sets and rep target.
///
/// **This replaced a builder that could only create.** A saved workout could be
/// started or deleted and nothing else, while the premade sheet told lifters
/// they could "rename, edit or delete yours". Now they can, and the same screen
/// serves both: [workout] null is a new one.
///
/// Returns the saved workout, or null if the lifter backed out.
class WorkoutEditorScreen extends StatefulWidget {
  const WorkoutEditorScreen({
    super.key,
    required this.library,
    required this.lookup,
    this.workout,
    this.log = const <Session>[],
    this.initialName,
    this.initialMovements = const <TemplateMovement>[],
  });

  final WorkoutLibrary library;
  final ExerciseLookup lookup;

  /// The workout being edited, or null to build a new one.
  final SavedWorkout? workout;

  /// For the picker's recent movements.
  final List<Session> log;

  final String? initialName;
  final List<TemplateMovement> initialMovements;

  @override
  State<WorkoutEditorScreen> createState() => _WorkoutEditorScreenState();
}

/// A movement being edited, with a key that survives reordering. Keyed by index
/// the list could not animate a drag: every key changed when anything moved.
class _Row {
  _Row(this.movement) : key = UniqueKey();

  final Key key;
  TemplateMovement movement;
}

class _WorkoutEditorScreenState extends State<WorkoutEditorScreen> {
  late final TextEditingController _name = TextEditingController(
    text: widget.workout?.name ?? widget.initialName ?? '',
  );
  late final List<_Row> _rows = <_Row>[
    for (final m in widget.workout?.movements ?? widget.initialMovements)
      _Row(m),
  ];
  late final String _initialName = _name.text;
  late final List<TemplateMovement> _initial = <TemplateMovement>[
    for (final r in _rows) r.movement,
  ];
  bool _saving = false;

  bool get _dirty =>
      _name.text != _initialName ||
      _rows.length != _initial.length ||
      <int>[
        for (var i = 0; i < _rows.length; i++)
          if (_rows[i].movement != _initial[i]) i,
      ].isNotEmpty;

  /// Both halves are required, and the button says so by being disabled. A
  /// workout with no name cannot be found again; one with no movements starts
  /// an empty session, which is the state the library exists to get somebody
  /// out of.
  bool get _canSave =>
      !_saving && _name.text.trim().isNotEmpty && _rows.isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addMovements() async {
    final names = await ExercisePickerSheet.show(
      context,
      lookup: widget.lookup,
      recent: PreviousPerformance.recentNames(widget.log),
      room: SessionLimits.movements - _rows.length,
    );
    if (names == null || !mounted) return;
    setState(() {
      for (final n in names) {
        if (n.trim().isNotEmpty) _rows.add(_Row(TemplateMovement(n.trim())));
      }
    });
  }

  void _remove(_Row row) {
    final at = _rows.indexOf(row);
    setState(() => _rows.removeAt(at));
    AppToast.show(
      context,
      '${row.movement.name} removed.',
      actionLabel: 'Undo',
      onAction: () {
        if (!mounted) return;
        setState(() => _rows.insert(at.clamp(0, _rows.length), row));
      },
    );
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final movements = <TemplateMovement>[for (final r in _rows) r.movement];
    final existing = widget.workout;
    final saved = existing == null
        // Exactly what they typed. The `(2)` suffix is for names the *app*
        // chose — see [uniqueWorkoutName].
        ? await widget.library.save(
            name: _name.text.trim(),
            movements: movements,
          )
        : await widget.library.update(
            existing.copyWith(name: _name.text.trim(), movements: movements),
          );
    if (!mounted) return;
    Navigator.of(context).pop(saved);
  }

  Future<void> _leave() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Discard changes?'),
        content: const Text('What you changed here will not be saved.'),
        actions: <Widget>[
          AppTextButton(
            label: 'Keep editing',
            onPressed: () => Navigator.of(dialog).pop(false),
          ),
          AppTextButton(
            label: 'Discard',
            onPressed: () => Navigator.of(dialog).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final full = _rows.length >= SessionLimits.movements;
    return PopScope(
      // A back gesture over unsaved changes asks first, the same as the arrow.
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        // A glass bar over a quiet photograph — the same header the library
        // has, so the two read as one place. The body starts below the bar:
        // the Scaffold adds its height to the top padding the SafeArea reads.
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          flexibleSpace: const GlassSurface.bar(child: SizedBox.expand()),
          leading: AppIconButton(
            icon: Icons.arrow_back,
            tooltip: 'Back',
            onPressed: _leave,
          ),
          title: Text(widget.workout == null ? 'New workout' : 'Edit workout'),
        ),
        body: PhotoBackdrop(
          image: 'assets/images/backgrounds/hero_home.webp',
          scrim: ScrimStrength.quiet,
          child: SafeArea(
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SectionLabel('Name'),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.sentences,
                        inputFormatters: <TextInputFormatter>[
                          LengthLimitingTextInputFormatter(
                            SessionLimits.nameLength,
                          ),
                        ],
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        decoration: const InputDecoration(
                          hintText: 'Push day, Leg day, Upper body',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Row(
                        children: <Widget>[
                          const Expanded(child: SectionLabel('Movements')),
                          Text(
                            '${_rows.length}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
                Expanded(
                  child: _rows.isEmpty
                      ? Center(
                          child: Text(
                            'Nothing in it yet.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                          ),
                          buildDefaultDragHandles: false,
                          itemCount: _rows.length,
                          // A dragged row lifts a little and settles back — the
                          // row is the thing moving, not a copy of it.
                          proxyDecorator: (child, _, animation) =>
                              AnimatedBuilder(
                                animation: animation,
                                builder: (context, child) => Transform.scale(
                                  scale: 1 + 0.03 * animation.value,
                                  child: child,
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  elevation: 8 * animation.value,
                                  shadowColor: Colors.black,
                                  borderRadius: AppRadius.cardAll,
                                  child: child,
                                ),
                              ),
                          onReorder: (from, to) => setState(() {
                            final target = to > from ? to - 1 : to;
                            _rows.insert(target, _rows.removeAt(from));
                          }),
                          itemBuilder: (context, i) => _MovementEditor(
                            key: _rows[i].key,
                            index: i,
                            movement: _rows[i].movement,
                            onChanged: (m) =>
                                setState(() => _rows[i].movement = m),
                            onRemove: () => _remove(_rows[i]),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        // The bar slot, not the foot of the body: a snackbar sits **above**
        // this slot, where it covered a body-level Save for the four seconds
        // after every removal — a quick Save landed on "Undo" instead.
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppOutlinedButton(
                  onPressed: full ? null : _addMovements,
                  icon: Icons.add,
                  label: 'Add movements',
                  expand: true,
                ),
                if (full)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      '${SessionLimits.movements} movements is the most '
                      'one workout holds.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                PrimaryButton(
                  label: 'Save',
                  busy: _saving,
                  onPressed: _canSave ? _save : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One movement in the editor: its name and handle on top, its sets and rep
/// target beneath — two lines, because one could not hold a name, a stepper,
/// a field and two controls at 375pt without cutting the name to a word.
class _MovementEditor extends StatelessWidget {
  const _MovementEditor({
    super.key,
    required this.index,
    required this.movement,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final TemplateMovement movement;
  final ValueChanged<TemplateMovement> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: Icon(
                      Icons.drag_handle,
                      size: 20,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    movement.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AppIconButton(
                  icon: Icons.close,
                  onPressed: onRemove,
                  tooltip: 'Remove ${movement.name}',
                  size: 18,
                  color: AppColors.textTertiary,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            // Two groups that sit at either end, and stack when the text is too
            // large for both on one line — a row of fixed widths overflowed.
            // Full width, or the wrap is only as wide as the two and "either
            // end" is the same place.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(left: 36, right: AppSpacing.sm),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: AppSpacing.xs,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SectionLabel('Sets', emphasis: LabelEmphasis.stat),
                      const SizedBox(width: AppSpacing.sm),
                      AppIconButton(
                        icon: Icons.remove,
                        size: 18,
                        tooltip: 'One fewer set of ${movement.name}',
                        color: AppColors.textSecondary,
                        onPressed: movement.sets <= 1
                            ? null
                            : () => onChanged(
                                movement.copyWith(sets: movement.sets - 1),
                              ),
                      ),
                      // At least 28 wide so the steppers do not shift between 9 and
                      // 10; wider when the text is.
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 28),
                        child: Text(
                          '${movement.sets}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                      AppIconButton(
                        icon: Icons.add,
                        size: 18,
                        tooltip: 'One more set of ${movement.name}',
                        color: AppColors.textSecondary,
                        onPressed:
                            movement.sets >= SessionLimits.setsPerMovement
                            ? null
                            : () => onChanged(
                                movement.copyWith(sets: movement.sets + 1),
                              ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SectionLabel('Reps', emphasis: LabelEmphasis.stat),
                      const SizedBox(width: AppSpacing.sm),
                      SizedBox(
                        // Room for "200" at the phone's text size.
                        width: MediaQuery.textScalerOf(
                          context,
                        ).scale(48).clamp(64, 160).toDouble(),
                        child: _RepTargetField(
                          value: movement.repTarget,
                          onChanged: (reps) => onChanged(
                            movement.copyWith(repTarget: () => reps),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A rep target, or blank for "whatever you did last time".
class _RepTargetField extends StatefulWidget {
  const _RepTargetField({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  State<_RepTargetField> createState() => _RepTargetFieldState();
}

class _RepTargetFieldState extends State<_RepTargetField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value?.toString() ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3),
        // Past the limit is refused, not clamped — the same rule as a set.
        TextInputFormatter.withFunction(
          (oldValue, newValue) =>
              newValue.text.isNotEmpty &&
                  (int.tryParse(newValue.text) ?? 0) > SessionLimits.maxReps
              ? oldValue
              : newValue,
        ),
      ],
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.bg,
        hintText: '–',
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
      onChanged: (text) {
        final reps = int.tryParse(text);
        widget.onChanged(reps == null || reps == 0 ? null : reps);
      },
    );
  }
}
