import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../settings/presentation/settings_screen.dart' show SettingsTile;
import '../domain/legal_copy.dart';
import 'legal_document_screen.dart';

/// Privacy & legal: the one place the compliance surfaces are reachable from.
///
/// The three documents are data-rights surfaces, so they live together rather
/// than being scattered across Settings. Deliberately the same shape as run's
/// legal screen, so the two apps do not present compliance differently.
///
/// A self-contained route: push it from anywhere, take what it shows as
/// parameters, so it renders against fakes in tests and in the preview.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, this.email});

  /// Shown at the top when signed in, so it is obvious which account the
  /// rights below apply to. Null when signed out, which is an ordinary state
  /// here — tracking works without an account, and the documents are readable
  /// before anybody has one.
  final String? email;

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & legal')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          children: <Widget>[
            if (email != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.lg,
                ),
                child: Text(
                  email!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            SettingsTile(
              icon: Icons.description_outlined,
              title: termsOfUse.title,
              subtitle: 'What you agree to by using the app',
              onTap: () => _push(
                context,
                const LegalDocumentScreen(document: termsOfUse),
              ),
            ),
            SettingsTile(
              icon: Icons.shield_outlined,
              title: privacyPolicy.title,
              subtitle: 'What we collect, and who we share it with',
              onTap: () => _push(
                context,
                const LegalDocumentScreen(document: privacyPolicy),
              ),
            ),
            SettingsTile(
              icon: Icons.auto_awesome_outlined,
              title: aiDisclosure.title,
              // The subtitle names the provider rather than saying "learn
              // more". Somebody who never opens the screen should still leave
              // this list knowing their words go to a third party.
              subtitle: 'What is sent to OpenRouter, and what is not',
              onTap: () => _push(
                context,
                const LegalDocumentScreen(document: aiDisclosure),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
