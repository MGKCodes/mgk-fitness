import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'dev_persona.dart';

/// The persona buttons offered on the sign-in screen, under the existing
/// developer quick-sign-in row.
///
/// **Never built in release.** Every call site is guarded by [kDebugMode], and
/// the widget asserts it rather than trusting the guard, so a future call site
/// that forgets cannot quietly ship a seeded-data control.
class DevPersonaButtons extends StatelessWidget {
  const DevPersonaButtons({
    super.key,
    required this.busy,
    required this.onSelected,
  });

  final bool busy;

  /// Given the chosen persona. The caller signs in — this widget knows nothing
  /// about auth.
  final ValueChanged<DevPersona> onSelected;

  @override
  Widget build(BuildContext context) {
    assert(kDebugMode, 'DevPersonaButtons must never be built in release');
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Enter as',
          style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final persona in DevPersona.values)
              OutlinedButton(
                onPressed: busy ? null : () => onSelected(persona),
                child: Text(persona.label),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Seeded data, on this device only. Never synced.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textTertiary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// The persona switcher in Settings — changes who you are without signing out.
///
/// Listens to [devPersona] rather than holding its own copy, so it agrees with
/// the sign-in screen and with whatever the app root is actually rendering.
class DevPersonaSection extends StatelessWidget {
  const DevPersonaSection({super.key, this.onSwitched});

  /// Called after the persona changes. Settings uses it to pop back to the
  /// shell — the screen this sits on was pushed over the *previous* shell, and
  /// switching rebuilds that shell underneath it.
  final VoidCallback? onSwitched;

  @override
  Widget build(BuildContext context) {
    assert(kDebugMode, 'DevPersonaSection must never be built in release');
    final theme = Theme.of(context);
    return ValueListenableBuilder<DevPersona?>(
      valueListenable: devPersona,
      builder: (context, active, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.xs,
            ),
            child: Text(
              'DEVELOPER',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textTertiary,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _PersonaRow(
            title: 'Off — your real data',
            subtitle: 'Runs and plans from Supabase, as shipped.',
            selected: active == null,
            onTap: () => _select(null, active),
          ),
          for (final persona in DevPersona.values)
            _PersonaRow(
              title: persona.label,
              subtitle: persona.blurb,
              selected: active == persona,
              onTap: () => _select(persona, active),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xs,
              AppSpacing.xl,
              AppSpacing.sm,
            ),
            child: Text(
              'Seeded runs, plans and coach memory, built on this device. '
              'Nothing here is written to Supabase, and none of it is your '
              'account’s real data.',
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

  void _select(DevPersona? next, DevPersona? active) {
    if (next == active) return;
    setDevPersona(next);
    onSwitched?.call();
  }
}

/// One selectable persona row.
class _PersonaRow extends StatelessWidget {
  const _PersonaRow({
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
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xs,
      ),
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        size: 20,
        color: selected ? AppColors.textPrimary : AppColors.textTertiary,
      ),
      title: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}
