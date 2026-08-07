import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../tracking/domain/session.dart';
import '../domain/plan.dart';
import '../domain/plan_generator.dart';
import '../domain/plan_validator.dart';

/// "I don't like barbell bench press, can we swap it out."
///
/// Opens from a movement in the live session, asks the coach, and shows what it
/// suggests. **Nothing changes until the lifter taps one** — the coach proposes,
/// and a coach that rewrote the session somebody was halfway through would be
/// worse than one that could not help at all.
///
/// The reply is always shown, even with no options behind it. "Honestly, skip
/// it today" is a complete answer, and so is a reply whose suggestions were all
/// discarded by the validator.
class SwapSheet extends StatefulWidget {
  const SwapSheet({
    super.key,
    required this.planner,
    required this.session,
    required this.movement,
    required this.log,
    this.unit = MassUnit.kilograms,
    this.validator = const PlanValidator(),
  });

  final CoachPlanner planner;

  /// The session as it stands. Sent to the coach because it is not a record
  /// yet — the device owns it until it is finished.
  final Session session;

  /// The movement they want rid of.
  final String movement;

  /// Their finished sessions, so a suggested movement's target can be derived
  /// from what they have actually lifted.
  final List<Session> log;

  final MassUnit unit;
  final PlanValidator validator;

  /// Returns the chosen replacement, or null if they backed out.
  static Future<PlannedMovement?> show(
    BuildContext context, {
    required CoachPlanner planner,
    required Session session,
    required String movement,
    required List<Session> log,
    MassUnit unit = MassUnit.kilograms,
  }) => showModalBottomSheet<PlannedMovement>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SwapSheet(
      planner: planner,
      session: session,
      movement: movement,
      log: log,
      unit: unit,
    ),
  );

  @override
  State<SwapSheet> createState() => _SwapSheetState();
}

class _SwapSheetState extends State<SwapSheet> {
  final TextEditingController _input = TextEditingController();

  SwapVerdict? _verdict;
  PlanFailure? _failure;
  bool _waiting = false;

  @override
  void initState() {
    super.initState();
    // Asked straight away with no reason given: most of the time there is not
    // one worth typing, and making somebody explain themselves before they can
    // change an exercise is friction for its own sake. The field stays, for
    // when the reason matters ("shoulder hurts").
    _ask('');
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _ask(String reason) async {
    setState(() {
      _waiting = true;
      _failure = null;
    });
    try {
      final proposal = await widget.planner.swap(
        message: reason.trim().isEmpty
            ? 'I want to swap out ${widget.movement}.'
            : 'I want to swap out ${widget.movement}. ${reason.trim()}',
        session: widget.session,
      );
      if (!mounted) return;
      setState(() {
        _verdict = widget.validator.checkSwap(proposal, log: widget.log);
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
    final media = MediaQuery.of(context);
    final verdict = _verdict;

    return SizedBox(
      height: media.size.height * 0.7,
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
            SectionLabel('Instead of ${widget.movement}'),
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
                  else if (verdict != null) ...<Widget>[
                    // Always shown, whatever happened to the options.
                    Text(
                      verdict.reply,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    for (var i = 0; i < verdict.options.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AppCard(
                          onTap: () =>
                              Navigator.of(context).pop(verdict.options[i]),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                verdict.options[i].name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                verdict.options[i].render(widget.unit),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              if (i < verdict.why.length &&
                                  verdict.why[i].isNotEmpty) ...<Widget>[
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  verdict.why[i],
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
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
                        hintText: 'Why? (optional)',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    onPressed: _waiting ? null : () => _ask(_input.text),
                    icon: const Icon(Icons.arrow_upward),
                    tooltip: 'Ask again',
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
