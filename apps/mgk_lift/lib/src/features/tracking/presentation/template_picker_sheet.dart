import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../data/workout_templates.dart';
import '../domain/workout_template.dart';

/// Picks a ready-made session to start from.
///
/// This exists for the empty-state problem. Someone opening a tracker faces a
/// blank session and has to remember what a push day is before they can log
/// anything — so the first session is the hardest, which is exactly the wrong
/// way round. One tap fills the card list and they start lifting.
///
/// Splits are shown first because that is how people think about training —
/// "I run PPL" — and each expands into the sessions it contains.
class TemplatePickerSheet extends StatelessWidget {
  const TemplatePickerSheet({super.key});

  /// Returns the chosen template, or null if dismissed.
  static Future<WorkoutTemplate?> show(BuildContext context) {
    return showModalBottomSheet<WorkoutTemplate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TemplatePickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    // The offered subset, not the whole catalogue. `offeredSplits` is derived
    // from `offeredTemplates`, so a split can never appear here whose Tuesday
    // opens a session the picker does not show.
    final byId = <String, WorkoutTemplate>{
      for (final t in offeredTemplates) t.id: t,
    };

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
            const SectionLabel('Start from a template'),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Pick a session. You can change anything once it is in.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                children: <Widget>[
                  for (final split in offeredSplits)
                    _SplitBlock(
                      split: split,
                      templates: <WorkoutTemplate>[
                        for (final id in split.templateIds)
                          if (byId[id] != null) byId[id]!,
                      ],
                      onPick: (t) => Navigator.of(context).pop(t),
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

class _SplitBlock extends StatelessWidget {
  const _SplitBlock({
    required this.split,
    required this.templates,
    required this.onPick,
  });

  final WorkoutSplit split;
  final List<WorkoutTemplate> templates;
  final ValueChanged<WorkoutTemplate> onPick;

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
                  // The split photographs are already greyscale, so unlike the
                  // form illustrations they need no inversion — only a scrim to
                  // keep the label legible.
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        Text(split.name, style: theme.textTheme.titleMedium),
                        Text(
                          '${split.description} · ${split.daysPerWeek} days',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
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
                ActionChip(
                  onPressed: () => onPick(t),
                  label: Text('${t.name} · ${t.exercises.length}'),
                  backgroundColor: AppColors.surface,
                  side: BorderSide.none,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
