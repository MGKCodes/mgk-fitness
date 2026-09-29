import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../legal/domain/disclaimer_store.dart';
import '../../legal/presentation/medical_disclaimer_screen.dart';
import '../../legal/presentation/privacy_policy_screen.dart';
import '../domain/ai_consent.dart';

/// Where the runner is asked whether their training may go to the AI provider.
///
/// **Before anything is sent, and before the price.** Every way into the coach
/// comes through here first: the coach mark, every "ask the coach", and "Build
/// a plan". It sits after the account, because the answer is kept on one, and
/// before the paywall, so nobody pays for a coach and then declines to let it
/// see their training.
///
/// What it says is the privacy policy's OpenRouter paragraph, cut to what a
/// runner needs in order to decide. It names the gateway and not the model
/// vendor, because the model is chosen on the server and can change without a
/// build. Both buttons are plain, and neither is chosen for them.
class AiConsentSheet extends StatelessWidget {
  const AiConsentSheet({super.key});

  static const String title = 'Before your coach answers';

  static const String intro =
      'Your coach is an AI model. To answer you, Run sends your training to '
      'OpenRouter, a service that passes each request to the AI model provider '
      'that writes the reply. Some of what is sent is health information, so '
      'it only goes if you agree.';

  static const List<String> sent = <String>[
    'Your training profile: your goal, weekly volume, the days you can run, '
        'a recent race or time trial, and injury notes if you gave any',
    'Your plan, and plans you have finished',
    'Your recent runs: date, distance, time and pace',
    'Your messages to the coach, a short summary of past conversations, and '
        'a few older messages it recalls',
  ];

  static const List<String> neverSent = <String>[
    'Your name, email or account ID. We do not add them, but a message goes '
        'as you wrote it.',
    'Your GPS routes',
  ];

  static const String control =
      'Requests go from our server, not your phone, and ask OpenRouter to use '
      'only providers that do not keep or train on what we send. That is a '
      'control we apply, not a promise we can make for them.';

  static const String withdraw =
      'You can take this back in Settings › Privacy & legal.';

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
    // Solid, like the gate and the conversation: behind a sheet is a scrim.
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
              // Scrolls, because the buttons must never be what gets cut off on
              // a small phone with large text.
              Flexible(
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
                        label: 'Read the privacy policy',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PrivacyPolicyScreen(),
                          ),
                        ),
                      ),
                    ],
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

/// Everything the coach needs settled before it may send: the runner's
/// permission for the AI provider, and then the medical disclaimer if this
/// phone has not had it acknowledged.
///
/// **Two questions, asked one after the other, never as one.** Agreeing to
/// where data goes and acknowledging that a plan is not medical advice are
/// different things to agree to, and a single button covering both would make
/// neither answer clear. The disclaimer is the same screen `CoachFlow` gates on,
/// word for word, so the plan path and the conversation cannot drift apart. It
/// used to exist only on the plan path; the conversation never showed it.
///
/// Each is written when it is answered, so a runner who agrees and then backs
/// out of the disclaimer is asked only the disclaimer next time.
///
/// Returns true when both are in place. False means stop: nothing has been
/// sent, and the runner is back where they were.
Future<bool> ensureCoachConsent(
  BuildContext context, {
  required AiConsentStore consent,
  required DisclaimerStore disclaimer,
}) async {
  if (!await consent.isGranted()) {
    if (!context.mounted) return false;
    if (!await AiConsentSheet.show(context)) return false;
    try {
      await consent.grant();
    } catch (_) {
      // Checked below, where it can be said.
    }
    // Read back rather than trusted. An answer that did not save would let the
    // conversation open and then have every request refused.
    if (!await consent.isGranted()) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              "Your answer didn't save, so nothing was sent. Try again.",
            ),
          ),
        );
      }
      return false;
    }
  }

  if (!await disclaimer.isAcknowledged()) {
    if (!context.mounted) return false;
    final understood = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (routeContext) => MedicalDisclaimerScreen(
          onAcknowledge: () => Navigator.of(routeContext).pop(true),
          onDecline: () => Navigator.of(routeContext).pop(false),
        ),
      ),
    );
    if (understood != true) return false;
    await disclaimer.acknowledge();
  }
  return true;
}
