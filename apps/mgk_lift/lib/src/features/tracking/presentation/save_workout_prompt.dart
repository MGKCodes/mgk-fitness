import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/session.dart';
import '../domain/workout_library.dart';

/// Names a session's shape and keeps it — **one implementation, reached from
/// two moments.**
///
/// It is offered twice: from the foot of the running session, and again on the
/// summary once the session has ended. Those are genuinely different moments —
/// one is "I can already tell this is worth keeping", the other is "that
/// worked" — but they are the same action, and the first version of this had
/// the dialog written out at only one of them, which is why moving it meant
/// moving the session screen's private copy here rather than growing a second.
///
/// Returns the name it saved under, or null if the lifter backed out. Callers
/// use that to stop asking: a session that has been saved once must not be
/// offered again on the way out.
Future<String?> promptToSaveWorkout(
  BuildContext context, {
  required WorkoutLibrary library,
  required TextEditingController field,
  required String suggestedName,
  required List<String> movements,
}) async {
  // Nothing to keep. A session with no movements has no shape, and an empty
  // workout in the library is a row that can never be started from.
  if (movements.isEmpty) return null;

  final name = await _askForName(context, field, suggestedName);
  if (name == null || !context.mounted) return null;

  await library.save(name: name, movements: movements);
  if (!context.mounted) return name;

  // Dropped rather than awaited. [AppHaptics] says so itself — "every call
  // returns a future that callers are free to drop, and none of them should
  // ever be awaited on a frame boundary" — and the version this was lifted
  // from awaited it, which put a platform round trip between the write and
  // everything the caller does about it.
  unawaited(AppHaptics.commit());

  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('$name is in your workouts.')));
  return name;
}

/// The movements to save, in order and without repeats.
///
/// A session where the lifter came back to the bench at the end is one workout
/// with bench in it, not one with bench in it twice.
List<String> workoutMovementsOf(Session session) {
  final movements = <String>[];
  for (final e in session.exercises) {
    if (!movements.contains(e.name)) movements.add(e.name);
  }
  return movements;
}

/// The one field a save needs, in a dialog rather than a screen.
///
/// Pre-filled with the session's name and selected, so the common answer is one
/// tap and the less common one is typing over the top rather than clearing a
/// field first.
///
/// **The controller belongs to the calling screen, not to the dialog.**
/// Creating one here and disposing it after the `await` looks right and is not:
/// the await returns the moment `pop` is called, while the dialog is still
/// animating out, and the field rebuilds at least once against a controller
/// that has already been disposed. Owning it for the life of the screen also
/// means the second save of a session opens on the field the first one left.
Future<String?> _askForName(
  BuildContext context,
  TextEditingController field,
  String initial,
) {
  field
    ..text = initial
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      // Not the same words as the button that opened it. Two widgets reading
      // "Save to your workouts" on screen at once is one thing said twice, and
      // the louder of them is no longer the one you can act on.
      title: const Text('Name this workout'),
      content: TextField(
        controller: field,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (value) => Navigator.of(
          dialogContext,
        ).pop(value.trim().isEmpty ? null : value.trim()),
      ),
      actions: <Widget>[
        AppTextButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        FilledButton(
          onPressed: () {
            final typed = field.text.trim();
            Navigator.of(dialogContext).pop(typed.isEmpty ? null : typed);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
