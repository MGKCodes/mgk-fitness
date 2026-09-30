import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/legal_document.dart';

/// Renders a [LegalDocument] in the app's own greyscale typography: the lead in
/// `textPrimary`, section headings as labels, body in `textSecondary`, bullets
/// with a silver marker. No colour — a legal notice signals nothing (ADR-0009).
///
/// Spacing comes from [AppSpacing] rather than the numbers run's copy of this
/// file uses. That is the one deliberate difference: the punch list's whole
/// lesson was that this app hand-rolls what the shared package already owns, so
/// a new file arriving with eight raw pixel values would be the same defect
/// landing again.
class LegalDocumentView extends StatelessWidget {
  const LegalDocumentView({
    super.key,
    required this.document,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.sm,
      AppSpacing.xl,
      AppSpacing.xxl,
    ),
    this.controller,
  });

  final LegalDocument document;
  final EdgeInsetsGeometry padding;

  /// Lets a caller observe scrolling — a gate that wants the reader to reach
  /// the bottom before a button enables, if one is ever added.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium?.copyWith(
      color: AppColors.textSecondary,
      height: 1.5,
    );

    return ListView(
      controller: controller,
      padding: padding,
      children: <Widget>[
        if (document.lead != null) ...<Widget>[
          Text(
            document.lead!,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        for (final section in document.sections) ...<Widget>[
          if (section.heading != null) ...<Widget>[
            SectionLabel(section.heading!, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.sm),
          ],
          for (final paragraph in section.paragraphs) ...<Widget>[
            Text(paragraph, style: body),
            const SizedBox(height: AppSpacing.md),
          ],
          for (final bullet in section.bullets) _Bullet(text: bullet),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (document.footnote != null) ...<Widget>[
          const Divider(color: AppColors.elevated, height: AppSpacing.xxl),
          Text(
            document.footnote!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            margin: const EdgeInsets.only(
              top: AppSpacing.sm,
              right: AppSpacing.md,
            ),
            width: AppSpacing.xs,
            height: AppSpacing.xs,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
