import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../domain/unit_preferences.dart';
import 'credits_screen.dart';

/// The shipped version, shown at the foot of Settings.
///
/// **Keep it in step with `version:` in pubspec.yaml.** Dart cannot read the
/// pubspec at runtime without a plugin, and a wrong version in a bug report is
/// worse than none.
const String kAppVersion = '0.1.0';

/// Units, and the credits the licence requires.
///
/// Deliberately thin. Everything an account owns — email, deletion, the plan —
/// belongs with the account rather than here, and Lift has no auth yet.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.initial,
    this.store,
    this.onChanged,
    this.version = kAppVersion,
  });

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

  final String version;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late UnitPreferences _prefs = widget.initial;

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

            const SizedBox(height: AppSpacing.lg),
            const _Heading('About'),

            SettingsTile(
              icon: Icons.workspace_premium_outlined,
              title: 'Credits',
              subtitle: 'Exercise illustrations, typeface, licences',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CreditsScreen(),
                ),
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
          SegmentedButton<T>(
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
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

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
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
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
