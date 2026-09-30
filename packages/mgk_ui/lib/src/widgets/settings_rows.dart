import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import 'app_card.dart';
import 'section_label.dart';
import 'sheet_handle.dart';

/// One line of the settings index: what it is, what it is **set to**, and a
/// chevron if there is somewhere to go.
///
/// ## Why the value is on the right rather than under the title
///
/// The screen this replaced gave every row a sentence underneath it — "Your
/// runs stay on this device", "Bring in runs from your watch or another app",
/// a paragraph about health information. Each was true and each was written to
/// be read once, so a runner opening Settings for the fifth time read the same
/// five explanations to find one switch. The page ran to roughly two and a half
/// screens and nothing on it could be checked at a glance.
///
/// A settings index has one job: let somebody see what everything is set to
/// without touching anything. That is what the trailing value does — `Miles`,
/// `Off`, `Location on` — and it is why the subtitles could go rather than
/// merely shrink. The explanation still exists; it moved to the screen where
/// the setting is actually changed, which is where somebody deciding wants it
/// and where somebody auditing does not.
///
/// This is the standard shape in both platforms' own settings apps, for the
/// same reason. Written for Run's Settings and shared when Lift's took the
/// same shape (the redesign's finding 19).
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.value,
    this.onTap,
    this.tint,
    this.trailing,
  });

  final String title;

  /// What it is set to, printed on the right. Null for a row that is an action
  /// rather than a setting — there is no value for "Run setup again".
  final String? value;

  final VoidCallback? onTap;

  /// Colours the title and the value together, for a row reporting something
  /// wrong. Used sparingly: see [AppColors.danger]'s own note and ADR-0009.
  final Color? tint;

  /// Replaces the chevron — a switch, a spinner. A row with its own control
  /// does not also navigate.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color titleColor = tint ?? AppColors.textPrimary;
    final Color valueColor = tint ?? AppColors.textTertiary;

    final row = Padding(
      // 16 rather than 12. The tighter row was chosen when the screen was
      // fighting for vertical space; once the prose moved out it was spending
      // the saving on empty charcoal at the bottom instead. A settings row is
      // a touch target before it is a line of text.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.bodyMedium?.copyWith(color: titleColor),
            ),
          ),
          if (value != null) ...<Widget>[
            const SizedBox(width: AppSpacing.md),
            // Shrinks rather than wraps. A long value ellipsises so the row
            // stays one line high and the column of titles stays a column.
            Flexible(
              child: Text(
                value!,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: valueColor),
              ),
            ),
          ],
          if (trailing != null)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: trailing,
            )
          else if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(left: AppSpacing.xs),
              child: Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textTertiary,
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

/// A group of [SettingsRow]s under one label.
///
/// The rows sit on a card rather than on the page, which is what lets the
/// labels carry less weight: the grouping is visible, so the heading does not
/// have to do the separating on its own.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.sm,
          ),
          child: SectionLabel(label),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// A choice from a few, as a sheet: the options with a tick on the current one,
/// and under them the sentence that explains it.
///
/// **The explanation lives here, not on the index.** Run's distance setting
/// was a segmented control with two lines under it saying it is shared with
/// Lift and that runs are stored in metric; both worth saying, neither worth
/// saying every time somebody opens Settings. So the index shows the value and
/// the sheet says the rest, where the choice is made. Both apps' units use it.
///
/// Returns the option picked, or null if the sheet was dismissed.
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T selected,
  String? note,
}) => showModalBottomSheet<T>(
  context: context,
  backgroundColor: AppColors.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
  ),
  builder: (sheetContext) {
    final theme = Theme.of(sheetContext);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Center(child: SheetHandle()),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            for (final (value, label) in options)
              SettingsRow(
                title: label,
                trailing: value == selected
                    ? const Icon(
                        Icons.check,
                        size: 20,
                        color: AppColors.textPrimary,
                      )
                    : const SizedBox(width: 20),
                onTap: () => Navigator.of(sheetContext).pop(value),
              ),
            if (note != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                note,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  },
);
