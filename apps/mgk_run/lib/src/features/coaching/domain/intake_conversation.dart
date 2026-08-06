import 'intake_slots.dart';

/// One turn of the onboarding conversation, as plain text. The model's
/// structured extraction is kept separate (see [IntakeTurn]) — the transcript
/// the user sees and the slot state Dart owns are different things.
class IntakeMessage {
  const IntakeMessage({required this.role, required this.text});

  /// `'user'` or `'assistant'`.
  final String role;
  final String text;

  bool get isUser => role == 'user';
}

/// One coach reply: the user-facing [reply] plus the slots [extracted] this
/// turn. The caller merges [extracted] into its running [IntakeSlots] and
/// decides completeness — the model never holds the slot state (onboarding.md).
class IntakeTurn {
  const IntakeTurn({required this.reply, required this.extracted});

  final String reply;
  final IntakeSlots extracted;
}
