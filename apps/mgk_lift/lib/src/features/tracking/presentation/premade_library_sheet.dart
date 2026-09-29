import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../data/workout_templates.dart';
import '../domain/workout_library.dart';
import '../domain/workout_template.dart';

/// Browse the app's ready-made sessions and **add** one to your library.
///
/// **This is not a start path, and the distinction is the whole point.** The
/// app-provided list is the coach's raw material — the Knowledge decision
/// *"Lift templates are the coach's grounding layer, not a user-facing
/// library"*. Adding makes a **copy** in the lifter's own library, and from that
/// moment the two are unrelated: editing the copy does not touch the fifteen.
///
/// All fifteen sessions and all eight splits are here, with `offered` ordering
/// rather than filtering: curating a library is a decision made once and
/// sitting down, so hiding nine of the fifteen would be withholding them for
/// no reason the app could give.
///
/// Three things changed on 2026-09-29: every add can be undone; a premade you
/// already have needs an explicit **Add again** rather than the same tap twice
/// (a second tap used to make `Push (2)` without a word); and the sheet is a
/// solid one inside the safe area, not glass over the flat screen behind it.
class PremadeLibrarySheet extends StatefulWidget {
  const PremadeLibrarySheet({super.key, required this.library});

  final WorkoutLibrary library;

  /// Returns how many workouts were added — zero for a sheet opened and closed.
  static Future<int> show(
    BuildContext context, {
    required WorkoutLibrary library,
  }) async {
    final added = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      // Its own messenger, so Undo shows **in** the sheet. On the screen's, the
      // snackbar sat behind a sheet as tall as the screen: an add with an Undo
      // nobody could see.
      builder: (_) => ScaffoldMessenger(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: PremadeLibrarySheet(library: library),
        ),
      ),
    );
    return added ?? 0;
  }

  @override
  State<PremadeLibrarySheet> createState() => _PremadeLibrarySheetState();
}

class _PremadeLibrarySheetState extends State<PremadeLibrarySheet> {
  /// The premades already in the library, so the list can say which ones you
  /// have. Loaded once, then kept current as things are added and undone.
  Set<String> _have = const <String>{};

  /// The names already taken, for the `(2)` suffix.
  final List<String> _names = <String>[];

  /// How many this visit has added, handed back on close.
  int _added = 0;

  /// Guards the double-tap: a save is a write and a round trip.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await widget.library.all();
    if (!mounted) return;
    setState(() {
      _have = <String>{
        for (final w in saved)
          if (w.premadeId != null) w.premadeId!,
      };
      _names
        ..clear()
        ..addAll(saved.map((w) => w.name));
    });
  }

  Future<void> _add(List<WorkoutTemplate> templates) async {
    if (_saving) return;
    setState(() => _saving = true);
    final added = <SavedWorkout>[];
    for (final template in templates) {
      final name = uniqueWorkoutName(template.name, _names);
      added.add(
        await widget.library.save(
          name: name,
          movements: <TemplateMovement>[
            for (final m in template.exercises) TemplateMovement(m),
          ],
          fromPremade: template.id,
        ),
      );
      _names.add(name);
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _added += added.length;
      _have = <String>{..._have, for (final t in templates) t.id};
    });
    // Not awaited: the message never waits on the motor.
    unawaited(AppHaptics.selection());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            added.length == 1
                ? '${added.single.name} added.'
                : '${added.length} workouts added.',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              for (final w in added) {
                await widget.library.remove(w.id);
              }
              _added -= added.length;
              await _load();
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byId = <String, WorkoutTemplate>{
      for (final t in workoutTemplates) t.id: t,
    };
    final sessions = <WorkoutTemplate>[
      ...workoutTemplates.where((t) => t.offered),
      ...workoutTemplates.where((t) => !t.offered),
    ];

    return Padding(
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
          Row(
            children: <Widget>[
              const Expanded(child: SectionLabel('Add to your library')),
              AppIconButton(
                icon: Icons.close,
                onPressed: () => Navigator.of(context).pop(_added),
                tooltip: 'Close',
                color: AppColors.textSecondary,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'These are copies. Rename, edit or delete yours without touching '
            'the originals.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              children: <Widget>[
                const SectionLabel('Splits'),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'A whole rotation in one tap.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final split in workoutSplits)
                  _SplitBlock(
                    split: split,
                    templates: <WorkoutTemplate>[
                      for (final id in split.templateIds)
                        if (byId[id] != null) byId[id]!,
                    ],
                    onAdd: _saving ? null : _add,
                  ),
                const SizedBox(height: AppSpacing.md),
                const SectionLabel('Sessions'),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'One at a time, if you would rather build the week yourself.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final template in sessions)
                  _SessionRow(
                    template: template,
                    alreadyHave: _have.contains(template.id),
                    onAdd: _saving
                        ? null
                        : () => _add(<WorkoutTemplate>[template]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A split, and the sessions it rotates through. A tap on + adds every session
/// in it.
class _SplitBlock extends StatelessWidget {
  const _SplitBlock({
    required this.split,
    required this.templates,
    required this.onAdd,
  });

  final WorkoutSplit split;
  final List<WorkoutTemplate> templates;

  /// Null while a save is in flight.
  final void Function(List<WorkoutTemplate>)? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: AppRadius.cardAll,
            child: SizedBox(
              height: 84,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Image.asset(
                    split.image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: AppColors.elevated),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: <Color>[Color(0xE61A1A1A), Color(0x661A1A1A)],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              Text(
                                split.name,
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                '${split.description} · '
                                '${split.daysPerWeek} days',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AppIconButton(
                          icon: Icons.add,
                          onPressed: onAdd == null
                              ? null
                              : () => onAdd!(templates),
                          // Says the count: this is the one action here that
                          // writes more than one row.
                          tooltip:
                              'Add all ${templates.length} to your library',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final t in templates)
                Chip(
                  label: Text(t.name),
                  backgroundColor: AppColors.elevated,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One ready-made session. A tap adds it — unless it is already in the
/// library, when adding another copy is its own, explicit action.
class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.template,
    required this.alreadyHave,
    required this.onAdd,
  });

  final WorkoutTemplate template;
  final bool alreadyHave;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        color: AppColors.elevated,
        onTap: alreadyHave ? null : onAdd,
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
                  Text(template.name, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    alreadyHave
                        ? 'In your library'
                        : '${template.description} · '
                              '${template.exercises.length} movements',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (alreadyHave)
              AppTextButton(label: 'Add again', onPressed: onAdd)
            else
              AppIconButton(
                icon: Icons.add,
                onPressed: onAdd,
                tooltip: 'Add ${template.name} to your library',
              ),
          ],
        ),
      ),
    );
  }
}
