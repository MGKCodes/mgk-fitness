import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'dev_coach_model.dart';

/// The model picker in Settings — changes which model answers, without a
/// redeploy and without editing a Supabase secret.
///
/// Sits under the persona switcher because the two compose: pick a runner with
/// a history worth talking about, then ask several models about it and compare
/// what comes back.
class DevCoachModelSection extends StatelessWidget {
  const DevCoachModelSection({super.key});

  @override
  Widget build(BuildContext context) {
    assert(kDebugMode, 'DevCoachModelSection must never be built in release');
    final theme = Theme.of(context);
    return ValueListenableBuilder<String?>(
      valueListenable: devCoachModel,
      builder: (context, active, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.xs,
            ),
            child: Text(
              'COACH MODEL',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textTertiary,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _ModelRow(
            title: 'Server default',
            subtitle: 'Whatever COACH_MODEL is set to. How the app ships.',
            selected: active == null,
            onTap: () => setDevCoachModel(null),
          ),
          for (final choice in coachModelChoices)
            _ModelRow(
              title: choice.label,
              subtitle: choice.blurb,
              selected: active == choice.id,
              onTap: () => setDevCoachModel(choice.id),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xs,
              AppSpacing.xl,
              AppSpacing.sm,
            ),
            child: Text(
              'Applies to every coach call from this build. The server honours '
              'it only for models listed in COACH_MODEL_ALLOWLIST, so a choice '
              'here can be refused and quietly fall back to the default.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One selectable model row.
class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check, size: 18, color: AppColors.textPrimary),
          ],
        ),
      ),
    );
  }
}
