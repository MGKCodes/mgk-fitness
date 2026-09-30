import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';

/// What somebody chose when they tried to start a workout with another open.
enum OpenSessionChoice { resume, discardAndStart }

/// The rule the saved-workout preview used to carry, moved to the Start
/// buttons it guarded (the design review's finding 7): **one session at a
/// time.** A second Start with one already open asks, rather than silently
/// resuming or silently throwing the first away.
///
/// It names both workouts, because "a session is already open" leaves the
/// lifter to remember which, and the answer depends on it. Null is Cancel:
/// nothing changes.
Future<OpenSessionChoice?> askResumeOrDiscard(
  BuildContext context, {
  required String openName,
  required String wantedName,
}) {
  return showDialog<OpenSessionChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$openName is still open'),
      content: Text(
        'Resume it, or discard it and start $wantedName? Discarding drops '
        "every set you have logged in $openName, and it can't be undone.",
      ),
      actions: <Widget>[
        AppTextButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppTextButton(
          label: 'Discard it',
          onPressed: () =>
              Navigator.of(context).pop(OpenSessionChoice.discardAndStart),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
        ),
        AppFilledButton(
          label: 'Resume $openName',
          onPressed: () => Navigator.of(context).pop(OpenSessionChoice.resume),
        ),
      ],
    ),
  );
}
