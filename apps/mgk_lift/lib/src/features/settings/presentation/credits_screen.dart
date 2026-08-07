import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// Where the app says whose work it is built on.
///
/// **This screen is a licence condition, not a courtesy.** The exercise
/// illustrations are derived from a CC BY-SA 4.0 dataset, and §3(a)(1) of that
/// licence requires the creator, a licence notice, the disclaimer, a link to the
/// original, and a statement that the material was modified — all of which have
/// to survive wherever the images go. §3(a)(2) allows satisfying that "in any
/// reasonable manner based on the medium", and for an app the settled convention
/// is a credits screen, which is what this is.
///
/// So: **do not delete a line from here to tidy it up.** Removing the credit is
/// how the original app ended up claiming sole ownership of work it had adapted.
///
/// Links are selectable text rather than tappable, which keeps a whole
/// dependency out of the app for one screen. The licence asks for "a URI or
/// hyperlink", and a URI someone can copy is a URI.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Credits')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          children: const <Widget>[
            _Credit(
              label: 'Exercise illustrations',
              body:
                  'Adapted from the Everkinetic open exercise dataset by Greg '
                  'Priday, redrawn in a consistent line style with an image '
                  'model. The poses and compositions are theirs.',
              notice:
                  'Original images © Everkinetic, licensed CC BY-SA 4.0.\n'
                  'These adaptations are likewise offered under CC BY-SA 4.0.\n'
                  'Provided as-is, without warranties of any kind.',
              links: <String>[
                'github.com/everkinetic/data',
                'creativecommons.org/licenses/by-sa/4.0/',
              ],
            ),
            SizedBox(height: AppSpacing.xl),
            _Credit(
              label: 'Typeface',
              body: 'Inter, by Rasmus Andersson.',
              notice: 'SIL Open Font License 1.1.',
              links: <String>['rsms.me/inter'],
            ),
            SizedBox(height: AppSpacing.xl),
            _Credit(
              label: 'This app',
              body:
                  'MGK Lift is open source. The code is AGPL-3.0 — if you run a '
                  'modified version as a service, you have to publish your '
                  'changes.',
              notice: 'Built by Matthew Kay under MGKCodes.',
              links: <String>['github.com/MGKCodes/mgk-fitness'],
            ),
          ],
        ),
      ),
    );
  }
}

class _Credit extends StatelessWidget {
  const _Credit({
    required this.label,
    required this.body,
    required this.notice,
    required this.links,
  });

  final String label;
  final String body;

  /// The copyright and licence notice. Kept visually distinct from the prose,
  /// because this is the part the licence actually requires.
  final String notice;

  final List<String> links;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionLabel(label),
        const SizedBox(height: AppSpacing.sm),
        Text(
          body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SelectableText(
                notice,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final link in links)
                SelectableText(
                  link,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                    height: 1.5,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
