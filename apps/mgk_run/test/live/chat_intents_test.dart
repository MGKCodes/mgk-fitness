@Tags(<String>['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/data/coach_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'live_backend.dart';

/// **Does what the runner says reach something that can act on it?**
///
/// An intent crosses four layers: the model chooses a kind, the function's
/// `chatIntent` filter accepts it, Dart's `_intentFrom` accepts it again, and
/// the controller routes it. Three of those four have been silently wrong at
/// some point, and every unit test passed each time — because each layer's
/// tests asserted the kinds that layer already knew about.
///
/// `log_run` was the expensive one. It shipped; the server-side filter was
/// hard-coded to `adapt_week` and dropped it; it looked exactly like a model
/// refusing to follow its prompt. Fixing that layer left the identical bug one
/// layer up in Dart, which is how the same bug survived being fixed once.
///
/// These are the end-to-end question none of those layers can ask about itself:
/// say a sentence to the real coach, and check something actionable comes back.
///
/// ```
/// flutter test --tags live --dart-define-from-file=config/app_config.json
/// ```
void main() {
  if (!liveConfigured) {
    test('live chat intents', () {}, skip: liveSkipReason);
    return;
  }

  late SupabaseClient client;
  late CoachService coach;

  setUpAll(() async {
    client = await signedInClient();
    coach = CoachService(client: client);
  });

  tearDownAll(() async => client.dispose());

  const String brief =
      'They are in week 4 of 12 of a 21 km block, 55 days out from the event. '
      'This is a build week of about 48 km. They can run on Monday, Tuesday, '
      'Thursday, Saturday and Sunday.';

  Future<ChatTurn> say(String message) => coach.chat(
    brief: brief,
    history: const <ChatMessage>[],
    message: message,
  );

  test('mentioning a run raises log_run, and it survives every filter', () {
    return live(() async {
      final turn = await say('I did 5k in 26 minutes this morning');

      expect(
        turn.intent,
        isNotNull,
        reason:
            'a run mentioned in passing produced no intent at all — either '
            'the model did not raise one, or a filter dropped it',
      );
      expect(turn.intent!.isLogRun, isTrue, reason: 'got ${turn.intent!.kind}');

      // And the extraction the intent points at actually reads it.
      final draft = await coach.logRun(turn.intent!.request);
      expect(draft, isNotNull);
      expect(draft!.distanceMeters, closeTo(5000, 200));
    });
  });

  test('correcting a run raises edit_run, not a second log_run', () {
    // The distinction that matters: logging a correction as a new run leaves
    // the runner with two runs where they did one, and neither of them right.
    return live(() async {
      final turn = await say("yesterday's run was actually 6k, not 5");

      expect(turn.intent, isNotNull);
      expect(
        turn.intent!.isEditRun,
        isTrue,
        reason: 'got ${turn.intent!.kind}',
      );
    });
  });

  test('naming a race raises set_goal', () {
    return live(() async {
      final turn = await say("I've entered a half marathon on 4 October");

      expect(turn.intent, isNotNull);
      expect(
        turn.intent!.isSetGoal,
        isTrue,
        reason: 'got ${turn.intent!.kind}',
      );

      final change = await coach.setGoal(turn.intent!.request);
      expect(change, isNotNull);
      expect(change!.goalDistanceMeters, closeTo(21097, 200));
    });
  });

  test('asking to move a session raises adapt_week', () {
    return live(() async {
      final turn = await say('can we move Thursday to Saturday this week');

      expect(turn.intent, isNotNull);
      expect(
        turn.intent!.isAdaptWeek,
        isTrue,
        reason: 'got ${turn.intent!.kind}',
      );
    });
  });

  test('an ordinary question raises nothing', () {
    // The other half. A coach that raised an intent on every turn would put a
    // confirmation card in front of someone who only asked a question, and the
    // cards are only meaningful because they are rare.
    return live(() async {
      final turn = await say('how has my training been going?');

      expect(turn.reply, isNotEmpty);
      expect(
        turn.intent,
        isNull,
        reason:
            'a question produced an actionable intent: ${turn.intent?.kind}',
      );
    });
  });

  test('the coach never claims a change it has not made', () {
    // Every acting intent is a proposal the runner confirms. A reply saying "I
    // have updated that" above a card still asking permission makes the
    // confirmation meaningless — and both log_run and set_goal shipped doing
    // exactly that before the prompt was fixed. Twice, months apart, because
    // the rule was written for one intent and not carried to the next.
    return live(() async {
      final turn = await say("I've entered a marathon on 15 November");
      final reply = turn.reply.toLowerCase();

      for (final claim in <String>[
        'i have updated',
        'i have set',
        'i have changed',
        'i have logged',
      ]) {
        expect(
          reply,
          isNot(contains(claim)),
          reason: 'claimed a write before the runner confirmed: ${turn.reply}',
        );
      }
    });
  });
}
