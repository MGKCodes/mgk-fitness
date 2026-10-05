import 'package:mgk_run/src/core/brand.dart';
import 'package:flutter/material.dart';

import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/legal/domain/account_deleter.dart';
import 'package:mgk_run/src/features/legal/presentation/delete_account_screen.dart';
import 'package:mgk_run/src/features/legal/presentation/legal_screen.dart';
import 'package:mgk_run/src/features/legal/presentation/medical_disclaimer_screen.dart';

/// Preview harness for the legal / compliance surfaces — no Supabase, no device
/// plugins, so they can be checked on Flutter web from any machine. A developer
/// tool, never shipped. Kept separate from `preview/main.dart` so the two can be
/// worked on independently.
///
/// ```
/// flutter run -t lib/preview/legal_preview.dart -d web-server --web-port 8891
/// #   http://localhost:8891/?screen=legal
/// ```
void main() => runApp(const LegalPreviewApp());

/// A deleter that reports the interesting case: Runio's data went, the shared
/// login stayed because Liftio is using it.
class _SiblingRetainedDeleter implements AccountDeleter {
  @override
  Future<AccountDeletionResult> deleteAccount({
    required DeletionScope scope,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return const AccountDeletionResult(
      accountDeleted: false,
      retainedReason: 'sibling_app_data',
      deletedRows: <String, int>{
        'runio.runs': 10,
        'runio.run_points': 1859,
        'runio.run_splits': 27,
        'runio.runner_profiles': 1,
      },
    );
  }
}

/// The legal screens, also spread into `preview/main.dart`'s map so the single
/// harness on 8888 covers every screen. Kept here because the fakes and this
/// standalone entry point belong together.
final Map<String, WidgetBuilder> legalPreviewScreens = <String, WidgetBuilder>{
  // The settings/legal surface: disclaimer, privacy policy, delete account.
  'legal': (_) => LegalScreen(
    auth: FakeAuthRepository(
      signedIn: true,
      email: 'dev@mgkfitness.mgkcodes.com',
    ),
    deleter: _SiblingRetainedDeleter(),
  ),
  // The disclaimer as the onboarding gate — accept / decline.
  'disclaimer-gate': (context) => MedicalDisclaimerScreen(
    onAcknowledge: () => ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Acknowledged.'))),
    onDecline: () => ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Declined — flow exits.'))),
  ),
  // The same wording read-only, as reached from the legal screen.
  'disclaimer': (_) => const MedicalDisclaimerScreen(),
  // The destructive confirmation on its own. Type DELETE to arm the button.
  'delete': (_) => DeleteAccountScreen(
    auth: FakeAuthRepository(
      signedIn: true,
      email: 'dev@mgkfitness.mgkcodes.com',
    ),
    deleter: _SiblingRetainedDeleter(),
  ),
};

class LegalPreviewApp extends StatelessWidget {
  const LegalPreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    final key = Uri.base.queryParameters['screen'];
    final builder = legalPreviewScreens[key];
    return MaterialApp(
      title: '$kProductName legal preview',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) =>
            builder?.call(context) ??
            _Index(keys: legalPreviewScreens.keys.toList()),
      ),
    );
  }
}

class _Index extends StatelessWidget {
  const _Index({required this.keys});

  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$kProductName · legal preview')),
      body: ListView(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Append ?screen=<key> to the URL:'),
          ),
          for (final k in keys)
            ListTile(dense: true, title: Text(k), subtitle: Text('?screen=$k')),
        ],
      ),
    );
  }
}
