import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/coach_report.dart';

/// Reports one of the coach's replies, from inside the conversation it was
/// said in.
///
/// Reached by a long press on the reply, which is where a runner already is
/// when they read something wrong; a report that meant leaving the app for an
/// email would mostly not be made. A reason is required and nothing is chosen
/// for them; the note is optional.
///
/// **A report that did not send says so and keeps what they wrote**, so a
/// runner on a train can try again rather than start again.
class CoachReportSheet extends StatefulWidget {
  const CoachReportSheet({
    super.key,
    required this.reply,
    required this.reporter,
  });

  /// The reply being reported, exactly as it was shown.
  final String reply;
  final CoachReporter reporter;

  @override
  State<CoachReportSheet> createState() => _CoachReportSheetState();
}

class _CoachReportSheetState extends State<CoachReportSheet> {
  final TextEditingController _note = TextEditingController();
  CoachReportReason? _reason;
  bool _sending = false;
  bool _failed = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null || _sending) return;
    setState(() {
      _sending = true;
      _failed = false;
    });
    try {
      await widget.reporter.report(
        CoachReport(reply: widget.reply, reason: reason, note: _note.text),
      );
    } catch (_) {
      // Everything they chose and typed stays where it is.
      if (mounted) {
        setState(() {
          _sending = false;
          _failed = true;
        });
      }
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      // The keyboard pushes the sheet up rather than covering the note.
      padding: EdgeInsets.only(bottom: insets),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.md),
                  child: SheetHandle(),
                ),
                Text(
                  'Report this reply',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Say what was wrong with it. We keep the reply, your reason '
                  'and any note with your account so we can review it.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: <Widget>[
                    for (final reason in CoachReportReason.values)
                      ChoiceChip(
                        label: Text(reason.label),
                        showCheckmark: false,
                        selected: _reason == reason,
                        onSelected: _sending
                            ? null
                            : (_) => setState(() => _reason = reason),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _note,
                  enabled: !_sending,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: CoachReport.maxNote,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Anything else we should know (optional)',
                  ),
                ),
                if (_failed) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    "That didn't send. Check your connection and try again; "
                    'what you wrote is still here.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.danger,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: 'Send report',
                  busy: _sending,
                  onPressed: _reason == null ? null : _send,
                ),
                const SizedBox(height: AppSpacing.xs),
                Center(
                  child: AppTextButton(
                    label: 'Cancel',
                    onPressed: _sending
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens [CoachReportSheet] for [reply]. True once the report has arrived.
///
/// **The confirmation is the caller's, and it goes under the reply.** A
/// snackbar was the obvious quiet confirmation and it does not work here: it
/// belongs to the page's scaffold, and the conversation is a sheet over that
/// page, so it would appear behind the very thing it confirms. A line under
/// the reply says the same thing, where the runner is looking, about the
/// reply they reported.
Future<bool> reportCoachReply(
  BuildContext context, {
  required String reply,
  required CoachReporter reporter,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CoachReportSheet(reply: reply, reporter: reporter),
    ) ??
    false;
