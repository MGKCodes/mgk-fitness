import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/coach_memory.dart';

/// What the coach remembers, shown to the person it is about.
///
/// **The point of this screen is that it is readable.** The memory is a stored
/// paragraph about somebody's training and their body, written by a model,
/// reloaded into every conversation and never seen by anyone else. Keeping it
/// out of sight would make "the coach remembers you" a claim they have to take
/// on trust, and would make a wrong sentence in it undiscoverable.
///
/// It is deliberately **not editable**. The memory is rewritten from the
/// transcript when it falls behind, so an edit would be reverted within a few
/// conversations — a text field here would be a promise the coach does not
/// keep. Erasing is the control that actually holds, so erasing is the control
/// offered.
class CoachMemoryScreen extends StatefulWidget {
  const CoachMemoryScreen({super.key, required this.store});

  final CoachMemoryStore store;

  @override
  State<CoachMemoryScreen> createState() => _CoachMemoryScreenState();
}

class _CoachMemoryScreenState extends State<CoachMemoryScreen> {
  CoachMemory? _memory;
  CoachMemoryFailure? _failure;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final memory = await widget.store.read();
      if (!mounted) return;
      setState(() {
        _memory = memory;
        _busy = false;
      });
    } on CoachMemoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e.failure;
        _busy = false;
      });
    }
  }

  Future<void> _forget() async {
    // Confirmed first, and named plainly. This is not undoable and it is not
    // the same as deleting the account, so the dialog has to say both.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forget everything?'),
        content: const Text(
          'Your coach will lose what it has learned about you, and the '
          'conversations behind it. Your training log is not touched, and your '
          'account stays as it is.\n\n'
          'It starts learning again from your next conversation.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.store.clear();
      if (!mounted) return;
      setState(() {
        _memory = CoachMemory.none;
        _busy = false;
      });
    } on CoachMemoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e.failure;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final memory = _memory;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('What your coach remembers')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            Text(
              // Said once, plainly, on the screen that proves it. The coach
              // screen promising this and nowhere showing it would be the
              // weaker half of the same sentence.
              'Your coach keeps a few notes about you between conversations, so '
              'it does not start from nothing every time. It is written from '
              'what you have told it, and only you can see it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_failure != null)
              _Message(text: _failure!.message, onRetry: _load)
            else if (memory == null || memory.isEmpty)
              _Message(
                text:
                    'Nothing yet. Your coach writes this once you have talked '
                    'for a while, so there is nothing to show after a question '
                    'or two.',
              )
            else ...<Widget>[
              AppCard(
                child: SelectableText(
                  memory.summary,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
              if (memory.updatedAt != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  // "When did it decide that" is the first question anyone asks
                  // about a sentence they disagree with.
                  'Last updated ${_when(memory.updatedAt!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              Text(
                'You cannot edit this. Your coach rewrites it as you talk, so '
                'a change here would not last. If it has something wrong, '
                'telling your coach is what fixes it — or clear it and start '
                'again.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(label: 'Forget everything', onPressed: _forget),
            ],
          ],
        ),
      ),
    );
  }
}

/// A date a person would say out loud, not an ISO string.
String _when(DateTime at) {
  final days = DateTime.now().difference(at).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  return '${at.day.toString().padLeft(2, '0')}/'
      '${at.month.toString().padLeft(2, '0')}/${at.year}';
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textTertiary,
            height: 1.4,
          ),
        ),
        if (onRetry != null) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ],
    );
  }
}
