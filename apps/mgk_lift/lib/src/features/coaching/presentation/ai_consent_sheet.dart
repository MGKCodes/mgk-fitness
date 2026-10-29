import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../legal/domain/legal_copy.dart';
import '../../legal/presentation/legal_document_screen.dart';
import '../domain/ai_consent.dart';

/// Where the lifter is asked whether their training may go to the AI provider.
///
/// **Before anything is sent, and before the price.** The coach mark, *Build a
/// plan* and a swap mid-session all come through here first (issue #10). It
/// sits after the account, because the answer is kept on one, and before the
/// sales screen, so nobody pays for a coach and then declines to let it see
/// their training.
///
/// Run's sheet, in Lift's words: what it says is *How your coach uses AI* cut
/// to what a lifter needs in order to decide. It names the gateway and not the
/// model vendor, because the model is chosen on the server and can change
/// without a build. Both buttons are plain, and neither is chosen for them.
class AiConsentSheet extends StatelessWidget {
  const AiConsentSheet({super.key});

  static const String title = 'Before your coach answers';

  static const String intro =
      'Your coach is an AI model. To answer you, Lift sends what you ask and '
      'your training to OpenRouter, a service that passes each request to the '
      'AI model provider that writes the reply. Some of what is sent is health '
      'information, so it only goes if you agree.';

  static const List<String> sent = <String>[
    'Your messages to the coach, as you wrote them',
    'A summary of your recent training: the sessions you logged, what you '
        'lifted, and how much',
    'When you ask for a plan: your goal, the days you can train, your '
        'equipment, and injury notes if you gave any',
    'When you ask to swap a movement: the movements in that session',
  ];

  static const List<String> neverSent = <String>[
    'Your name, email or account ID. We do not add them, but a message goes '
        'as you wrote it.',
    'Your progress photos',
  ];

  static const String control =
      'Requests go from our server, not your phone, and ask OpenRouter to use '
      'only providers that do not keep or train on what we send. That is a '
      'control we apply, not a promise we can make for them.';

  static const String withdraw =
      'You can take this back by turning off Use the AI coach in Settings.';

  static const String agreeLabel = 'Agree';
  static const String notNowLabel = 'Not now';

  /// Shows the sheet. True only for "Agree"; "Not now", a back gesture and a
  /// tap on the scrim are all a no, and none of them writes anything.
  static Future<bool> show(BuildContext context) async =>
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const AiConsentSheet(),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium?.copyWith(
      color: AppColors.textSecondary,
      height: 1.45,
    );
    // Solid, like Run's: behind a sheet is a scrim, and this one is read
    // before it is answered.
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.md),
                child: SheetHandle(),
              ),
              // Scrolls, and says so, because the buttons must never be what
              // gets cut off on a small phone with large text.
              Flexible(
                child: ScrollEdgeFade(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(intro, style: body),
                        const SizedBox(height: AppSpacing.lg),
                        const SectionLabel('What is sent'),
                        const SizedBox(height: AppSpacing.sm),
                        for (final line in sent) _Point(line, style: body),
                        const SizedBox(height: AppSpacing.md),
                        const SectionLabel('Never sent'),
                        const SizedBox(height: AppSpacing.sm),
                        for (final line in neverSent) _Point(line, style: body),
                        const SizedBox(height: AppSpacing.md),
                        Text(control, style: body),
                        const SizedBox(height: AppSpacing.sm),
                        Text(withdraw, style: body),
                        AppTextButton(
                          label: 'Read how your coach uses AI',
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const LegalDocumentScreen(
                                document: aiDisclosure,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    PrimaryButton(
                      label: agreeLabel,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppTextButton(
                      label: notNowLabel,
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('•  ', style: style),
        Expanded(child: Text(text, style: style)),
      ],
    ),
  );
}

/// The coach's permission: true when there is a current yes on the account,
/// or the lifter has just given one.
///
/// Asks with [AiConsentSheet] when there is no yes, writes the answer, and
/// reads it back rather than trusting the write: an answer that did not save
/// would let the coach open and then have every request refused.
///
/// The medical disclaimer is not here. Lift's shell asks it at its own doors,
/// once per phone, and a swap in the middle of a session is not a door it
/// belongs at.
Future<bool> ensureCoachConsent(
  BuildContext context, {
  required AiConsentStore consent,
}) async {
  if (await consentGiven(consent)) return true;
  if (!context.mounted) return false;
  if (!await AiConsentSheet.show(context)) return false;
  try {
    await consent.grant();
  } on Object {
    // Checked below, where it can be said.
  }
  if (await consentGiven(consent)) return true;
  if (context.mounted) {
    AppToast.show(
      context,
      "Your answer didn't save, so nothing was sent. Try again.",
    );
  }
  return false;
}
