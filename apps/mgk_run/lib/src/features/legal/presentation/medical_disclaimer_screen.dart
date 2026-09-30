import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../domain/legal_copy.dart';
import 'legal_document_view.dart';

/// The medical disclaimer.
///
/// Two modes, one screen, because the wording must be identical in both
/// (`docs/medical-disclaimer.md`):
///  - **gate** — [onAcknowledge] is supplied. The runner must accept before the
///    coach generates anything. Declining backs out via [onDecline].
///  - **reference** — both callbacks null. Reachable any time from the legal
///    screen, with a normal back button.
class MedicalDisclaimerScreen extends StatelessWidget {
  const MedicalDisclaimerScreen({
    super.key,
    this.onAcknowledge,
    this.onDecline,
  });

  /// Called when the runner accepts. Null renders the read-only reference view.
  final VoidCallback? onAcknowledge;

  /// Called when the runner declines at the gate.
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
      // The bottom inset is the panel's to take, not the page's: a SafeArea
      // round the whole column stopped the panel's fill 34pt short of the
      // bottom edge, a strip of page under a bar that looked cut off (board C9,
      // G1). The reference view has no panel and keeps the plain inset.
      body: SafeArea(
        bottom: !_isGate,
        child: Column(
          children: <Widget>[
            if (_isGate)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        // Not "builds a plan": the conversation shows this
                        // gate too now, and it builds nothing.
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
                padding: EdgeInsets.fromLTRB(20, _isGate ? 16 : 8, 20, 24),
              ),
            ),
            if (_isGate)
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  20 + MediaQuery.paddingOf(context).bottom,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.elevated)),
                ),
                child: Column(
                  children: <Widget>[
                    // Full width, like every other step's main action. A bare
                    // FilledButton sizes to its label, so this was a narrow
                    // centred pill under a column of full-width ones.
                    PrimaryButton(
                      label: 'I understand',
                      onPressed: onAcknowledge,
                    ),
                    if (onDecline != null) ...<Widget>[
                      const SizedBox(height: 4),
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
