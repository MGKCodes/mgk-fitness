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
    int turnCap = 7,
    IntakeSlots initialSlots = const IntakeSlots(),
  }) : _coach = coach,
       _now = now,
       _turnCap = turnCap,
       _slots = initialSlots;

  final CoachClient _coach;
  final DateTime Function() _now;

  /// A hard cap so a bad extraction loop can't trap the user (onboarding.md).
  /// Counts the runner's own messages.
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
