import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/legal_copy.dart';
import 'legal_document_view.dart';

/// The medical disclaimer, as Run's coach asks it (5 October 2026).
///
/// Two modes, one screen, so the wording is identical in both:
///  - **gate**: [onAcknowledge] is given. The lifter accepts before the coach
///    answers anything or builds a plan; declining backs out via [onDecline].
///  - **reference**: both callbacks null. Reachable any time from Privacy &
///    legal, with a normal back button.
class MedicalDisclaimerScreen extends StatelessWidget {
  const MedicalDisclaimerScreen({
    super.key,
    this.onAcknowledge,
    this.onDecline,
  });

  /// Called when the lifter accepts. Null draws the read-only reference.
  final VoidCallback? onAcknowledge;

  /// Called when the lifter declines at the gate.
  final VoidCallback? onDecline;

  bool get _isGate => onAcknowledge != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isGate ? 'Before we start' : medicalDisclaimer.title),
        automaticallyImplyLeading: !_isGate,
        leading: _isGate && onDecline != null
            ? AppIconButton(
                icon: Icons.close,
                tooltip: 'Not now',
                onPressed: onDecline,
              )
            : null,
      ),
      // The bottom inset is the panel's to take, not the page's, so its fill
      // reaches the bottom edge (Run's board C9). The reference has no panel
      // and keeps the plain inset.
      body: SafeArea(
        bottom: !_isGate,
        child: Column(
          children: <Widget>[
            if (_isGate)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xs,
                  AppSpacing.xl,
                  0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: AppSpacing.sm + 2),
                    Expanded(
                      child: Text(
                        'Read this before you start with the coach.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: LegalDocumentView(
                document: medicalDisclaimer,
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  _isGate ? AppSpacing.lg : AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
              ),
            ),
            if (_isGate)
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.elevated)),
                ),
                child: Column(
                  children: <Widget>[
                    PrimaryButton(
                      label: 'I understand',
                      onPressed: onAcknowledge,
                    ),
                    if (onDecline != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.xs),
                      AppTextButton(label: 'Not now', onPressed: onDecline),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
