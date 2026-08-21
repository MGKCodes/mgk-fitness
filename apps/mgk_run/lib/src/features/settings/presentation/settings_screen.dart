import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../../auth/data/auth_repository.dart';
import '../../legal/data/account_deletion_service.dart';
import '../../legal/domain/account_deleter.dart';
import '../../legal/presentation/delete_account_screen.dart';
import '../../legal/presentation/legal_screen.dart';
import '../../../dev/dev_coach_model_controls.dart';
import '../../../dev/dev_persona_controls.dart';
import '../data/backup_consent_factory.dart';
import '../data/backup_eraser.dart';
import '../domain/backup_consent.dart';
import '../../health/domain/workout_source.dart';
import 'backup_section.dart';
import 'permissions_section.dart';
import '../domain/unit_settings.dart';

/// The shipped version, shown at the foot of Settings.
///
/// A committed constant rather than a read of the bundle: the app takes no
/// dependency it does not need, and the preview harness has no bundle to read.
/// **Keep it in step with `version:` in pubspec.yaml.**
const String kAppVersion = '1.0.0';

/// Settings: **everything about the app rather than about the running.**
///
/// This is where a control belongs if it is not itself training — who is signed
/// in, how distances read, what the app promises about the data, and how to
/// leave. Profile used to lead with the signed-in address and a joined-on date;
/// those are account facts, so they are here, and Profile is about runs.
///
/// There is no row through to Profile any more. Profile is a tab — a row here
/// pointing at a page one tap away was a leftover from when it was not.
///
/// Takes its dependencies as parameters like every other screen here, so it
/// renders against fakes in tests and the preview harness.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.unit,
    required this.settings,
    this.onUnitChanged,
    this.memberSince,
    this.appVersion = kAppVersion,
    this.auth = const AuthRepository(),
    this.deleter = const AccountDeletionService(),
    this.consentStore,
    this.eraser,
    this.health,
  });

  /// Where workouts recorded elsewhere come from.
  ///
  /// Injected so a test can supply a fake, and defaulted to the real HealthKit
  /// reader so the screen works on a device without this being threaded through
  /// the whole app first. Worth wiring properly at the shell once more than one
  /// screen needs it.
  final WorkoutSource? health;

  /// The unit currently in effect.
  final UnitSystem unit;

  final UnitSettings settings;

  /// Called once the new unit is stored, so the app around this screen can
  /// re-render in the chosen units.
  final ValueChanged<UnitSystem>? onUnitChanged;

  /// When the runner's record starts — their first recorded run. Null when they
  /// have not run yet, which simply drops the line rather than inventing a date.
  final DateTime? memberSince;

  /// Shown at the foot of the page. Injectable so a build that reads the real
  /// bundle version can pass it in; [kAppVersion] is the committed fallback.
  final String appVersion;

  final AuthRepository auth;
  final AccountDeleter deleter;

  /// Where the backup answer lives. Defaults to the platform store.
  final BackupConsentStore? consentStore;

  /// Removes what is already stored when consent is withdrawn. Null skips the
  /// erase, which is what the preview harness wants.
  final BackupEraser? eraser;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late UnitSystem _unit = widget.unit;
  bool _saving = false;

  /// What the coach calls them. Held in state rather than read from the
  /// repository on every build so the row updates the moment it is changed,
  /// without waiting on an auth event to come back round.
  late String? _name = widget.auth.currentName;

  late final BackupConsentStore _consentStore =
      widget.consentStore ?? createBackupConsentStore();
  BackupConsent _consent = BackupConsent.unknown;
  bool _consentBusy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadConsent());
  }

  Future<void> _loadConsent() async {
    final value = await _consentStore.read();
    if (mounted) setState(() => _consent = value);
  }

  /// Granting starts the mirror. Withdrawing stops it AND removes what is
  /// already stored — a switch that only stopped future uploads would be a
  /// pause dressed up as a withdrawal.
  Future<void> _setConsent(BackupConsent next) async {
    if (_consentBusy || next == _consent) return;
    setState(() {
      _consent = next;
      _consentBusy = true;
    });
    // Local first, so uploads stop before the erase is attempted rather than
    // racing it.
    await _consentStore.write(next);

    var erased = true;
    if (next == BackupConsent.declined) {
      erased = await widget.eraser?.eraseAll() ?? true;
    }
    if (!mounted) return;
    setState(() => _consentBusy = false);
    if (!erased) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Backup is off, but your stored data could not be removed. '
            'Try again when you have a connection.',
          ),
        ),
      );
    }
  }

  Future<void> _select(UnitSystem unit) async {
    if (unit == _unit || _saving) return;
    setState(() {
      _unit = unit;
      _saving = true;
    });
    // save() is contractually non-throwing and writes locally first, so the
    // choice holds even with no network — no failure branch to show here.
    await widget.settings.save(unit);
    if (!mounted) return;
    setState(() => _saving = false);
    widget.onUnitChanged?.call(unit);
  }

  /// Changes what the coach calls this runner.
  ///
  /// The intro accepts any name at all, on the grounds that a name is not a
  /// format and every rule that rejects one rejects somebody real. That is only
  /// a fair trade if a typo can be put right afterwards, and until this existed
  /// it could not be: the name was written once at sign-up and read back
  /// forever, in the coach's brief, on every screen that greets them.
  ///
  /// Cleared rather than rejected when left blank, so "do not use a name" is a
  /// reachable answer rather than a validation error.
  Future<void> _editName() async {
    // `TextFormField` with an `initialValue` rather than a controller of our
    // own, deliberately: a controller created here has to be disposed here,
    // and disposing it the moment `showDialog` returns kills it while the
    // dialog is still animating out — the field rebuilds against a disposed
    // notifier and throws. This field owns its controller and outlives the
    // route properly.
    var draft = _name ?? '';
    final given = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('What should the coach call you?'),
        content: TextFormField(
          initialValue: draft,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'Your name',
            helperText: 'Leave it empty and the coach will not use a name.',
            // A dialog is narrower than the field this was written for, and
            // helper text is one line unless told otherwise — so the sentence
            // explaining the escape hatch was itself cut off at "will not u...".
            helperMaxLines: 2,
          ),
          onChanged: (v) => draft = v,
          onFieldSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: <Widget>[
          AppTextButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(draft),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // A dismissed dialog pops null, which is not the same as an empty string:
    // one means "changed my mind", the other means "no name, thanks".
    if (given == null || !mounted) return;

    await widget.auth.updateName(given);
    if (!mounted) return;
    setState(() => _name = widget.auth.currentName);
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Sign out?'),
        content: const Text(
          'Your runs stay on this device. Sign back in to sync them.',
        ),
        actions: <Widget>[
          AppTextButton(
            label: 'Stay signed in',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Settings is pushed *over* [AuthGate], so signing out swaps the tree
    // underneath this route while leaving the route itself on top: the dialog
    // closed, the account line still read the same address, and signing out
    // looked like a button that did nothing. Drop back to the root so what the
    // gate just built — the signed-out flow — is what the runner actually sees.
    //
    // Captured before the await rather than read after it: the context may be
    // gone by then, and a navigator cannot be looked up from a dead one.
    final navigator = Navigator.of(context);
    await widget.auth.signOut();
    if (!mounted) return;
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = widget.auth.currentEmail;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: <Widget>[
            // Who is signed in, and since when. Both moved off Profile: they
            // are facts about the account, not about the training.
            if (email != null || widget.memberSince != null)
              Entrance(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.sm,
                    AppSpacing.xl,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SectionLabel('Account'),
                      const SizedBox(height: AppSpacing.sm),
                      if (email != null)
                        Text(
                          email,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (widget.memberSince != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Running with Runio since '
                          '${_monthYear(widget.memberSince!)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],

                      // The only thing onboarding gathers, and until this
                      // existed it was permanent: written once at sign-up and
                      // read back forever.
                      const SizedBox(height: AppSpacing.md),
                      InkWell(
                        onTap: _editName,
                        borderRadius: AppRadius.cardAll,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                          ),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      'Coach calls you',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      // Not "not set", which reads as an error.
                                      // No name is a choice the coach handles.
                                      _name ?? 'Nothing in particular',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: AppColors.textTertiary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: AppColors.textTertiary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const Entrance(
              index: 2,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.xs,
                ),
                child: SectionLabel('Distance'),
              ),
            ),
            Entrance(
              index: 3,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xs,
                  AppSpacing.xl,
                  AppSpacing.sm,
                ),
                child: SegmentedButton<UnitSystem>(
                  segments: const <ButtonSegment<UnitSystem>>[
                    ButtonSegment<UnitSystem>(
                      value: UnitSystem.metric,
                      label: Text('Kilometres'),
                    ),
                    ButtonSegment<UnitSystem>(
                      value: UnitSystem.imperial,
                      label: Text('Miles'),
                    ),
                  ],
                  selected: <UnitSystem>{_unit},
                  showSelectedIcon: false,
                  onSelectionChanged: _saving
                      ? null
                      : (selected) => _select(selected.first),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: Text(
                'Shared with Liftio — changing it here changes it there too. '
                'Your runs are always stored in metric.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                  height: 1.4,
                ),
              ),
            ),

            Entrance(
              index: 5,
              child: SettingsTile(
                icon: Icons.logout,
                title: 'Sign out',
                subtitle: 'Your runs stay on this device',
                showChevron: false,
                onTap: _signOut,
              ),
            ),
            // Also reachable inside Privacy & legal, which is where the law
            // wants it. It is here too because this is where a runner looks for
            // it — a deletion buried one screen deeper reads as hidden.
            Entrance(
              index: 6,
              child: SettingsTile(
                icon: Icons.delete_outline,
                title: 'Delete account',
                subtitle: 'Permanently remove your runs, profile, and plans',
                tint: AppColors.danger,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DeleteAccountScreen(
                      auth: widget.auth,
                      deleter: widget.deleter,
                    ),
                  ),
                ),
              ),
            ),

            const Divider(height: AppSpacing.xxl, color: AppColors.elevated),

            // Above the legal rows rather than inside them: this is a decision
            // the runner makes, not a document they read.
            Entrance(
              index: 4,
              child: BackupSection(
                consent: _consent,
                busy: _consentBusy,
                onChanged: _setConsent,
              ),
            ),

            PermissionsSection(health: widget.health),

            const Divider(height: AppSpacing.xxl, color: AppColors.elevated),

            // Labelled rather than floating. Everything else on this screen
            // sits under a heading; these did not, which made them read as
            // leftovers — and left "Sign out" and "Delete account", both
            // account actions, further from the account than the unit picker.
            const Entrance(
              index: 5,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.xs,
                ),
                child: SectionLabel('About'),
              ),
            ),
            Entrance(
              index: 5,
              child: SettingsTile(
                icon: Icons.shield_outlined,
                title: 'Privacy & legal',
                subtitle: 'Disclaimer, privacy policy, your data',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        LegalScreen(auth: widget.auth, deleter: widget.deleter),
                  ),
                ),
              ),
            ),
            // Debug builds only: enter the app as a seeded runner. Last, under
            // a divider, because it is a tool rather than a setting — and
            // absent entirely from a release bundle.
            if (kDebugMode) ...<Widget>[
              const Divider(height: AppSpacing.xxl, color: AppColors.elevated),
              DevPersonaSection(
                // The shell this screen was pushed over is rebuilt when the
                // persona changes, so going back to a stale route would show
                // the previous runner's app. Return to the new one.
                onSwitched: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
              ),
              // Which model answers. Under the persona because the two
              // compose: pick a runner worth talking about, then ask several
              // models about them and compare.
              const DevCoachModelSection(),
            ],

            const SizedBox(height: AppSpacing.xl),
            Center(
              child: Column(
                children: <Widget>[
                  Text(
                    'Runio ${widget.appVersion}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'MGKCodes',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in a settings list: icon, title, supporting line, chevron.
///
/// Shared so settings and the legal screen cannot drift into two slightly
/// different list rows.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.tint,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Overrides the icon and title colour — for a destructive row, the only
  /// sanctioned use of colour (ADR-0009).
  final Color? tint;

  /// A chevron promises another screen. Turn it off for a row that acts in
  /// place — signing out opens a dialog and stays put.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xs,
      ),
      leading: Icon(icon, color: tint ?? AppColors.textSecondary),
      title: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: tint ?? AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
      trailing: showChevron
          ? const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textTertiary,
            )
          : null,
    );
  }
}

const List<String> _months = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _monthYear(DateTime at) => '${_months[at.month - 1]} ${at.year}';
