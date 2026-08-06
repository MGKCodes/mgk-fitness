import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../domain/legal_document.dart';

/// Renders a [LegalDocument] in the app's own greyscale typography: the lead in
/// `textPrimary`, section headings as labels, body in `textSecondary`, bullets
/// with a silver marker. No colour — a legal notice signals nothing.
///
/// Scrollable, and shrink-wrapped by the caller's [padding] so it drops into
/// both a full screen and the acknowledgement gate.
class LegalDocumentView extends StatelessWidget {
  const LegalDocumentView({
    super.key,
    required this.document,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 32),
    this.controller,
  });

  final LegalDocument document;
  final EdgeInsetsGeometry padding;

  /// Lets the gate observe scrolling if it ever needs to.
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
          const SizedBox(height: 20),
        ],
        for (final section in document.sections) ...<Widget>[
          if (section.heading != null) ...<Widget>[
            SectionLabel(section.heading!, color: AppColors.textTertiary),
            const SizedBox(height: 8),
          ],
          for (final paragraph in section.paragraphs) ...<Widget>[
            Text(paragraph, style: body),
            const SizedBox(height: 12),
          ],
          for (final bullet in section.bullets) _Bullet(text: bullet),
          const SizedBox(height: 16),
        ],
        if (document.footnote != null) ...<Widget>[
          const Divider(color: AppColors.elevated, height: 32),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            margin: const EdgeInsets.only(top: 8, right: 12),
            width: 4,
            height: 4,
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
