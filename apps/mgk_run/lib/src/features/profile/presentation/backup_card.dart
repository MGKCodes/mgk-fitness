import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/backup_state.dart';

/// One line on Profile saying where the runner's training actually is.
///
/// **The field test asked for "a visible sync state — whether data has reached
/// the back end".** Profile had none: its own class doc said everything on it
/// was derived from data already on the device, with *"nothing to keep in
/// sync"*, which stopped being the whole truth the moment backup existed.
///
/// Settings has carried the same record for months and still does — this does
/// not replace it. Settings is where backup is *configured*; Profile is where
/// the log lives, and "is this safe?" is a question you ask while looking at
/// the thing you would lose.
class BackupCard extends StatelessWidget {
  const BackupCard({super.key, required this.state});

  final ProfileBackupState state;

  @override
  Widget build(BuildContext context) {
    final bool syncing = state.syncing;
    return Row(
      children: <Widget>[
        SizedBox.square(
          dimension: 14,
          child: syncing
              ? const CircularProgressIndicator(strokeWidth: 2)
              : Icon(
                  state.health.isFailing
                      ? Icons.cloud_off_outlined
                      : Icons.cloud_done_outlined,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            _sentence(state),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  /// **Four sentences, and none of them claims more than is known.**
  ///
  /// In particular none says "everything is backed up": [BackupHealth]'s own
  /// doc is explicit that it reports the *last attempt* and cannot say whether
  /// everything on the phone is mirrored. A line that said so would be the
  /// screen inventing a guarantee out of a timestamp.
  static String _sentence(ProfileBackupState s) {
    if (s.syncing) return 'Backing up…';
    if (s.health.isFailing) {
      return 'Could not reach the server. Your training is safe on this phone.';
    }
    if (s.justSent > 0) {
      final runs = s.justSent == 1 ? 'run' : 'runs';
      return 'Backed up. ${s.justSent} $runs sent just now.';
    }
    final DateTime? at = s.health.lastSucceededAt;
    if (at == null) return 'Nothing has been backed up yet.';
    return 'Last backed up ${_ago(at)}.';
  }

  /// Lifted verbatim from Lift's sync bar, which had already settled it.
  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
