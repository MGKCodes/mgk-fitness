import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../data/workout_templates.dart';
import '../domain/workout_library.dart';
import '../domain/workout_template.dart';

/// Browse the app's ready-made sessions and **add** one to your library.
///
/// **This is not a start path, and the distinction is the whole point.** It
/// replaces `TemplatePickerSheet`, which handed a premade's movements straight
/// into a blank session — making the app-provided list the thing a lifter
/// starts from, which is precisely what the Knowledge decision *"Lift templates
/// are the coach's grounding layer, not a user-facing library"* rules out.
///
/// Adding makes a **copy** in the lifter's own library. From that moment the
/// two are unrelated: renaming or editing the copy does not touch the fifteen,
/// and there is no live link that could rewrite somebody's saved Push day
/// because the app's idea of one changed. That is Liftio's model, from
/// `WorkoutLibrarySlideUp.tsx`, and it is what makes the premades usable
/// without them being a surface.
///
/// All fifteen sessions and all eight splits are here, not the offered six.
/// The `offered` flag is about what to put in front of somebody with no coach
/// and no plan who has to decide *what to do today* — a decision made standing
/// up, in a hurry. Curating a library is the opposite kind of decision, so the
/// flag orders this list rather than filtering it.
class PremadeLibrarySheet extends StatefulWidget {
  const PremadeLibrarySheet({super.key, required this.library});

  final WorkoutLibrary library;

  /// Returns how many workouts were added, so the caller can reload and say so.
  /// Zero for a sheet that was opened and dismissed.
  static Future<int> show(
    BuildContext context, {
    required WorkoutLibrary library,
  }) async {
    final added = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PremadeLibrarySheet(library: library),
    );
    return added ?? 0;
  }

  @override
  State<PremadeLibrarySheet> createState() => _PremadeLibrarySheetState();
}

class _PremadeLibrarySheetState extends State<PremadeLibrarySheet> {
  /// The premades already in the library, so the list can say which ones you
  /// have. Loaded once — re-reading after every add would rebuild the whole
  /// sheet under the finger that just tapped it.
  Set<String> _have = const <String>{};

  /// The names already taken, for the `(2)` suffix. Kept alongside [_have]
  /// rather than re-read, and updated as things are added, so adding Push
  /// twice in one visit produces `Push (2)` rather than a second `Push`.
  final List<String> _names = <String>[];

  /// How many this visit has added. Handed back on close so the caller knows
  /// whether anything changed without having to diff the library.
  int _added = 0;

  /// Guards the double-tap: a save is a write and a round trip, and the row
  /// stays on screen while it happens.
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

  Future<void> _add(Iterable<WorkoutTemplate> templates) async {
    if (_saving) return;
    setState(() => _saving = true);
    for (final template in templates) {
      final name = uniqueWorkoutName(template.name, _names);
      await widget.library.save(
        name: name,
        movements: template.exercises,
        fromPremade: template.id,
      );
      _names.add(name);
      _have = <String>{..._have, template.id};
      _added++;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    await AppHaptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final byId = <String, WorkoutTemplate>{
      for (final t in workoutTemplates) t.id: t,
    };

    // Offered first, then the rest. Same list, different order — see the class
    // comment for why this is an ordering and not a filter.
    final sessions = <WorkoutTemplate>[
      ...workoutTemplates.where((t) => t.offered),
      ...workoutTemplates.where((t) => !t.offered),
    ];

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
              'These are copies. Rename, edit or delete yours without '
              'touching the originals.',
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
                    'One at a time, if you would rather build the week '
                    'yourself.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (final template in sessions)
                    _SessionRow(
                      template: template,
                      // Not a lock. Adding a second Push so you can keep a
                      // heavy and a light one is a real thing people do — this
                      // only says you already have one, which is the question
                      // somebody scrolling a list of fifteen is actually
                      // asking.
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
      ),
    );
  }
}

/// A split, and the sessions it rotates through.
///
/// Carried over from the picker this sheet replaces, image treatment and all —
/// the photographs are already greyscale, so unlike the form illustrations they
/// need no inversion, only a scrim to keep the label legible. What changed is
/// what a tap means: it adds every session in the split rather than starting
/// one of them.
class _SplitBlock extends StatelessWidget {
  const _SplitBlock({
    required this.split,
    required this.templates,
    required this.onAdd,
  });

  final WorkoutSplit split;
  final List<WorkoutTemplate> templates;

  /// Null while a save is in flight. See `_PremadeLibrarySheetState._saving`.
  final void Function(Iterable<WorkoutTemplate>)? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
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
                          // Says the count, because adding a split is the one
                          // action here that writes more than one row and a
                          // lifter should know that before they tap it.
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
                  backgroundColor: AppColors.surface,
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

/// One ready-made session, with what it trains and how many movements.
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
        onTap: onAdd,
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
                    '${template.description} · '
                    '${template.exercises.length} movements',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (alreadyHave) ...<Widget>[
              const Icon(Icons.check, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'In your library',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
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
