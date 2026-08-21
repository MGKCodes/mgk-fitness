import '../../../core/brand.dart';
import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../../settings/presentation/settings_screen.dart' show SettingsTile;
import '../data/account_deletion_service.dart';
import '../domain/account_deleter.dart';
import 'delete_account_screen.dart';
import 'medical_disclaimer_screen.dart';
import 'privacy_policy_screen.dart';

/// Privacy & legal: the one place the compliance surfaces are reachable from.
///
/// `docs/compliance.md` wants the privacy policy linked in-app, the medical
/// disclaimer available from settings, and a working deletion path. Those are all
/// data-rights surfaces, so they live together rather than being scattered.
///
/// A self-contained route: push it from anywhere, take dependencies as
/// parameters, so it renders against fakes in tests and the preview.
class LegalScreen extends StatelessWidget {
  const LegalScreen({
    super.key,
    this.auth = const AuthRepository(),
    this.deleter = const AccountDeletionService(),
  });

  final AuthRepository auth;
  final AccountDeleter deleter;

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = auth.currentEmail;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & legal')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: <Widget>[
            if (email != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Text(
                  email,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            SettingsTile(
              icon: Icons.medical_information_outlined,
              title: 'Medical disclaimer',
              subtitle: '$kProductName is not medical advice',
              onTap: () => _push(context, const MedicalDisclaimerScreen()),
            ),
            SettingsTile(
              icon: Icons.shield_outlined,
              title: 'Privacy policy',
              subtitle: 'What we collect, and who we share it with',
              onTap: () => _push(context, const PrivacyPolicyScreen()),
            ),
            const Divider(color: AppColors.elevated, height: 32),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: const SectionLabel(
                'Your data',
                color: AppColors.textTertiary,
              ),
            ),
            SettingsTile(
              icon: Icons.delete_outline,
              title: 'Delete account',
              subtitle: 'Permanently remove your runs, profile, and plans',
              tint: AppColors.danger,
              onTap: () => _push(
                context,
                DeleteAccountScreen(auth: auth, deleter: deleter),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
