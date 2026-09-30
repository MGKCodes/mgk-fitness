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

  group('searching', () {
    final lookup = ExerciseLookup();
    List<String> names(
      String query, {
      String? muscleGroup,
      String? equipment,
    }) => <String>[
      for (final e in lookup.search(
        query,
        muscleGroup: muscleGroup,
        equipment: equipment,
      ))
        e.name,
    ];

    test('matches words, not the whole query, in any order', () {
      expect(
        names('curl bicep'),
        contains('Alternating Bicep Curl With Dumbbell'),
      );
      expect(
        names('bicep curl'),
        contains('Alternating Bicep Curl With Dumbbell'),
      );
      // Half-typed, the way it is on the way to the rest.
      expect(
        names('bicep cu'),
        contains('Alternating Bicep Curl With Dumbbell'),
      );
    });

    test('every word has to match', () {
      final local = ExerciseLookup(<Exercise>[
        entry('Bench Press'),
        entry('Back Squat'),
      ]);
      expect(local.search('bench squat'), isEmpty);
      expect(local.search('bench'), hasLength(1));
    });

    test('a muscle group or equipment word counts', () {
      expect(names('chest barbell'), contains('Barbell Bench Press'));
    });

    test('names holding the words themselves come first', () {
      // "Chest" is a muscle group for dozens; a name with it in leads.
      final results = names('chest');
      final inName = results.indexWhere(
        (n) => n.toLowerCase().contains('chest'),
      );
      final notInName = results.indexWhere(
        (n) => !n.toLowerCase().contains('chest'),
      );
      expect(inName, isNonNegative);
      expect(inName, lessThan(notInName));
    });

    test('a name that starts with what was typed leads', () {
      expect(names('bench').first, startsWith('Bench'));
    });

    group('other names', () {
      final cases = <String, String>{
        'db bench': 'Dumbbell Bench Press',
        'bb squat': 'Barbell Back Squat',
        'single arm bench': 'One Arm Bench Press',
        'one arm tricep extension':
            'Single Arm Triceps Extension With Dumbbell',
        'lat pulldown': 'Close Grip Lat Pull Down',
        'tricep push down': 'Cable Tricep Pushdown',
        'pullup': 'Pull-up',
        'pull up': 'Pull-up',
        'chinup': 'Chin-up',
        'push up': 'Close Triceps Pushup',
        'pushup': 'Bosu Ball Push Up',
        'situp': 'Sit-up',
        'rdl': 'Barbell Romanian Deadlift',
        'triceps pushdown': 'Cable Tricep Pushdown',
        'tricep pushdown': 'Reverse Grip Triceps Pushdown',
      };
      cases.forEach((query, expected) {
        test('"$query" finds $expected', () {
          expect(names(query), contains(expected));
        });
      });

      test('are whole words: "db" inside a word is not dumbbell', () {
        // No catalogue word has "db" in it, so an invented one checks it.
        final local = ExerciseLookup(<Exercise>[entry('Oddball Raise')]);
        expect(local.search('dumbbell'), isEmpty);
      });
    });

    group('one typo', () {
      test('in a word over four letters, as the last choice', () {
        expect(names('squatt'), isNotEmpty);
        expect(names('dumbel'), isNotEmpty);
        // Two letters swapped is one slip.
        expect(names('deadlfit'), contains('Barbell Deadlift'));
        expect(names('bnech'), contains('Barbell Bench Press'));
      });

      test('never in a short word, where one letter is half the word', () {
        // "rox" is one edit from "row", and short words are where a guess is
        // most likely to be a different movement.
        expect(names('rox'), isEmpty);
      });

      test('ranks below a clean match', () {
        // "press" matches outright; "preas" only through a typo.
        final local = ExerciseLookup(<Exercise>[
          entry('Preacher Curl'),
          entry('Press Down'),
        ]);
        expect(
          <String>[for (final e in local.search('press')) e.name],
          <String>['Press Down'],
        );
        expect(
          <String>[for (final e in local.search('preas')) e.name].first,
          'Preacher Curl',
        );
      });

      test('never two', () {
        expect(names('dumbbelll curll squatt'), isEmpty);
        // Two slips in one word: a letter changed and one added.
        expect(names('sqwaat'), isEmpty);
      });
    });

    group('filters', () {
      test('narrow by muscle group, with or without a query', () {
        final triceps = names('', muscleGroup: 'Triceps');
        expect(triceps, isNotEmpty);
        expect(
          lookup
              .search('', muscleGroup: 'Triceps')
              .every((e) => e.muscleGroup == 'Triceps'),
          isTrue,
        );
        expect(
          names('extension', muscleGroup: 'Triceps'),
          everyElement(isIn(triceps)),
        );
      });

      test('narrow by equipment, the rare kinds under Other', () {
        final other = lookup.search(
          '',
          equipment: ExerciseLookup.otherEquipment,
        );
        expect(other, isNotEmpty);
        for (final e in other) {
          expect(ExerciseLookup.equipment, isNot(contains(e.equipment)));
        }
        expect(
          lookup
              .search('', equipment: 'Cable')
              .every((e) => e.equipment == 'Cable'),
          isTrue,
        );
      });

      test('combine', () {
        final both = lookup.search(
          '',
          muscleGroup: 'Chest',
          equipment: 'Dumbbell',
        );
        expect(both, isNotEmpty);
        expect(
          both.every(
            (e) => e.muscleGroup == 'Chest' && e.equipment == 'Dumbbell',
          ),
          isTrue,
        );
      });

      test('cover every muscle group and every movement', () {
        // A group added to the catalogue with no chip would be unreachable
        // by filtering, and nothing else would notice.
        for (final e in lookup.all) {
          expect(ExerciseLookup.muscleGroups, contains(e.muscleGroup));
        }
        var total = 0;
        for (final kind in ExerciseLookup.equipment) {
          total += lookup.search('', equipment: kind).length;
        }
        expect(total, lookup.all.length);
      });
    });

    test('an empty query lists everything, alphabetically', () {
      final all = names('');
      expect(all.length, lookup.all.length);
      expect(all, <String>[...all]..sort());
    });
  });
}
