import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/plan.dart';
import '../domain/plan_adaptation.dart';
import '../domain/plan_generator.dart';

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
  final TextEditingController _input = TextEditingController();

  String? _reply;
  List<AdaptChange> _changes = const <AdaptChange>[];
  final Set<int> _accepted = <int>{};
  PlanFailure? _failure;
  bool _waiting = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

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
        _input.clear();
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
    final media = MediaQuery.of(context);

    return SizedBox(
      height: media.size.height * 0.75,
      child: GlassSurface(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const SectionLabel('Change this week'),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Tell your coach what has changed. Nothing moves until you say so.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            Expanded(
              child: ListView(
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
            ),

            if (_changes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: PrimaryButton(
                  label: _accepted.isEmpty
                      ? 'Change nothing'
                      : 'Make ${_accepted.length} '
                            '${_accepted.length == 1 ? 'change' : 'changes'}',
                  onPressed: () => Navigator.of(context).pop(<AdaptChange>[
                    for (var i = 0; i < _changes.length; i++)
                      if (_accepted.contains(i)) _changes[i],
                  ]),
                ),
              ),

            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !_waiting,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _ask,
                      decoration: const InputDecoration(
                        hintText: 'Shoulder is sore, can we move Thursday?',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    onPressed: _waiting ? null : () => _ask(_input.text),
                    icon: const Icon(Icons.arrow_upward),
                    tooltip: 'Ask',
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
