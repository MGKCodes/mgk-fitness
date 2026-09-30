import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/backup_consent.dart';
import '../domain/backup_health.dart';

/// The backup decision, on a screen of its own.
///
/// ## Why this is not still a switch on the settings index
///
/// It was, with three paragraphs under it, and those paragraphs were not
/// decoration. Backing up sends **special-category health data** under UK GDPR
/// — runs, routes, heart rate, injury notes, and everything said to the coach —
/// so the consent has to be informed, and the text was the informing.
///
/// That produced a bind. The index needed the text to keep the consent honest,
/// and the text was most of why the index could not be read at a glance.
///
/// **The way out is to move the switch, not the words.** There is already a
/// prompt that explains all of this properly — `BackupConsentPrompt`, shown
/// when the app asks — but it is only reached on the paths where the app
/// raises the question. A runner who found the switch in Settings and flipped
/// it got no prompt at all, so the paragraph beside it was the entire
/// disclosure on that path. Deleting it to tidy the index would have quietly
/// removed the only thing making that consent informed.
///
/// So the switch came here, where the explanation can be as long as it needs
/// to be and nobody reads it who is not deciding. The index now carries one
/// word — `On` or `Off` — which is what somebody checking wants, and this
/// screen carries the rest, which is what somebody changing it wants.
class BackupScreen extends StatelessWidget {
  const BackupScreen({
    super.key,
    required this.consent,
    required this.health,
    required this.busy,
    required this.onChanged,
  });

  final BackupConsent consent;
  final BackupHealth health;
  final bool busy;
  final ValueChanged<BackupConsent> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyDim = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textTertiary,
      height: 1.5,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Back up my data')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: SettingsRow(
                title: 'Back up my data',
                trailing: Switch(
                  value: consent.allowsBackup,
                  onChanged: busy
                      ? null
                      : (on) => onChanged(
                          on ? BackupConsent.granted : BackupConsent.declined,
                        ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Named plainly. A runner deciding whether to upload their injury
            // notes and their conversations with the coach is entitled to know
            // that is what the switch covers, rather than "your activity".
            Text(
              'Runs, routes, heart rate, your plan and what the coach '
              'remembers about you. This is health information, so it is only '
              'sent if you say so, and turning it off deletes what has already '
              'been stored.',
              style: bodyDim,
            ),
            const SizedBox(height: AppSpacing.md),
            // "Off, everything stays on this phone" was false twice over:
            // the coach sends training to the AI provider whatever this
            // switch says, and the phone's own backup can hold a copy. What
            // the switch decides is our servers.
            Text(
              'Off, none of it is kept on our servers, so a lost phone loses '
              "it unless the phone's own backup has it. On, you can pick up on "
              'a new one.',
              style: bodyDim,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Using the coach is separate: it sends what it needs to answer '
              'when you use it, whether this is on or off, and it asks first.',
              style: bodyDim,
            ),

            if (consent.allowsBackup && _lastAttempt != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              Text(
                _lastAttempt!,
                style: theme.textTheme.bodySmall?.copyWith(
                  // Tinted only when something is wrong, which is the
                  // sanctioned use of colour (ADR-0009). A successful backup
                  // is a fact, not an event.
                  color: health.isFailing
                      ? AppColors.danger
                      : AppColors.textTertiary,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// What the last push did, shown only while backup is on: a runner who
  /// declined has no backup to report on, and telling them one failed would be
  /// reporting a promise nobody made.
  ///
  /// Moved here verbatim from `BackupSection`, wording included. A failed
  /// backup is worth being discoverable and is not worth alarming about — it
  /// is usually repaired by the next launch, and nothing is lost meanwhile
  /// because the phone is the authority (ADR-0023).
  String? get _lastAttempt {
    if (health.isFailing) {
      // "the app" rather than the product name — docs/naming.md retired Runio
      // as a user-facing name, and a bare "Run" reads as the noun.
      return 'The last backup did not go through. Your runs are safe on this '
          'phone, and the app will try again next time you open it.';
    }
    final at = health.lastSucceededAt;
    if (at == null) return null;
    return 'Last backed up ${_shortDate(at)}.';
  }
}

/// Abbreviated, matching the log's own dates (`RunTile`) rather than full
/// month names — this is a supporting line, not a heading.
const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _shortDate(DateTime at) => '${at.day} ${_months[at.month - 1]}';

/// What the settings index prints on the right of the Back up my data row.
///
/// One word where the old screen had a sentence. The three-state distinction
/// survives it: "Not set up" is not "Off", because the runner has not decided
/// and saying Off would claim they had.
String backupRowValue(BackupConsent consent) => switch (consent) {
  BackupConsent.unknown => 'Not set up',
  BackupConsent.granted => 'On',
  BackupConsent.declined => 'Off',
};
