import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../coaching/domain/coach_memory.dart';
import '../../coaching/presentation/coach_memory_screen.dart';
import '../../auth/domain/account.dart';
import '../../legal/domain/account_deleter.dart';
import '../../legal/domain/legal_copy.dart';
import '../../legal/presentation/legal_document_screen.dart';
import '../../legal/presentation/legal_screen.dart';
import '../../purchases/presentation/restore_button.dart';
import '../../sync/presentation/account_section.dart';
import '../../sync/presentation/backup_scheduler.dart';
import '../../tracking/domain/rest_alerts.dart';
import '../domain/unit_preferences.dart';
import 'credits_screen.dart';

/// The shipped version, shown at the foot of Settings.
///
/// **Keep it in step with `version:` in pubspec.yaml.** Dart cannot read the
/// pubspec at runtime without a plugin, and a wrong version in a bug report is
/// worse than none.
const String kAppVersion = '2.0.0';

/// Units, and the credits the licence requires.
///
/// Deliberately thin. Everything an account owns — email, deletion, the plan —
/// belongs with the account rather than here.
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
  });

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

  Widget _account(BackupStatus status) => AccountSection(
    status: status,
    isSignedIn: widget.isSignedIn,
    email: widget.email,
    onSyncNow: widget.onSyncNow,
    onSignIn: widget.onSignIn,
    now: widget.now,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readOnly = widget.store == null;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: <Widget>[
            const _Heading('Units'),

            _Choice<UnitSystem>(
              label: 'Distance',
              // Named for what they are. "Metric" and "Imperial" make a lifter
              // translate; kilometres and miles are the actual choice.
              options: const <UnitSystem, String>{
                UnitSystem.metric: 'Kilometres',
                UnitSystem.imperial: 'Miles',
              },
              value: _prefs.distance,
              enabled: !readOnly && !_saving,
              onChanged: (v) => _update(_prefs.copyWith(distance: v)),
              note:
                  'Only affects cardio distances. Shared with Run — changing it '
                  'here changes it there too.',
            ),

            _Choice<MassUnit>(
              label: 'Weight',
              options: const <MassUnit, String>{
                MassUnit.kilograms: 'Kilograms',
                MassUnit.pounds: 'Pounds',
              },
              value: _prefs.mass,
              enabled: !readOnly && !_saving,
              onChanged: (v) => _update(_prefs.copyWith(mass: v)),
              // The two are separate on purpose, and saying so heads off the
              // "why didn't my weights change too" that one switch would cause.
              note:
                  'A separate choice from distance — miles with kilograms is '
                  'ordinary. Your training is always stored in kilograms and '
                  'converted for display, so switching never changes what your '
                  'history means.',
            ),

            if (readOnly)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                child: Text(
                  'Sign in to change these.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),

            if (widget.restAlerts != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              const _Heading('Workout'),
              SettingsTile(
                icon: Icons.timer_outlined,
                title: 'Rest timer alerts',
                subtitle: switch (_alertsAllowed) {
                  true =>
                    'On. A buzz when rest is over, even with your phone '
                        'locked.',
                  false when _alertsRefused =>
                    'Your phone said no. Turn on notifications for Lift in '
                        "your phone's settings.",
                  false => 'Off. Tap to get a buzz when rest is over.',
                  null => ' ',
                },
                onTap: _alertsAllowed == false && !_alertsRefused
                    ? _turnOnAlerts
                    : null,
                showChevron: false,
              ),
            ],

            const SizedBox(height: AppSpacing.lg),
            // One section, not two. The old screen had a "Backup" card and an
            // "Account" row three headings apart, which said the account was a
            // backup and the identity was something else. It is one thing.
            const _Heading('Account'),
            // Live, so a run started here — or by a checkpoint while the
            // screen is open — is reported as it happens.
            if (widget.backup case final backup?)
              ValueListenableBuilder<BackupStatus>(
                valueListenable: backup,
                builder: (context, status, _) => _account(status),
              )
            else
              _account(const BackupStatus()),
            if (widget.isSignedIn)
              SettingsTile(
                icon: Icons.logout,
                title: 'Sign out',
                // Says what survives, because the fear this row triggers is
                // that signing out is a way to lose something.
                subtitle: 'Your training stays on this phone',
                onTap: widget.onSignOut,
                showChevron: false,
              ),

            if (widget.onRestorePurchases != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: RestorePurchasesButton(
                    onRestore: widget.onRestorePurchases,
                  ),
                ),
              ),

            if (widget.useCoach != null ||
                (widget.isSignedIn && widget.coachMemory != null)) ...<Widget>[
              const _Heading('Coach'),

              if (widget.useCoach case final bool on) ...<Widget>[
                SwitchListTile(
                  value: on,
                  onChanged: widget.onUseCoachChanged,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  title: const Text('Use the AI coach'),
                  subtitle: Text(
                    on
                        ? 'On. What you write is sent to OpenRouter.'
                        : 'Off. Nothing is sent to OpenRouter.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                      height: 1.4,
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
                    // Named plainly, and it names what is actually at stake.
                    // "Enable AI features" would be a category; the sentence a
                    // lifter needs is the one about their own words.
                    'Your messages, a summary of your recent training, and your '
                    'injury notes if you gave any. Off means none of it leaves '
                    'the app, and the coach mark goes away with it — logging, '
                    'plans you already have, photos and syncing all keep '
                    'working.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                      height: 1.4,
                    ),
                  ),
                ),
                SettingsTile(
                  icon: Icons.auto_awesome_outlined,
                  title: aiDisclosure.title,
                  // Reachable from beside the switch as well as from the legal
                  // hub. Somebody deciding whether to turn it off is exactly
                  // who the disclosure is for, and making them go and find it
                  // under About is how a disclosure becomes decorative.
                  subtitle: 'What is sent, and what is not',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const LegalDocumentScreen(document: aiDisclosure),
                    ),
                  ),
                ),
              ],

              if (widget.isSignedIn && widget.coachMemory != null)
                SettingsTile(
                  icon: Icons.psychology_outlined,
                  title: 'What your coach remembers',
                  // The subtitle is where the app says the coach remembers at
                  // all. A lifter who never opens the screen should still learn
                  // it from the row.
                  subtitle: 'Read it, or clear it',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          CoachMemoryScreen(store: widget.coachMemory!),
                    ),
                  ),
                ),
            ],

            const SizedBox(height: AppSpacing.lg),
            const _Heading('About'),

            SettingsTile(
              icon: Icons.policy_outlined,
              title: 'Privacy & legal',
              subtitle: 'Terms, privacy policy, how your coach uses AI',
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
            SettingsTile(
              icon: Icons.workspace_premium_outlined,
              title: 'Credits',
              subtitle: 'Exercise illustrations, typeface, licences',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const CreditsScreen()),
              ),
            ),
            SettingsTile(
              icon: Icons.info_outline,
              title: 'Version',
              subtitle: widget.version,
              showChevron: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.lg,
      AppSpacing.xl,
      AppSpacing.xs,
    ),
    child: SectionLabel(text),
  );
}

/// One labelled either/or, with the sentence explaining what it does under it.
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.options,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.note,
  });

  final String label;
  final Map<T, String> options;
  final T value;
  final bool enabled;
  final ValueChanged<T> onChanged;
  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          // Full width, so Distance and Weight line up instead of each sizing
          // to its own longest word — and so the halves are big enough to hit
          // without looking.
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              segments: <ButtonSegment<T>>[
                for (final entry in options.entries)
                  ButtonSegment<T>(value: entry.key, label: Text(entry.value)),
              ],
              selected: <T>{value},
              showSelectedIcon: false,
              onSelectionChanged: enabled
                  ? (selected) => onChanged(selected.first)
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            note,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
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
