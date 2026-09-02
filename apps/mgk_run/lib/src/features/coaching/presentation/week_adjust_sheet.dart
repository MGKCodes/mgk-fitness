import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../data/adaptation_service.dart';
import '../data/coach_errors.dart';
import '../domain/prescribed_distance.dart';
import '../domain/runner_profile.dart';
import '../domain/training_plan.dart';
import '../domain/week_adaptation.dart';
import 'session_labels.dart';

/// Adjust a week from a natural-language request. The runner describes what to
/// change, the coach proposes a revised week (already validated), and the diff
/// is shown for approval. Pops with the revised [TrainingWeek] on apply, or null
/// on discard — the model proposes, the runner disposes.
class WeekAdjustSheet extends StatefulWidget {
  const WeekAdjustSheet({
    super.key,
    required this.adaptation,
    required this.week,
    required this.slot,
    required this.profile,
    this.initialRequest,
    this.unit = UnitSystem.metric,
  });

  final AdaptationService adaptation;
  final TrainingWeek week;
  final SkeletonWeek slot;
  final RunnerProfile profile;

  /// A request the runner has already made — in the chat, where they said "my
  /// calf is sore, can we move today's run" rather than opening this sheet. The
  /// sheet then opens already asking, so the request travels through the same
  /// propose → validate → diff → approve path as one typed in here. The chat
  /// hands the words over; it never changes the plan itself (CLAUDE.md rule 2).
  final String? initialRequest;

  final UnitSystem unit;

  @override
  State<WeekAdjustSheet> createState() => _WeekAdjustSheetState();
}

class _WeekAdjustSheetState extends State<WeekAdjustSheet> {
  final _input = TextEditingController();
  bool _busy = false;

  /// Why the last request failed, ready to show. A hit allowance and a request
  /// the coach couldn't work with need different words — "try rephrasing" is
  /// useless advice when the real problem is that you're out of requests.
  String? _failure;
  AdaptationProposal? _proposal;

  @override
  void initState() {
    super.initState();
    final request = widget.initialRequest?.trim();
    if (request == null || request.isEmpty) return;
    _input.text = request;
    // After the first frame: `_ask` sets state, and the sheet has not been laid
    // out yet. The request is left in the field so the runner can see — and
    // edit — what the coach is about to be asked on their behalf.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_ask());
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final request = _input.text.trim();
    if (request.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _failure = null;
      _proposal = null;
    });

    AdaptationProposal? proposal;
    String? failure;
    try {
      proposal = await widget.adaptation.propose(
        week: widget.week,
        slot: widget.slot,
        profile: widget.profile,
        request: request,
      );
      if (proposal == null) {
        failure = "The coach couldn't adjust that. Try rephrasing.";
      }
    } on AdaptationRefused catch (e) {
      // A week the validator would not stand behind. It knows why, and the
      // reason is usually a fact about the runner's own week rather than the
      // wording of the request, so telling them to rephrase would be wrong.
      failure = e.message;
    } on CoachLimitException catch (e) {
      // The runner's allowance, not a bad request — rephrasing won't help.
      failure = e.message;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _proposal = proposal;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final proposal = _proposal;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      // The handle is this sheet's only way out. Its "Back" resets the
      // proposal and is not a dismiss, and it appears in one state of three.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SheetHandle(),
          Text(
            'Adjust this week',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (proposal == null) ..._askView() else ..._reviewView(proposal),
        ],
      ),
    );
  }

  List<Widget> _askView() => <Widget>[
    TextField(
      controller: _input,
      enabled: !_busy,
      minLines: 1,
      maxLines: 3,
      // Not when the request arrived from the chat: the coach is already
      // working on it, and a keyboard over the answer helps nobody.
      autofocus: widget.initialRequest == null,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => _ask(),
      decoration: const InputDecoration(
        hintText: "What needs to change? e.g. can't run Tuesday",
      ),
    ),
    if (_failure != null)
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          _failure!,
          style: const TextStyle(color: AppColors.danger, fontSize: 13),
        ),
      ),
    const SizedBox(height: 12),
    SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _busy ? null : _ask,
        child: _busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.onPrimary,
                ),
              )
            : const Text('Ask the coach'),
      ),
    ),
  ];

  List<Widget> _reviewView(AdaptationProposal proposal) => <Widget>[
    const Text(
      "Here's what I'd change:",
      style: TextStyle(color: AppColors.textSecondary),
    ),
    const SizedBox(height: 10),
    for (final change in proposal.changes)
      _ChangeRow(change: change, unit: widget.unit),
    const SizedBox(height: 18),
    Row(
      children: <Widget>[
        Expanded(
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(proposal.week),
            child: const Text('Apply'),
          ),
        ),
        const SizedBox(width: 12),
        AppTextButton(
          label: 'Back',
          onPressed: () => setState(() => _proposal = null),
        ),
      ],
    ),
  ];
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change, required this.unit});

  final SessionChange change;
  final UnitSystem unit;

  String _label(PlannedSession? s) => s == null
      ? 'Rest'
      : '${kindLabel(s.kind)} ${formatPrescribed(s.distanceMeters, unit)}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Text(
              weekdayName(change.weekday),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: <TextSpan>[
                  TextSpan(text: _label(change.before)),
                  const TextSpan(
                    text: '  →  ',
                    style: TextStyle(color: AppColors.textTertiary),
                  ),
                  TextSpan(
                    text: _label(change.after),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
                style: const TextStyle(color: AppColors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
