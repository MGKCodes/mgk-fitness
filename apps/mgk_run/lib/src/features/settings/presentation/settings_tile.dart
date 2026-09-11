import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// An icon, a title, a sentence, and a chevron.
///
/// **The older row shape, kept for the two screens that still want a
/// sentence.** The settings index moved to [SettingsRow], which puts the VALUE
/// on the right instead of an explanation underneath, because an index exists
/// to be scanned. These are not indexes:
///
///   * [LegalScreen], where each row is a document and the subtitle says which
///     one -- "Terms of use" and "Privacy policy" are not self-explanatory to
///     somebody deciding which to open.
///   * [PermissionsSection], where the subtitle is the permission's actual
///     state in a full sentence. "Off, runs will not record a route" says
///     something the value "Off" cannot.
///
/// It lived inside the settings screen until 2026-09-11 and was imported from
/// there with a `show` clause, which made two screens depend on a third for a
/// widget none of them owns.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.tint,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Overrides the icon and title colour — for a destructive row, the only
  /// sanctioned use of colour (ADR-0009).
  final Color? tint;

  /// A chevron promises another screen. Turn it off for a row that acts in
  /// place — signing out opens a dialog and stays put.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xs,
      ),
      leading: Icon(icon, color: tint ?? AppColors.textSecondary),
      title: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: tint ?? AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
      trailing: showChevron
          ? const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textTertiary,
            )
          : null,
    );
  }
}
