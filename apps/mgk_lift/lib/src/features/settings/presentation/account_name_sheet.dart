import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// Gives the account a name, changes it, or takes it away, from the account
/// screen's *Name* row. True once [save] has gone through; null when the
/// sheet was dismissed.
///
/// **The one place a name is given without being asked for.** Sign-in asks
/// once, after a new account, and never after Sign in with Apple (Run's
/// ADR-0047, amended 19 October 2026); an Apple account, or anybody who
/// skipped, gives it here. Nothing on the way here prompts for it: the row
/// says *Not set* and waits.
///
/// Not `mgk_ui`'s `AccountNameStep`, which is the question after a new
/// account: its *Skip* and a blank field both mean "nothing to write", so it
/// cannot clear a name. Here a blank field and *Save* clears it, and the sheet
/// is dismissed to change nothing.
///
/// Solid, like Settings' other sheets, and lifted over the keyboard, which is
/// up the whole time it is open.
Future<bool?> showAccountNameSheet(
  BuildContext context, {
  required String? current,
  required Future<void> Function(String? name) save,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppColors.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
  ),
  builder: (sheet) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
    child: AccountNameSheet(current: current, save: save),
  ),
);

/// What [showAccountNameSheet] holds. Public so a board can draw it open.
class AccountNameSheet extends StatefulWidget {
  const AccountNameSheet({
    super.key,
    required this.current,
    required this.save,
  });

  /// The name the account has now, which the field starts with.
  final String? current;

  /// Writes the name: trimmed, or null to clear it. Throws when it did not
  /// reach the server, which the sheet says, keeping what was typed.
  final Future<void> Function(String? name) save;

  /// What a test finds the field by.
  static const Key fieldKey = ValueKey<String>('account-name-sheet');

  @override
  State<AccountNameSheet> createState() => _AccountNameSheetState();
}

class _AccountNameSheetState extends State<AccountNameSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.current ?? '',
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final typed = _name.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(typed.isEmpty ? null : typed);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Your name did not save. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Center(child: SheetHandle()),
            const SizedBox(height: AppSpacing.lg),
            Text('Your name', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            // The same promise the step after a new account makes: one name,
            // on the account, so Run shows it too.
            Text(
              'Your first name, the same in both apps. Leave it blank to '
              'remove it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              key: AccountNameSheet.fieldKey,
              controller: _name,
              enabled: !_saving,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              autofillHints: const <String>[AutofillHints.givenName],
              decoration: const InputDecoration(labelText: 'First name'),
              onSubmitted: (_) => _save(),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.danger,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: 'Save', busy: _saving, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
