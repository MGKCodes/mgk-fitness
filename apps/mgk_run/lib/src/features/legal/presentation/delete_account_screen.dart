import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../data/account_deletion_service.dart';
import '../domain/account_deleter.dart';

/// Account deletion, confirmed properly.
///
/// `docs/compliance.md` requires the user to be able to delete their account and
/// all associated data and have it *actually removed*. That is irreversible, so
/// the gate is a typed confirmation, not a tap: the runner must type `DELETE`.
/// Nothing leaves the screen until they do.
///
/// Afterwards the outcome is stated plainly, including the case the shared
/// MGKCodes login survives because Liftio is using it (ADR-0008), and only then
/// does the session end.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({
    super.key,
    this.auth = const AuthRepository(),
    this.deleter = const AccountDeletionService(),
    this.onSignedOut,
  });

  final AuthRepository auth;
  final AccountDeleter deleter;

  /// Where to go once the session has ended. Defaults to unwinding to the app
  /// root, so the sign-in flow is what remains.
  final VoidCallback? onSignedOut;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  static const _phrase = 'DELETE';

  final TextEditingController _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  AccountDeletionResult? _result;

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  bool get _armed => _confirm.text.trim().toUpperCase() == _phrase;

  Future<void> _delete() async {
    if (!_armed || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.deleter.deleteAccount();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
      });
    } on AccountDeletionException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _finish() async {
    await widget.auth.signOut();
    if (!mounted) return;
    final onSignedOut = widget.onSignedOut;
    if (onSignedOut != null) {
      onSignedOut();
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delete account'),
        automaticallyImplyLeading: result == null && !_busy,
      ),
      body: SafeArea(
        child: result == null ? _buildConfirm(context) : _buildDone(result),
      ),
    );
  }

  Widget _buildConfirm(BuildContext context) {
    final theme = Theme.of(context);
    final email = widget.auth.currentEmail;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.danger,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'This cannot be undone.',
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Deleting removes all of your Runio data from our servers — not '
          'hidden, actually deleted:',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        const _DeletedItem('Every run, with its route points and splits'),
        const _DeletedItem('Your runner profile and generated plans'),
        const _DeletedItem('The date of birth and weight you gave Runio'),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionLabel(
                'About your login',
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: 8),
              Text(
                'Your login is a shared MGKCodes fitness account, so Liftio can '
                'use it too. If it holds no Liftio data we delete the login as '
                'well. If it does, we delete everything Runio holds and keep '
                'only the login, so your Liftio data survives.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (email != null) ...<Widget>[
          Text(
            'Signed in as $email',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text('Type $_phrase to confirm', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _confirm,
          enabled: !_busy,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: _phrase),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 16),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.danger,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: _armed && !_busy ? _delete : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            disabledForegroundColor: AppColors.textTertiary,
            side: BorderSide(
              color: _armed && !_busy ? AppColors.danger : AppColors.elevated,
            ),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Delete my data'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Keep my account'),
        ),
      ],
    );
  }

  Widget _buildDone(AccountDeletionResult result) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: <Widget>[
        const Icon(
          Icons.check_circle_outline,
          size: 40,
          color: AppColors.success,
        ),
        const SizedBox(height: 16),
        Text('Your Runio data is deleted', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(
          result.loginRetainedForSiblingApp
              ? 'Every run, route point, split, and your runner profile have '
                    'been removed from our servers. Your login is still active '
                    'because Liftio is using it — email hello@mgkcodes.com if '
                    'you want that removed too.'
              : 'Every run, route point, split, and your runner profile have '
                    'been removed from our servers, along with your login.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        FilledButton(onPressed: _finish, child: const Text('Done')),
      ],
    );
  }
}

class _DeletedItem extends StatelessWidget {
  const _DeletedItem(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.remove, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
