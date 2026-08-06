import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/tracking/data/exercise_lookup.dart';
import 'package:mgk_lift/src/features/tracking/data/workout_templates.dart';

void main() {
  final lookup = ExerciseLookup();

  test('the ported catalogue and templates are all present', () {
    expect(workoutTemplates, hasLength(15));
    expect(workoutSplits, hasLength(8));
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
        reason: '${split.id} has ${split.templateIds.length} sessions but '
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
