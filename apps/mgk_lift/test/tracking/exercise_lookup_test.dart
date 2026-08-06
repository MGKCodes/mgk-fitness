import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/tracking/data/exercise_lookup.dart';
import 'package:mgk_lift/src/features/tracking/domain/exercise.dart';

Exercise entry(String name) => Exercise(
  name: name,
  category: 'Cable',
  muscleGroup: 'Triceps',
  equipment: 'Cable',
  imageKey: name.toLowerCase().replaceAll(' ', '-'),
);

void main() {
  group('finding a movement in the catalogue', () {
    test('case and punctuation do not matter', () {
      final lookup = ExerciseLookup(<Exercise>[entry('Barbell Bench Press')]);
      expect(lookup.find('barbell bench press')?.name, 'Barbell Bench Press');
      expect(lookup.find('Barbell-Bench-Press')?.name, 'Barbell Bench Press');
    });

    test('nor does word order', () {
      // Found on device. The catalogue calls it "Cable Overhead Tricep
      // Extension"; a lifter typing the equally natural other order got no
      // image and no muscle group, as though they had invented the exercise.
      final lookup = ExerciseLookup(<Exercise>[
        entry('Cable Overhead Tricep Extension'),
      ]);
      expect(
        lookup.find('Overhead Cable Tricep Extension')?.name,
        'Cable Overhead Tricep Extension',
      );
    });

    test('nor a plural', () {
      final lookup = ExerciseLookup(<Exercise>[
        entry('Seated Rear Lateral Cable Raise'),
      ]);
      expect(
        lookup.find('Seated Rear Lateral Cable Raises')?.name,
        'Seated Rear Lateral Cable Raise',
      );
    });

    test('"press" does not become "pres"', () {
      // The trap in stripping a trailing s naively.
      final lookup = ExerciseLookup(<Exercise>[entry('Bench Press')]);
      expect(lookup.find('bench press')?.name, 'Bench Press');
      expect(lookup.find('Bench Presses'), isNull);
    });

    test('an exact name wins over a reordered one', () {
      // Both exist, so neither may be pulled to the other.
      final lookup = ExerciseLookup(<Exercise>[
        entry('Cable Overhead Tricep Extension'),
        entry('Overhead Cable Tricep Extension'),
      ]);
      expect(
        lookup.find('Cable Overhead Tricep Extension')?.name,
        'Cable Overhead Tricep Extension',
      );
      expect(
        lookup.find('Overhead Cable Tricep Extension')?.name,
        'Overhead Cable Tricep Extension',
      );
    });

    test('an ambiguous word set matches nothing rather than guessing', () {
      // Two movements sharing a word multiset. Resolving to whichever was
      // indexed last would put a confidently wrong picture on the card a
      // lifter is looking at mid-set, which is worse than a blank one.
      final lookup = ExerciseLookup(<Exercise>[
        entry('Cable Overhead Tricep Extension'),
        entry('Overhead Cable Tricep Extension'),
      ]);
      expect(lookup.find('Tricep Overhead Extension Cable'), isNull);
    });

    test('a movement they invented is still a miss', () {
      final lookup = ExerciseLookup(<Exercise>[entry('Barbell Bench Press')]);
      expect(lookup.find('Smith machine incline press, feet up'), isNull);
    });
  });

  group('the shipped catalogue', () {
    test('resolves the reordered name that started this', () {
      expect(
        ExerciseLookup().find('Overhead Cable Tricep Extension')?.name,
        'Cable Overhead Tricep Extension',
      );
    });

    test('every entry still finds itself exactly', () {
      // The loose pass must never shadow an exact name.
      final lookup = ExerciseLookup();
      for (final exercise in lookup.all) {
        expect(
          lookup.find(exercise.name)?.name,
          exercise.name,
          reason: '${exercise.name} no longer resolves to itself',
        );
      }
    });
  });
}
