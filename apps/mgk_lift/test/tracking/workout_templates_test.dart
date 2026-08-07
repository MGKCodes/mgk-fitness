import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/tracking/data/exercise_lookup.dart';
import 'package:mgk_lift/src/features/tracking/data/workout_templates.dart';

void main() {
  final lookup = ExerciseLookup();

  test('the ported catalogue and templates are all present', () {
    expect(workoutTemplates, hasLength(15));
    expect(workoutSplits, hasLength(8));
  });

  group('what the picker offers', () {
    test('a short list, and the rest stay as the coach\'s raw material', () {
      // Fifteen is a lot to choose between with no coach and no plan. These six
      // answer "what should I do today"; the other nine are body-part sessions
      // for somebody who already knows, and they remain in `workoutTemplates`
      // for the coach to compose from rather than being deleted.
      expect(offeredTemplates.map((t) => t.id), <String>[
        'push',
        'pull',
        'legs',
        'upper',
        'lower',
        'full-body',
      ]);
      expect(workoutTemplates.length, greaterThan(offeredTemplates.length));
    });

    test('an offered split never opens a session the picker hides', () {
      // The reason offeredSplits is derived rather than listed. A hand-kept
      // second list drifts, and the drift shows up as a split whose Tuesday
      // opens nothing — which reads as a bug in the picker, not a stale
      // constant three files away.
      final offered = <String>{for (final t in offeredTemplates) t.id};
      for (final split in offeredSplits) {
        for (final id in split.templateIds) {
          expect(
            offered,
            contains(id),
            reason: '${split.id} offers $id, which the picker does not show',
          );
        }
      }
    });

    test('the splits that survive are the ones worth offering', () {
      // Asserted by name rather than only by the rule above, so quietly
      // dropping the last multi-day split fails here instead of silently
      // leaving the picker with one entry.
      expect(offeredSplits.map((s) => s.id), <String>[
        'ppl',
        'upper-lower',
        'full-body',
        'upper-lower-ppl',
      ]);
    });
  });

  test('every template exercise resolves to a catalogue movement', () {
    // The load-bearing cross-reference. A name that does not resolve produces a
    // templated session with no form image and no muscle group — which looks
    // like a bug in the card, not like a typo three files away.
    final unresolved = <String>[];
    for (final template in workoutTemplates) {
      for (final name in template.exercises) {
        if (lookup.find(name) == null) {
          unresolved.add('${template.id}: $name');
        }
      }
    }
    expect(unresolved, isEmpty);
  });

  test('every split resolves to real templates', () {
    final ids = <String>{for (final t in workoutTemplates) t.id};
    final dangling = <String>[];
    for (final split in workoutSplits) {
      for (final id in split.templateIds) {
        if (!ids.contains(id)) dangling.add('${split.id}: $id');
      }
    }
    expect(dangling, isEmpty);
  });

  test('template ids are unique, since splits address them by id', () {
    final ids = workoutTemplates.map((t) => t.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('no template is empty', () {
    for (final t in workoutTemplates) {
      expect(t.exercises, isNotEmpty, reason: '${t.id} has no movements');
      expect(t.description, isNotEmpty, reason: '${t.id} has no description');
    }
  });

  test('a split names as many days as it has sessions, or repeats them', () {
    // PPL over 6 days is three templates run twice — legitimate. What would be
    // wrong is a split claiming fewer days than it has distinct sessions,
    // because then one could never be reached.
    for (final split in workoutSplits) {
      expect(
        split.daysPerWeek,
        greaterThanOrEqualTo(split.templateIds.length),
        reason:
            '${split.id} has ${split.templateIds.length} sessions but '
            'only ${split.daysPerWeek} days',
      );
    }
  });

  test('shared templates are defined once and reused', () {
    // `legs` appears in several splits by design: changing what a leg day is
    // should change it everywhere. This is the indirection paying for itself.
    final usage = <String, int>{};
    for (final split in workoutSplits) {
      for (final id in split.templateIds) {
        usage[id] = (usage[id] ?? 0) + 1;
      }
    }
    expect(usage['legs'], greaterThan(1));
  });

  test('no text carries mojibake from the port', () {
    // The TypeScript source was UTF-8; reading it as Latin-1 during generation
    // turned every middle dot into "Â·". Visible on device, invisible in a
    // diff unless you are looking for it.
    for (final s in workoutSplits) {
      expect(s.description, isNot(contains('Â')), reason: s.id);
      expect(s.name, isNot(contains('Â')), reason: s.id);
    }
    for (final t in workoutTemplates) {
      expect(t.description, isNot(contains('Â')), reason: t.id);
      for (final e in t.exercises) {
        expect(e, isNot(contains('Â')), reason: '${t.id}: $e');
      }
    }
  });

  test('every split image is under the declared asset directory', () {
    for (final split in workoutSplits) {
      expect(split.image, startsWith('assets/images/splits/'));
      expect(split.image, endsWith('.webp'));
    }
  });
}
