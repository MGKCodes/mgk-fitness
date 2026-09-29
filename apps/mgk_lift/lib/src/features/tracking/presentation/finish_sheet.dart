import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../domain/session.dart';

/// The one look before a session ends.
///
/// **Finish used to be a single tap with no way back**, on a button in the
/// header — the heaviest decision on the screen, a thumb's width from the
/// session's name — and it kept every unticked set as though it had happened.
/// Unticked sets are now dropped (decision D3), so this says so **first**, in
/// the one place the lifter can still do something about it: keep going and
/// tick them.
///
/// Returns true to finish, null or false to keep going.
class FinishSheet extends StatelessWidget {
  const FinishSheet({super.key, required this.session, required this.massUnit});

  final Session session;
  final MassUnit massUnit;

  static Future<bool?> show(
    BuildContext context, {
    required Session session,
    required MassUnit massUnit,
  }) => showGlassSheet<bool>(
    context: context,
    builder: (_) => FinishSheet(session: session, massUnit: massUnit),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unticked = session.untickedSets;
    final sets = session.completedSets;
    final volume = session.volumeKg;
    // Movements with nothing ticked go too — the same rule, one level up. Said
    // here as well, because an untouched card is exactly the thing somebody
    // forgets is on the page. Seen on the emulator: two movements added and
    // never started, and the sheet said nothing about them.
    final empty = session.exercises
        .where((e) => !e.sets.any((s) => s.isCompleted))
        .length;
    final kept = session.exercises.length - empty;

    return SafeArea(
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
            Text('Finish ${session.name}?', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              <String>[
                '$sets ${sets == 1 ? 'set' : 'sets'}',
                if (volume > 0) Mass.kilograms(volume).label(massUnit),
                '$kept ${kept == 1 ? 'movement' : 'movements'}',
              ].join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (unticked > 0 || empty > 0) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              AppCard(
                color: AppColors.elevated,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (unticked > 0)
                      _Dropped(
                        '$unticked ${unticked == 1 ? 'set isn\'t' : 'sets aren\'t'} '
                        'ticked, so ${unticked == 1 ? 'it won\'t' : 'they won\'t'} '
                        'be saved.',
                      ),
                    if (unticked > 0 && empty > 0)
                      const SizedBox(height: AppSpacing.sm),
                    if (empty > 0)
                      _Dropped(
                        '$empty ${empty == 1 ? 'movement has' : 'movements have'} '
                        'nothing logged, so ${empty == 1 ? 'it won\'t' : 'they won\'t'} '
                        'be kept.',
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Finish',
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: AppSpacing.xs),
            AppTextButton(
              label: 'Keep going',
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line about something Finish will leave out.
class _Dropped extends StatelessWidget {
  const _Dropped(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      const Icon(
        Icons.radio_button_unchecked,
        size: 18,
        color: AppColors.textSecondary,
      ),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ),
    ],
  );
}
