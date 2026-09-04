import 'package:flutter/foundation.dart';

import '../data/coach_client.dart';
import '../data/coach_service.dart';
import '../domain/intake_conversation.dart';
import '../domain/intake_slots.dart';

/// Drives the slot-filling onboarding conversation. **Dart owns the slot
/// state** (onboarding.md): each turn the coach returns extracted slots, which
/// are merged in here; Dart decides what is still missing, when the intake is
/// complete, and when the turn cap has been hit. The model never holds state.
class OnboardingController extends ChangeNotifier {
  OnboardingController({
    required CoachClient coach,
    DateTime Function() now = DateTime.now,
    int turnCap = 12,
    IntakeSlots initialSlots = const IntakeSlots(),
  }) : _coach = coach,
       _now = now,
       _turnCap = turnCap,
       _slots = initialSlots;

  final CoachClient _coach;
  final DateTime Function() _now;

  /// A hard cap so a bad extraction loop can't trap the user (onboarding.md).
  /// Counts the runner's own messages.
  ///
  /// **Sized for one question per turn.** It was 7, which fitted an intake
  /// prompt that told the model to batch two or three questions into every
  /// message. A build 12 field test met the result — four questions in one
  /// bubble — so `INTAKE_INSTRUCTIONS` now asks exactly one thing per turn,
  /// and a cap sized for batching became a cap that ends the conversation
  /// mid-question.
  ///
  /// The arithmetic, from [IntakeSlots.requiredSlots]: a block is the deepest
  /// shape at six required slots (goal, event date, weekly volume, longest
  /// run, days per week, time trial), and a runner whose shape is not yet
  /// known spends one more turn settling it. Which weekdays they can run is
  /// not a seventh: it is asked in the same breath as how many, and the prompt
  /// says so. So seven turns is the *perfect* case — every question answered
  /// cleanly, first time, nothing misheard.
  ///
  /// 12 puts five spare turns on top of that. A cap is a loop-breaker, not a
  /// budget: hitting it drops the runner on the confirmation screen with holes
  /// in their profile, and a hole where the training days should be leaves
  /// that screen's build button doing nothing at all. It should be reached by
  /// a model that has stopped listening, never by a runner who asked what a
  /// time trial was.
  final int _turnCap;

  final List<IntakeMessage> _messages = <IntakeMessage>[];

  /// Seeded from the pre-account conversation where there was one: the shape
  /// was settled before sign-up, so the coach opens on what it still needs
  /// rather than asking what they are training for a second time (ADR-0018).
  IntakeSlots _slots;
  bool _busy = false;
  String? _error;

  /// The transcript so far, oldest first.
  List<IntakeMessage> get messages => List.unmodifiable(_messages);

  /// The slots gathered so far.
  IntakeSlots get slots => _slots;

  /// A coach turn is in flight.
  bool get isBusy => _busy;

  /// A user-presentable error from the last turn, if any.
  String? get error => _error;

  int get _userTurns => _messages.where((m) => m.isUser).length;

  /// Every required slot is filled and passes sanity checks.
  bool get isComplete => _slots.isComplete(_now());

  /// The runner has hit the turn cap without completing — move on to the
  /// editable confirmation screen with whatever was gathered.
  bool get turnCapReached => _userTurns >= _turnCap;

  /// The conversation should end: either it is done or it is capped.
  bool get isFinished => isComplete || turnCapReached;

  /// Whether the input should accept another message.
  bool get canSend => !_busy && !isFinished;

  /// Opens the conversation — the coach greets and asks the first questions.
  /// Safe to call once; a no-op if the transcript already has content.
  Future<void> start() async {
    if (_messages.isNotEmpty || _busy) return;
    await _turn();
  }

  /// Sends the runner's [text], then fetches the coach's reply.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !canSend) return;
    _messages.add(IntakeMessage(role: 'user', text: trimmed));
    notifyListeners();
    await _turn();
  }

  Future<void> _turn() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final turn = await _coach.intake(slots: _slots, history: _messages);
      _messages.add(IntakeMessage(role: 'assistant', text: turn.reply));
      // Model proposes, Dart disposes: merge overlays only the non-null slots.
      _slots = _slots.merge(turn.extracted);
    } on CoachException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'The coach hit a problem. Please try again.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
