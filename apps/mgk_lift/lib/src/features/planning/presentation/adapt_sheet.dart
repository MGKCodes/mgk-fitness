import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/plan.dart';
import '../domain/plan_adaptation.dart';
import '../domain/plan_generator.dart';
import 'coach_sheet.dart';

/// "Shoulder is sore, can we move Thursday?"
///
/// **Every change is ticked individually before anything happens.** The coach
/// proposes a set; the lifter takes the ones they want. Applying the lot on one
/// button would make a request to move one day into a rearrangement of the week
/// — which is precisely the failure the diff representation exists to prevent.
///
/// Returns the accepted changes, or null if they backed out.
class AdaptSheet extends StatefulWidget {
  const AdaptSheet({
    super.key,
    required this.planner,
    required this.plan,
    required this.weekNumber,
    this.adapter = const PlanAdapter(),
  });

  final CoachPlanner planner;
  final Plan plan;
  final int weekNumber;
  final PlanAdapter adapter;

  static Future<List<AdaptChange>?> show(
    BuildContext context, {
    required CoachPlanner planner,
    required Plan plan,
    required int weekNumber,
  }) => showModalBottomSheet<List<AdaptChange>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        AdaptSheet(planner: planner, plan: plan, weekNumber: weekNumber),
  );

  @override
  State<AdaptSheet> createState() => _AdaptSheetState();
}

class _AdaptSheetState extends State<AdaptSheet> {
  String? _reply;
  List<AdaptChange> _changes = const <AdaptChange>[];
  final Set<int> _accepted = <int>{};
  PlanFailure? _failure;
  bool _waiting = false;

  Future<void> _ask(String message) async {
    if (message.trim().isEmpty || _waiting) return;
    setState(() {
      _waiting = true;
      _failure = null;
    });
    try {
      final proposal = await widget.planner.adapt(
        message: message.trim(),
        plan: widget.plan,
        weekNumber: widget.weekNumber,
      );
      if (!mounted) return;
      final checked = widget.adapter.check(
        proposal,
        plan: widget.plan,
        weekNumber: widget.weekNumber,
      );
      setState(() {
        _reply = proposal.reply;
        _changes = checked;
        // Everything starts ticked: the coach was asked for a proposal and
        // this is it. Un-ticking is the edit, which is the right way round —
        // making somebody opt into each change turns a suggestion into a form.
        _accepted
          ..clear()
          ..addAll(List<int>.generate(checked.length, (int i) => i));
        _waiting = false;
      });
    } on PlanException catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e.failure;
        _waiting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CoachSheet(
      title: 'Change week ${widget.weekNumber}',
      subtitle: 'Nothing moves until you say so.',
      hint: 'Shoulder is sore, can we move Thursday?',
      busy: _waiting,
      onAsk: _ask,
      // Unlike a swap, tapping a change does not confirm it — several can
      // apply at once, so the confirmation is its own action.
      footer: _changes.isEmpty
          ? null
          : PrimaryButton(
              label: _accepted.isEmpty
                  ? 'Change nothing'
                  : 'Make ${_accepted.length} '
                        '${_accepted.length == 1 ? 'change' : 'changes'}',
              onPressed: () => Navigator.of(context).pop(<AdaptChange>[
                for (var i = 0; i < _changes.length; i++)
                  if (_accepted.contains(i)) _changes[i],
              ]),
            ),
      child: ListView(
        shrinkWrap: true,
        children: <Widget>[
          if (_waiting)
            Text(
              'Asking your coach…',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textTertiary,
              ),
            )
          else if (_failure != null)
            Text(
              _failure!.message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          else if (_reply != null) ...<Widget>[
            Text(
              _reply!,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (var i = 0; i < _changes.length; i++)
              CheckboxListTile(
                value: _accepted.contains(i),
                onChanged: (bool? on) => setState(() {
                  if (on ?? false) {
                    _accepted.add(i);
                  } else {
                    _accepted.remove(i);
                  }
                }),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _changes[i].label,
                  style: theme.textTheme.bodyMedium,
                ),
                subtitle: _changes[i].why.isEmpty
                    ? null
                    : Text(
                        _changes[i].why,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
              ),
          ],
        ],
      ),
    );
  }
}
