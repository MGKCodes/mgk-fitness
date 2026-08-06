import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/data/coach_mappers.dart';
import 'package:mgk_run/src/features/history/domain/run_draft.dart';

/// The seam where a sentence becomes a run.
///
/// What is worth testing is not that a well-formed answer maps cleanly, but
/// that a **partial** one stays partial: the surface is told never to fill a
/// gap it was not given, and this must not fill one either. A guessed distance
/// reads exactly like a reported one once it is in the log.
void main() {
  _intentTests();
  final now = DateTime(2026, 7, 29, 12);

  test('a complete answer becomes a valid draft', () {
    final draft = runDraftFromResponse(<String, dynamic>{
      'distance_meters': 5000,
      'duration_seconds': 1560,
      'when': '2026-07-29T07:10:00Z',
      'kind': 'treadmill',
      'rpe': 6,
      'notes': 'felt easy',
    });

    expect(draft.distanceMeters, 5000);
    expect(draft.duration, const Duration(minutes: 26));
    expect(draft.type, kTypeTreadmill);
    expect(draft.rpe, 6);
    expect(draft.notes, 'felt easy');
    expect(draft.isValid(now), isTrue);
  });

  test('a gap stays a gap, and the validator names it', () {
    // "I ran for about forty minutes" — no distance. Not an error on the wire;
    // a draft with a hole, which RunDraft turns into a question.
    final draft = runDraftFromResponse(<String, dynamic>{
      'distance_meters': null,
      'duration_seconds': 2400,
      'when': '2026-07-29T07:10:00Z',
      'kind': null,
      'rpe': null,
      'notes': null,
    });

    expect(draft.distanceMeters, isNull, reason: 'must not be invented');
    expect(draft.isValid(now), isFalse);
    expect(
      draft.issues(now).map((i) => i.field),
      contains('distance'),
      reason: 'the runner is asked, not guessed at',
    );
  });

  test('an unresolvable time is left null rather than dated to now', () {
    // Defaulting to now would silently date a Tuesday run to today, and nothing
    // downstream could tell the difference.
    final draft = runDraftFromResponse(<String, dynamic>{'when': 'sometime'});
    expect(draft.startedAt, isNull);
    expect(draft.issues(now).map((i) => i.field), contains('started_at'));
  });

  test('a run the app did not watch is manual, not outdoor', () {
    // `kind` is what the runner said, and null means they did not say. Calling
    // it outdoor would be the mapper inventing provenance.
    expect(runDraftFromResponse(<String, dynamic>{}).type, kTypeManual);
    expect(
      runDraftFromResponse(<String, dynamic>{'kind': null}).type,
      kTypeManual,
    );
    expect(
      runDraftFromResponse(<String, dynamic>{'kind': 'outdoor'}).type,
      kTypeOutdoor,
    );
    // Anything off-contract is manual too, rather than trusted through.
    expect(
      runDraftFromResponse(<String, dynamic>{'kind': 'cycling'}).type,
      kTypeManual,
    );
  });

  test('blank notes are absent, not empty', () {
    expect(
      runDraftFromResponse(<String, dynamic>{'notes': '   '}).notes,
      isNull,
    );
    expect(runDraftFromResponse(<String, dynamic>{'notes': 7}).notes, isNull);
  });

  test('numbers arriving as doubles or strings do not become garbage', () {
    // Providers differ on whether an integer field comes back as 1560 or
    // 1560.0. A string is off-contract and must not be half-parsed.
    final d = runDraftFromResponse(<String, dynamic>{
      'duration_seconds': 1560.0,
      'distance_meters': 5000,
      'rpe': 6.0,
    });
    expect(d.duration, const Duration(seconds: 1560));
    expect(d.rpe, 6);

    final bad = runDraftFromResponse(<String, dynamic>{
      'duration_seconds': '1560',
      'distance_meters': '5k',
    });
    expect(bad.duration, isNull);
    expect(bad.distanceMeters, isNull);
  });

  test('an implausible extraction is refused, not stored', () {
    // 5 km in 2 minutes: what a misheard "26" looks like. Nobody typed it, so
    // nobody would catch it downstream.
    final draft = runDraftFromResponse(<String, dynamic>{
      'distance_meters': 5000,
      'duration_seconds': 120,
      'when': '2026-07-29T07:10:00Z',
    });
    expect(draft.isValid(now), isFalse);
  });
}

/// The intent mapper, which had the same hard-coded filter the server did.
void _intentTests() {
  test('every routable kind survives the mapper', () {
    // Regression, and the second time this exact bug appeared. Fixing it on the
    // server and leaving the Dart copy is how it survived being fixed once.
    for (final kind in CoachIntent.kinds) {
      final turn = chatTurnFromResponse(<String, dynamic>{
        'reply': 'ok',
        'intent': <String, dynamic>{'kind': kind, 'request': 'something'},
      });
      expect(turn.intent?.kind, kind, reason: '$kind must be routable');
    }
  });

  test('an unknown kind still degrades to no intent', () {
    // Deliberately a kind nothing serves. This used to say `set_goal`, which
    // stopped being unknown the day the coach learned to change a target — a
    // test asserting a name rather than a property ages into asserting the
    // opposite of what it meant.
    final turn = chatTurnFromResponse(<String, dynamic>{
      'reply': 'ok',
      'intent': <String, dynamic>{
        'kind': 'delete_everything',
        'request': 'all of it',
      },
    });
    expect(turn.intent, isNull);
  });

  test('every kind the app names is routable, and no others', () {
    // The property the test above was reaching for. `CoachIntent.kinds` is the
    // list the server's enum is kept in step with, and anything outside it has
    // nowhere to go.
    for (final kind in CoachIntent.kinds) {
      final turn = chatTurnFromResponse(<String, dynamic>{
        'reply': 'ok',
        'intent': <String, dynamic>{'kind': kind, 'request': 'something'},
      });
      expect(turn.intent?.kind, kind, reason: '$kind must be routable');
    }
    expect(CoachIntent.kinds, contains(CoachIntent.setGoal));
  });

  test('a kind with nothing to act on is dropped', () {
    for (final bad in <Map<String, dynamic>>[
      <String, dynamic>{'kind': 'log_run'},
      <String, dynamic>{'kind': 'log_run', 'request': '   '},
      <String, dynamic>{'kind': 'log_run', 'request': 7},
    ]) {
      expect(
        chatTurnFromResponse(<String, dynamic>{
          'reply': 'ok',
          'intent': bad,
        }).intent,
        isNull,
      );
    }
  });
}
