import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/brand.dart';
import '../../coaching/domain/coach_memory.dart';
import '../../coaching/presentation/coach_memory_screen.dart';
import '../../auth/domain/account.dart';
import '../../legal/domain/account_deleter.dart';
import '../../legal/domain/legal_copy.dart';
import '../../legal/presentation/legal_document_screen.dart';
import '../../legal/presentation/legal_screen.dart';
import '../../sync/presentation/backup_card.dart';
import '../../sync/presentation/backup_scheduler.dart';
import '../../tracking/domain/rest_alerts.dart';
import '../domain/unit_preferences.dart';
import 'account_screen.dart';
import 'credits_screen.dart';

/// The shipped version, shown at the foot of Settings.
///
/// **Keep it in step with `version:` in pubspec.yaml.** Dart cannot read the
/// pubspec at runtime without a plugin, and a wrong version in a bug report is
/// worse than none.
const String kAppVersion = '2.0.0';

/// Everything about the app rather than about the training: who is signed in,
/// how weights read, where backup stands, what the app says about itself.
///
/// **The same index as Run's, because half of it is the same thing.** The
/// profile at the top is the suite's one profile, so it is the suite's one
/// card ([ProfileCard]); the groups under it carry Run's names and order
/// (Preferences, Your data, About), with Lift's own rows inside them; and the
/// foot names the product and its maker the way Run's does. Somebody with both
/// apps should not have to learn Settings twice.
///
/// Deliberately thin. Everything done *to* an account — signing out,
/// restoring, deleting — is one tap in, on the account screen.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.initial,
    this.store,
    this.onChanged,
    this.backup,
    this.isSignedIn = false,
    this.email,
    this.onSignOut,
    this.onSyncNow,
    this.onSignIn,
    this.coachMemory,
    this.useCoach,
    this.onUseCoachChanged,
    this.auth,
    this.deleter,
    this.onAccountGone,
    this.onRestorePurchases,
    this.restAlerts,
    this.version = kAppVersion,
    this.now,
    this.planLabel,
    this.openUrl,
  });

  /// Opens the support page in the browser. Null is the real browser; a test
  /// passes its own, having none.
  final Future<bool> Function(Uri url)? openUrl;

  /// What the account pays for, on its card: `Subscribed` or `Free`. Null in
  /// a build that sells nothing.
  final String? planLabel;

  /// The rest-over alert's permission. Null hides the row: a build with no
  /// notifications has nothing to switch on.
  ///
  /// The session screen offers it once, as a toast beside the first rest. A
  /// lifter who let that go by had no other way back, which for the one
  /// feature the 2026-09-29 research found people complain about most (a
  /// timer they cannot trust) is not good enough. This is the way back.
  final RestAlerts? restAlerts;

  /// What the shell already loaded. Passed in rather than re-read, so opening
  /// Settings cannot briefly show kilograms to somebody who works in pounds.
  final UnitPreferences initial;

  /// Where the choice is persisted. **Null makes the controls read-only**,
  /// which is the honest state for a build with no backend: the setting is
  /// visible and inert rather than accepting a change it will silently lose.
  final UnitPreferencesStore? store;

  /// Reports every change up, so Track logs and Profile reports in the new unit
  /// without waiting for this screen to close.
  final ValueChanged<UnitPreferences>? onChanged;

  /// Where backup stands, live — what is waiting, what was refused, whether a
  /// run is under way. Null is a build with no server, which the card reports
  /// as this phone only.
  final ValueListenable<BackupStatus>? backup;

  final bool isSignedIn;

  /// Shown in the account row. Null when signed out.
  final String? email;

  final VoidCallback? onSignOut;
  final VoidCallback? onSyncNow;
  final VoidCallback? onSignIn;

  /// Where what the coach remembers is read and erased. Null hides the row
  /// entirely rather than showing one that opens an empty screen — there is
  /// nothing to remember without an account.
  final CoachMemoryStore? coachMemory;

  /// Whether the AI coach is switched on. **Null hides the switch**, which is
  /// the honest state for a build with no coach in it — a switch that turns off
  /// something absent is a control with nothing behind it.
  ///
  /// The value is held by the shell rather than here, because turning the coach
  /// off has to remove the mark floating over every surface, not just change a
  /// row on this screen.
  final bool? useCoach;

  final ValueChanged<bool>? onUseCoachChanged;

  /// Passed through to the legal hub, which is where deletion lives. Held
  /// here only because Settings is the route to that screen.
  final AuthService? auth;
  final AccountDeleter? deleter;

  /// See [DeleteAccountScreen.onAccountGone].
  final Future<void> Function()? onAccountGone;

  /// Restore purchases. **Null hides the row**, on the same rule as every other
  /// optional here: a build with no store cannot restore anything.
  ///
  /// It lives beside the account rather than under a Subscription heading of
  /// its own, because a subscription belongs to the login and a heading with
  /// one row under it is a section pretending to be a group. It is also the
  /// second place this appears — the paywalls carry it too — since somebody
  /// looking for it after a reinstall goes to Settings, not to the pitch for a
  /// thing they have already bought.
  final Future<void> Function()? onRestorePurchases;

  final String version;

  /// What "last checked" is measured against, for the account card. Null is the
  /// wall clock, which is what the app passes and what a preview must not.
  final DateTime? now;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late UnitPreferences _prefs = widget.initial;

  /// Whether rest alerts are allowed. Null until the first answer.
  bool? _alertsAllowed;

  /// Set when asking did not turn them on: the prompt is one-shot on iOS and
  /// can be refused for good on Android, and the phone's own settings are
  /// then the only place left.
  bool _alertsRefused = false;

  @override
  void initState() {
    super.initState();
    unawaited(_readAlerts());
  }

  Future<void> _readAlerts() async {
    final alerts = widget.restAlerts;
    if (alerts == null) return;
    final allowed = await alerts.allowed();
    if (!mounted) return;
    setState(() => _alertsAllowed = allowed);
  }

  Future<void> _turnOnAlerts() async {
    final alerts = widget.restAlerts;
    if (alerts == null) return;
    final granted = await alerts.ask();
    if (!mounted) return;
    setState(() {
      _alertsAllowed = granted;
      _alertsRefused = !granted;
    });
  }

  /// Blocks a second change while one is in flight, so two quick taps cannot
  /// race and leave the stored value disagreeing with the screen.
  bool _saving = false;

  Future<void> _update(UnitPreferences next) async {
    final store = widget.store;
    if (store == null || next == _prefs || _saving) return;

    // Applied immediately, not after the write. Changing a display unit is not
    // something to watch a spinner for, and a failed save is reconciled on the
    // next one rather than being worth undoing the screen for.
    setState(() {
      _prefs = next;
      _saving = true;
    });
    widget.onChanged?.call(next);

    await store.save(next);
    if (!mounted) return;
    setState(() => _saving = false);
  }

  /// Who this is, as Run's Settings shows it: a face, the address, and what
  /// they pay for. Lift keeps no photograph of anybody (O1) and asks no name,
  /// so the circle holds the address's first letter.
  ///
  /// Signed out, the card is the way in, and its note is the one fact worth
  /// stating unprompted: what exists on this phone only. It states that and
  /// stops. An account is a thing people already understand.
  Widget _profile(BackupStatus status) {
    if (!widget.isSignedIn) {
      return ProfileCard.withoutAccount(
        avatar: const InitialsAvatar(initials: null, size: 64),
        title: widget.onSignIn == null ? 'Not signed in' : 'Sign in',
        note: phoneOnlyLine(status.pending),
        onTap: widget.onSignIn,
      );
    }
    final email = widget.email;
    return ProfileCard(
      avatar: InitialsAvatar(initials: _initial(email), size: 64),
      // The address, when there is one. Naming the account is also how
      // somebody signed in as the wrong address finds out before they wonder
      // where their training went.
      title: email ?? 'Signed in',
      plan: widget.planLabel,
      onTap: _openAccount,
    );
  }

  static String? _initial(String? email) {
    final e = email?.trim() ?? '';
    return e.isEmpty ? null : e.characters.first.toUpperCase();
  }

  /// Backup, sign out, restore and delete: one tap behind the card (19).
  Future<void> _openAccount() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AccountScreen(
        email: widget.email,
        backup: widget.backup,
        planLabel: widget.planLabel,
        onSyncNow: widget.onSyncNow,
        onSignIn: widget.onSignIn,
        onRestorePurchases: widget.onRestorePurchases,
        onSignOut: widget.onSignOut,
        auth: widget.auth,
        deleter: widget.deleter,
        onAccountGone: widget.onAccountGone,
        now: widget.now,
      ),
    ),
  );

  /// The support page, which both store listings point at.
  Future<void> _openSupport() async {
    final Uri uri = Uri.parse(kSupportUrl);
    final open =
        widget.openUrl ??
        (Uri url) => launchUrl(url, mode: LaunchMode.externalApplication);
    if (await open(uri)) return;
    if (!mounted) return;
    // Says where it is when the browser will not open. A dead support link is
    // worse than a long one.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open support. It is at $uri')),
    );
  }

  Future<void> _pickMass() async {
    final picked = await showChoiceSheet<MassUnit>(
      context,
      title: 'Weight',
      options: const <(MassUnit, String)>[
        (MassUnit.kilograms, 'Kilograms'),
        (MassUnit.pounds, 'Pounds'),
      ],
      selected: _prefs.mass,
      // The two are separate on purpose, and saying so heads off the "why
      // didn't my weights change too" that one switch would cause.
      note:
          'A separate choice from distance — miles with kilograms is '
          'ordinary. Your training is always stored in kilograms and '
          'converted for display, so switching never changes what your '
          'history means.',
    );
    if (picked != null) await _update(_prefs.copyWith(mass: picked));
  }

  Future<void> _pickDistance() async {
    final picked = await showChoiceSheet<UnitSystem>(
      context,
      title: 'Distance',
      // Named for what they are. "Metric" and "Imperial" make a lifter
      // translate; kilometres and miles are the actual choice.
      options: const <(UnitSystem, String)>[
        (UnitSystem.metric, 'Kilometres'),
        (UnitSystem.imperial, 'Miles'),
      ],
      selected: _prefs.distance,
      note:
          'Only affects cardio distances. Shared with Run — changing it here '
          'changes it there too.',
    );
    if (picked != null) await _update(_prefs.copyWith(distance: picked));
  }

  /// A paragraph that used to sit under its row on every visit, now one tap
  /// away (19): true, and worth reading once.
  Future<void> _explain(String title, String body) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
        builder: (sheet) {
          final theme = Theme.of(sheet);
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
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

  static String _massLabel(MassUnit u) =>
      u == MassUnit.kilograms ? 'Kilograms' : 'Pounds';

  static String _distanceLabel(UnitSystem u) =>
      u == UnitSystem.metric ? 'Kilometres' : 'Miles';

  @override
  Widget build(BuildContext context) {
    // Live, so a run started from the account screen, or by a checkpoint
    // while this one is open, is reported as it happens.
    if (widget.backup case final backup?) {
      return ValueListenableBuilder<BackupStatus>(
        valueListenable: backup,
        builder: (context, status, _) => _screen(context, status),
      );
    }
    return _screen(context, const BackupStatus());
  }

  Widget _screen(BuildContext context, BackupStatus status) {
    final theme = Theme.of(context);
    final readOnly = widget.store == null;
    final canChange = !readOnly && !_saving;
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textTertiary,
      height: 1.4,
    );
    final (String backupValue, bool backupNeedsYou) = backupRowValue(status);
    final hasCoach =
        widget.useCoach != null ||
        (widget.isSignedIn && widget.coachMemory != null);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        // A column of a scroll view and a footer, as Run's is: the version
        // belongs at the bottom of the screen, and as a list item it sat
        // wherever the content happened to end.
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                children: <Widget>[
                  // **The profile first (19)**, as Run's Settings has it.
                  Entrance(child: _profile(status)),
                  const SizedBox(height: AppSpacing.lg),

                  // Each row shows what it is set to (19). The explanations
                  // are on the sheet each opens, where the choice is made.
                  Entrance(
                    index: 1,
                    child: SettingsGroup(
                      label: 'Preferences',
                      children: <Widget>[
                        SettingsRow(
                          title: 'Weight',
                          value: _massLabel(_prefs.mass),
                          onTap: canChange ? _pickMass : null,
                        ),
                        SettingsRow(
                          title: 'Distance',
                          value: _distanceLabel(_prefs.distance),
                          onTap: canChange ? _pickDistance : null,
                        ),
                        if (widget.restAlerts != null)
                          SettingsRow(
                            title: 'Rest timer alerts',
                            value: switch (_alertsAllowed) {
                              true => 'On',
                              false when _alertsRefused => 'Not allowed',
                              false => 'Off',
                              null => ' ',
                            },
                            onTap: switch (_alertsAllowed) {
                              false when !_alertsRefused => _turnOnAlerts,
                              false => () => _explain(
                                'Rest timer alerts',
                                "Your phone said no. Turn on notifications "
                                    "for Lift in your phone's settings, and "
                                    "the buzz comes back.",
                              ),
                              true => () => _explain(
                                'Rest timer alerts',
                                'A buzz when rest is over, even with your '
                                    'phone locked. It names the next set, and '
                                    'it is withdrawn when you come back to '
                                    'the app, so there is never a second.',
                              ),
                              null => null,
                            },
                          ),
                      ],
                    ),
                  ),
                  if (readOnly)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        AppSpacing.sm,
                        AppSpacing.xl,
                        0,
                      ),
                      child: Text('Sign in to change these.', style: quiet),
                    ),
                  const SizedBox(height: AppSpacing.xl),

                  // Where backup stands, in a word, where Run's index says
                  // whether backup is on. The sentence, each refusal and
                  // Sync now are on the account screen this opens. Signed out
                  // there is nothing to report that the card has not said.
                  if (widget.isSignedIn) ...<Widget>[
                    Entrance(
                      index: 2,
                      child: SettingsGroup(
                        label: 'Your data',
                        children: <Widget>[
                          SettingsRow(
                            title: 'Backup',
                            value: backupValue,
                            tint: backupNeedsYou ? AppColors.danger : null,
                            onTap: _openAccount,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],

                  if (hasCoach) ...<Widget>[
                    Entrance(
                      index: 3,
                      child: SettingsGroup(
                        label: 'Coach',
                        children: _coachRows(context, quiet),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],

                  Entrance(
                    index: 4,
                    child: SettingsGroup(
                      label: 'About',
                      children: <Widget>[
                        SettingsRow(title: 'Support', onTap: _openSupport),
                        SettingsRow(
                          title: 'Privacy & legal',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => LegalScreen(
                                email: widget.email,
                                auth: widget.auth,
                                deleter: widget.deleter,
                                onAccountGone: widget.onAccountGone,
                              ),
                            ),
                          ),
                        ),
                        SettingsRow(
                          title: 'Credits',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const CreditsScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // The product and its maker, in the words Run's foot uses.
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                '$kProductName ${widget.version} · MGKCodes',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _coachRows(BuildContext context, TextStyle? quiet) => <Widget>[
    if (widget.useCoach case final bool on)
      // A consent control, so the row still says in one line where the words
      // go. What exactly is sent is behind the info button, and the full
      // disclosure is the next row.
      SwitchListTile(
        value: on,
        onChanged: widget.onUseCoachChanged,
        contentPadding: const EdgeInsets.only(
          left: AppSpacing.xl,
          right: AppSpacing.md,
        ),
        title: Row(
          children: <Widget>[
            const Flexible(child: Text('Use the AI coach')),
            AppIconButton(
              icon: Icons.info_outline,
              tooltip: 'What is sent',
              size: 18,
              color: AppColors.textTertiary,
              visualDensity: VisualDensity.compact,
              onPressed: () => _explain(
                'What the coach is sent',
                'Your messages, a summary of your recent training, and your '
                    'injury notes if you gave any. Off means none of it '
                    'leaves the app, and the coach mark goes away with it — '
                    'logging, plans you already have, photos and syncing all '
                    'keep working.',
              ),
            ),
          ],
        ),
        subtitle: Text(
          on
              ? 'On. What you write is sent to OpenRouter.'
              : 'Off. Nothing is sent to OpenRouter.',
          style: quiet,
        ),
      ),
    if (widget.useCoach != null)
      SettingsRow(
        // Reachable from beside the switch as well as from the legal hub:
        // somebody deciding whether to turn it off is exactly who the
        // disclosure is for.
        title: aiDisclosure.title,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const LegalDocumentScreen(document: aiDisclosure),
          ),
        ),
      ),
    if (widget.isSignedIn && widget.coachMemory != null)
      SettingsRow(
        // The title is where the app says the coach remembers at all, so a
        // lifter who never opens it still learns it.
        title: 'What your coach remembers',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CoachMemoryScreen(store: widget.coachMemory!),
          ),
        ),
      ),
  ];
}

/// One row in a settings list: icon, title, supporting line, chevron.
///
/// Deliberately the same row as Run's, so the two apps' settings do not drift
/// into two slightly different lists.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.showChevron = true,
    this.tint,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Colours the icon and title. Greyscale is the rule (ADR-0009) and status is
  /// the sanctioned exception — a row that erases an account is status.
  final Color? tint;

  /// A chevron promises another screen. Turn it off for a row that does not
  /// go anywhere.
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
          fontWeight: FontWeight.w600,
          color: tint,
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
