import '../../../core/brand.dart';
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
import '../data/backup_health_factory.dart';
import '../domain/backup_consent.dart';
import '../domain/backup_health.dart';
import '../../health/domain/workout_source.dart';
import '../../onboarding/domain/intro_store.dart';
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
    this.backupHealthStore,
    this.eraser,
    this.health,
    this.introStore,
    this.onNameChanged,
    this.ensureAccount,
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

  /// Where the last push's outcome was written down. Defaults to the platform
  /// store, which is the same file `main.dart` hands the backup — this screen
  /// and the push path find it through the factory rather than by being wired
  /// to each other, exactly as they already do for consent. Naming it
  /// `backupHealthStore` rather than `healthStore` because [health] on this
  /// screen is HealthKit, and two unrelated meanings of "health" one field
  /// apart is a trap.
  final BackupHealthStore? backupHealthStore;

  /// Removes what is already stored when consent is withdrawn. Null skips the
  /// erase, which is what the preview harness wants.
  final BackupErasure? eraser;

  /// The other home for the runner's name — the one that answers when there is
  /// no account.
  ///
  /// **The name row used to write to auth metadata and nowhere else**, which
  /// made it useless to exactly the people who had just supplied a name: a
  /// runner with no account saw "Nothing in particular" under a heading that
  /// only appeared if they had already been running, and any correction they
  /// made went into a session that did not exist. The intro records the name
  /// against the install; this is that same store, so the row reads and writes
  /// what the coach is actually using.
  ///
  /// Null keeps an edit in memory for the session.
  final IntroStore? introStore;

  /// Reports a changed name upwards, so the shell that opened this screen stops
  /// handing the coach the old one. Signed in, the auth stream would eventually
  /// say so; signed out there is no stream to say anything.
  final ValueChanged<String?>? onNameChanged;

  /// Raises sign-up and resolves true once there is a session.
  ///
  /// **Backup is the second gate an account stands at**, alongside asking for a
  /// plan. Everything else here works with nobody signed in, because the
  /// on-device database is the source of truth (CLAUDE.md rule 1) — but a
  /// backup switch is a promise to put this runner's data somewhere it can be
  /// attributed to them, and with no account there is no such place. The switch
  /// would have flipped on, written consent, and mirrored nothing.
  ///
  /// Null means the caller has already decided an account is not required —
  /// the preview harness and tests that are not about this.
  final Future<bool> Function()? ensureAccount;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late UnitSystem _unit = widget.unit;
  bool _saving = false;

  /// What the coach calls them. Held in state rather than read from the
  /// repository on every build so the row updates the moment it is changed,
  /// without waiting on an auth event to come back round.
  ///
  /// Seeded from the account, then topped up from the install store once that
  /// read comes back — see [_loadName]. Starting from the account rather than
  /// waiting for both means the row is right immediately for anybody signed in
  /// and right one frame later for anybody not.
  late String? _name = widget.auth.currentName;

  late final IntroStore _introStore =
      widget.introStore ?? InMemoryIntroStore(done: true);

  late final BackupConsentStore _consentStore =
      widget.consentStore ?? createBackupConsentStore();
  BackupConsent _consent = BackupConsent.unknown;
  bool _consentBusy = false;

  late final BackupHealthStore _backupHealthStore =
      widget.backupHealthStore ?? createBackupHealthStore();
  BackupHealth _backupHealth = const BackupHealth();

  @override
  void initState() {
    super.initState();
    unawaited(_loadConsent());
    unawaited(_loadBackupHealth());
    unawaited(_loadName());
  }

  /// Fills in the name for a runner whose account does not hold one.
  ///
  /// The account wins where it has an answer: it is what travels between
  /// devices and what every other reader consults. The install store answers
  /// for the ordinary new case, where there is no account at all.
  Future<void> _loadName() async {
    if (_name != null) return;
    final local = await _introStore.readName();
    if (!mounted || local == null) return;
    setState(() => _name = local);
  }

  Future<void> _loadConsent() async {
    final value = await _consentStore.read();
    if (mounted) setState(() => _consent = value);
  }

  /// Read once on open rather than watched. The backup writes this file from
  /// the push path, which does not run while somebody is sitting on Settings,
  /// so there is nothing to keep up with.
  Future<void> _loadBackupHealth() async {
    final value = await _backupHealthStore.read();
    if (mounted) setState(() => _backupHealth = value);
  }

  /// Granting starts the mirror. Withdrawing stops it AND removes what is
  /// already stored — a switch that only stopped future uploads would be a
  /// pause dressed up as a withdrawal.
  ///
  /// **Granting needs an account first.** The mirror writes rows attributed to
  /// a user; with nobody signed in there is nothing to attribute them to, so
  /// the switch would have read "On" while every push failed on a row-level
  /// policy — the exact shape of promise this section exists to stop the app
  /// making. Withdrawal is never gated: consent must be at least as easy to
  /// take back as it was to give, and somebody who is not signed in has by
  /// definition nothing left to withdraw anyway.
  Future<void> _setConsent(BackupConsent next) async {
    if (_consentBusy || next == _consent) return;

    // Before the optimistic flip below, not after it. Asked afterwards, the
    // switch would slide to On, raise a sign-up, and then have to slide back
    // when it was refused — which reads as the app changing its mind.
    if (next == BackupConsent.granted && !widget.auth.isSignedIn) {
      final signedIn =
          await (widget.ensureAccount?.call() ?? Future<bool>.value(true));
      // The gate pushed a route and awaited it, so this screen may be gone.
      if (!signedIn || !mounted) return;
    }

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

    // **Both homes, every time.** The account is where a name travels from
    // device to device; the install store is where it lives for the runner who
    // has no account, which is now the ordinary one. Writing only the first is
    // what made this row a no-op for most of the people who reach it. Writing
    // only the second would drop the name on a second phone.
    //
    // `updateName` on a signed-out repository would be a round trip with no
    // session behind it, so it is skipped rather than allowed to throw.
    if (widget.auth.isSignedIn) await widget.auth.updateName(given);
    await _introStore.writeName(given);
    if (!mounted) return;

    final trimmed = given.trim();
    final next = trimmed.isEmpty ? null : trimmed;
    setState(() => _name = next);
    widget.onNameChanged?.call(next);
  }

  /// Signs the runner in, or up, from the account section.
  ///
  /// The same gate the backup switch and the plan flow raise, reached
  /// deliberately rather than by walking into it. Somebody who has decided they
  /// want an account should not have to flip a switch they may not want in
  /// order to be offered one.
  Future<void> _createAccount() async {
    await (widget.ensureAccount?.call() ?? Future<bool>.value(false));
    // Rebuilt either way: a completed sign-up changes every row in this
    // section, and a refused one leaves them exactly as they were.
    if (mounted) setState(() {});
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
    final signedIn = widget.auth.isSignedIn;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: <Widget>[
            // **The runner, before the account.**
            //
            // These two rows used to sit under an "Account" heading, behind a
            // condition that hid them unless there was an email or a run on
            // record. Neither is an account fact: the name is what the coach
            // was told in a conversation that no longer ends in an account, and
            // "running since" is read off the log on this phone. Under the old
            // arrangement the ordinary new runner - introduced, signed out, no
            // runs yet - opened Settings and found nothing about themselves at
            // all, including the one thing they had actually been asked for.
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
                    const SectionLabel('You'),
                    const SizedBox(height: AppSpacing.sm),

                    // The only thing onboarding gathers, and until this
                    // existed it was permanent: written once at sign-up and
                    // read back forever.
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
                                    style: theme.textTheme.bodySmall?.copyWith(
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
                    if (widget.memberSince != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Running since ${_monthYear(widget.memberSince!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // **The account, including when there is not one.**
            //
            // This section used to assume one existed: it printed an address,
            // and offered Sign out and Delete account unconditionally. After
            // the app stopped requiring an account, that left a runner who had
            // never made one being offered a way to sign out of nothing and to
            // delete an account that does not exist - two rows that could only
            // fail, in the place somebody looks to find out where they stand.
            Entrance(
              index: 1,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.sm,
                  AppSpacing.xl,
                  AppSpacing.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SectionLabel('Account'),
                    const SizedBox(height: AppSpacing.sm),
                    if (signedIn && email != null)
                      Text(
                        email,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else if (!signedIn)
                      Text(
                        // States the position rather than selling the fix. The
                        // row below says what an account is for; this says what
                        // is true right now, which is the thing somebody came
                        // to this screen to find out.
                        'You do not have one. Everything you have recorded is '
                        'on this phone, and only on this phone.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                          height: 1.4,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // **Immediately under the heading they belong to.**
            //
            // These rows have always been written after the unit picker, which
            // was survivable while "Account" was a block of text at the top of
            // the page. It stopped being survivable when it became a labelled
            // section: the board drew ACCOUNT, then DISTANCE, then Sign out and
            // Delete account — two account actions filed under distance, one
            // heading away from their own.
            if (signedIn) ...<Widget>[
              Entrance(
                index: 2,
                child: SettingsTile(
                  icon: Icons.logout,
                  title: 'Sign out',
                  subtitle: 'Your runs stay on this device',
                  showChevron: false,
                  onTap: _signOut,
                ),
              ),
              // Also reachable inside Privacy & legal, which is where the law
              // wants it. It is here too because this is where a runner looks
              // for it — a deletion buried one screen deeper reads as hidden.
              Entrance(
                index: 3,
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
            ]
            // Exactly the two things an account buys, named as such — the same
            // two gates the app actually raises one at (ADR-0019). Anything
            // more would be selling it.
            else
              Entrance(
                index: 2,
                child: SettingsTile(
                  icon: Icons.person_add_alt,
                  title: 'Create an account',
                  subtitle: 'Back up your training, and ask for a plan',
                  onTap: _createAccount,
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
                'Shared with Lift — changing it here changes it there too. '
                'Your runs are always stored in metric.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                  height: 1.4,
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
                health: _backupHealth,
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
                    '$kProductName ${widget.appVersion}',
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
