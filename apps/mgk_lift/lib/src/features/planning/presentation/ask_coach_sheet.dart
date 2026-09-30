import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The shell every "ask the coach to change something" sheet shares.
///
/// **Not `CoachSheet` in `coaching/presentation`, which is the coach itself.** Both were called
/// `CoachSheet` and nothing imported both, so the collision never failed a
/// build — it just made every doc reference ambiguous, including two that
/// already pointed the wrong way. This one is the frame around a request; the
/// other is the conversation.
///
/// **Written because the two that existed had already drifted after a day.**
/// Swapping a movement and changing the week are the same interaction — say
/// what you want, read what is proposed, take it or leave it — and they had
/// arrived at two max heights, two label conventions, and one supporting line
/// between them. That is principle 2 in [docs/design.md] applied to
/// composition: if two things occupy the same role, they are one component
/// with two states or they are wrong.
///
/// What it does NOT unify is the body. Picking one replacement and ticking
/// several changes are genuinely different selection models, and forcing them
/// into one widget would be coherence for its own sake.
class AskCoachSheet extends StatelessWidget {
  const AskCoachSheet({
    super.key,
    required this.title,
    required this.hint,
    required this.onAsk,
    required this.child,
    this.subtitle,
    this.footer,
    this.busy = false,
  });

  /// What this sheet is about. **Name its subject where there is one** —
  /// "Instead of Barbell Bench Press" tells you what you are changing; "Change
  /// this week" makes you remember.
  final String title;

  /// One line under the title, for a sheet whose subject is not self-evident.
  final String? subtitle;

  /// The placeholder in the ask field. Written as an example of a real request
  /// rather than an instruction, because it is the only guidance on an empty
  /// sheet.
  final String hint;

  final ValueChanged<String> onAsk;

  /// The proposal, however this sheet shows one.
  final Widget child;

  /// The confirm action, for a sheet that has one. Sheets where tapping an
  /// option IS the confirmation pass null.
  final Widget? footer;

  final bool busy;

  /// How tall a coach sheet may get.
  ///
  /// A ceiling, never a height — see principle 1. Pinned at a fraction, two
  /// suggestions left several hundred pixels of nothing above the input, and
  /// swapping the fixed height for a maxHeight changes nothing on its own
  /// while an `Expanded` inside still fills whatever it is given.
  static const double _maxHeightFraction = 0.75;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * _maxHeightFraction,
      ),
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
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SheetHandle(),
            SectionLabel(title),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),

            Flexible(child: child),

            if (footer != null) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              footer!,
            ],

            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: _AskField(hint: hint, onAsk: onAsk, busy: busy),
            ),
          ],
        ),
      ),
    );
  }
}

class _AskField extends StatefulWidget {
  const _AskField({
    required this.hint,
    required this.onAsk,
    required this.busy,
  });

  final String hint;
  final ValueChanged<String> onAsk;
  final bool busy;

  @override
  State<_AskField> createState() => _AskFieldState();
}

class _AskFieldState extends State<_AskField> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    widget.onAsk(_input.text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: <Widget>[
      Expanded(
        child: TextField(
          controller: _input,
          enabled: !widget.busy,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _send(),
          decoration: InputDecoration(hintText: widget.hint),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      IconButton.filled(
        onPressed: widget.busy ? null : _send,
        icon: const Icon(Icons.arrow_upward),
        tooltip: 'Ask',
      ),
    ],
  );
}
