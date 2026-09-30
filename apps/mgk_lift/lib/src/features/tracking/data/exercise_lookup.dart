import '../domain/exercise.dart';
import 'exercise_catalogue.dart';

/// Finds a catalogue entry for a logged exercise name.
///
/// A logged exercise is free text on purpose — someone typing "smith machine
/// incline press, feet up" is not wrong, and a log that only accepts catalogue
/// entries is one people work around. So this is a **best-effort enrichment**,
/// never a requirement: a match adds a form image and a muscle group, and a miss
/// costs nothing but those.
///
/// Matching is case- and punctuation-insensitive, because "Bench Press",
/// "bench press" and "Bench-Press" are the same movement to everyone except a
/// string comparison.
///
/// It is also **word-order- and plural-insensitive**, which is a fix rather
/// than a flourish: the catalogue calls one movement "Cable Overhead Tricep
/// Extension", and a lifter typing the equally natural "Overhead Cable Tricep
/// Extension" used to get no image and no muscle group, as though they had
/// invented the exercise. Same words, same movement.
///
/// [find] deliberately stops there. Nothing in it guesses at near-misses or
/// edit distance, because the failure is asymmetric: no image costs a lifter
/// nothing, and the *wrong* image on the card they are looking at mid-set is
/// worse than a blank one.
///
/// [search] is the other way round, and forgives more: it offers a list for a
/// person to choose from, so a near-miss is a row they can skip rather than a
/// picture they are shown. Words in any order, other names for the same thing,
/// and one typo in a long word.
class ExerciseLookup {
  ExerciseLookup([List<Exercise>? catalogue])
    : this._(catalogue ?? exerciseCatalogue);

  ExerciseLookup._(List<Exercise> catalogue)
    : _byKey = <String, Exercise>{
        for (final e in catalogue) _normalise(e.name): e,
      },
      _byWords = _indexByWords(catalogue),
      _haystacks = <String, _Haystack>{
        for (final e in catalogue) e.name: _Haystack(e),
      };

  /// The muscle-group filter, in the order a body is read, top down. A test
  /// pins that every group in the catalogue is here.
  static const List<String> muscleGroups = <String>[
    'Chest',
    'Back',
    'Shoulders',
    'Biceps',
    'Triceps',
    'Core',
    'Glutes',
    'Legs',
    'Cardio',
  ];

  /// The equipment filter. Five kinds hold 243 of the 266 movements; the
  /// rest, from bands to a wall ball, share [otherEquipment] rather than a
  /// chip each for a handful of rows.
  static const List<String> equipment = <String>[
    'Barbell',
    'Dumbbell',
    'Cable',
    'Machine',
    'Bodyweight',
    otherEquipment,
  ];

  static const String otherEquipment = 'Other';

  final Map<String, Exercise> _byKey;

  /// Keyed by the movement's words, sorted and singularised. See [_wordKey].
  final Map<String, Exercise> _byWords;

  /// Each movement's words for [search], keyed by name.
  final Map<String, _Haystack> _haystacks;

  /// The catalogue entry for [name], or null if it is a movement of their own.
  ///
  /// Exact first, so a name that matches a catalogue entry outright can never
  /// be pulled to a different one by the looser pass.
  Exercise? find(String name) =>
      _byKey[_normalise(name)] ?? _byWords[_wordKey(name)];

  /// Everything, for the picker.
  Iterable<Exercise> get all => _byKey.values;

  /// Catalogue entries matching [query], narrowed to [muscleGroup] and
  /// [equipment] when given. An empty query lists everything the filters
  /// allow, alphabetically.
  ///
  /// **Every word must match**, in any order, at the start of a word in the
  /// name, the muscle group or the equipment — so "curl bi" finds "Bicep
  /// Curl", and so does the half-typed "bicep cu". Other names for the same
  /// thing count ([_otherNames]), and a word over four letters may carry one
  /// typo. Best first: no typos before a typo, then names that start with
  /// what was typed, then names that hold every word themselves rather than
  /// through their muscle group or equipment.
  List<Exercise> search(
    String query, {
    String? muscleGroup,
    String? equipment,
  }) {
    final words = _wordsOf(query, canonical: true);
    final ranked = <(Exercise, _Rank)>[];
    for (final exercise in all) {
      if (muscleGroup != null && exercise.muscleGroup != muscleGroup) continue;
      if (equipment != null && equipmentFilterOf(exercise) != equipment) {
        continue;
      }
      final rank = words.isEmpty
          ? const _Rank(typos: 0, startsWith: true, outsideName: 0)
          : _haystacks[exercise.name]!.rank(words, query);
      if (rank != null) ranked.add((exercise, rank));
    }
    ranked.sort((a, b) {
      final byRank = a.$2.compareTo(b.$2);
      return byRank != 0 ? byRank : a.$1.name.compareTo(b.$1.name);
    });
    return <Exercise>[for (final (exercise, _) in ranked) exercise];
  }

  /// Which [equipment] chip [exercise] falls under.
  static String equipmentFilterOf(Exercise exercise) =>
      equipment.contains(exercise.equipment)
      ? exercise.equipment
      : otherEquipment;

  /// Other names for the same thing, each rewritten to one spelling before
  /// anything is compared. Short on purpose: each line is a name lifters
  /// actually type, or a spelling the catalogue itself uses both ways.
  static const List<(String, String)> _otherNames = <(String, String)>[
    ('single arm', 'one arm'),
    ('db', 'dumbbell'),
    ('bb', 'barbell'),
    ('rdl', 'romanian deadlift'),
    // The catalogue spells these apart and together ("Lat Pull Down",
    // "Cable Tricep Pushdown", "Push Up", "Close Triceps Pushup").
    ('pull down', 'pulldown'),
    ('push down', 'pushdown'),
    ('pull up', 'pullup'),
    ('chin up', 'chinup'),
    ('push up', 'pushup'),
    ('sit up', 'situp'),
  ];

  /// [text]'s words, lower case and split on anything not a letter or digit,
  /// each singularised ("triceps" is "tricep"). [canonical] also rewrites
  /// other names to one spelling first.
  static List<String> _wordsOf(String text, {required bool canonical}) {
    var t = ' ${text.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), ' ')} ';
    if (canonical) {
      for (final (from, to) in _otherNames) {
        // Padded with spaces, so "db" rewrites the word and never the "db"
        // inside another one. Twice, for a name that repeats back to back.
        t = t.replaceAll(' $from ', ' $to ').replaceAll(' $from ', ' $to ');
      }
    }
    return <String>[
      for (final w in t.split(' '))
        if (w.isNotEmpty) _singular(w),
    ];
  }

  static String _normalise(String name) =>
      name.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  /// A movement's words, singularised and sorted — so "Cable Overhead Tricep
  /// Extension" and "Overhead Cable Tricep Extensions" produce the same key.
  static String _wordKey(String name) {
    final words =
        name
            .toLowerCase()
            .split(RegExp('[^a-z0-9]+'))
            .where((w) => w.isNotEmpty)
            .map(_singular)
            .toList()
          ..sort();
    return words.join(' ');
  }

  /// Drops a trailing plural `s`. Guards on `ss` and on short words so "press"
  /// and "abs" survive intact, which is the whole difficulty with doing this
  /// naively.
  static String _singular(String word) =>
      word.length > 3 && word.endsWith('s') && !word.endsWith('ss')
      ? word.substring(0, word.length - 1)
      : word;

  /// Builds the loose index, **dropping any key two movements share**.
  ///
  /// Same words in a different order is nearly always the same movement, but
  /// nearly is not always, and an ambiguous key that silently resolves to
  /// whichever entry was indexed last would put a confidently wrong picture on
  /// a card. Ambiguity therefore resolves to no match.
  static Map<String, Exercise> _indexByWords(List<Exercise> catalogue) {
    final index = <String, Exercise>{};
    final ambiguous = <String>{};
    for (final exercise in catalogue) {
      final key = _wordKey(exercise.name);
      final existing = index[key];
      if (existing != null && existing.name != exercise.name) {
        ambiguous.add(key);
        continue;
      }
      index[key] = exercise;
    }
    index.removeWhere((key, _) => ambiguous.contains(key));
    return index;
  }
}

/// How well one movement matched, best first.
class _Rank implements Comparable<_Rank> {
  const _Rank({
    required this.typos,
    required this.startsWith,
    required this.outsideName,
  });

  /// Words that matched only by forgiving a typo.
  final int typos;

  /// The name begins with what was typed.
  final bool startsWith;

  /// Words matched by the muscle group or equipment, not the name.
  final int outsideName;

  @override
  int compareTo(_Rank other) {
    if (typos != other.typos) return typos.compareTo(other.typos);
    if (startsWith != other.startsWith) return startsWith ? -1 : 1;
    return outsideName.compareTo(other.outsideName);
  }
}

/// One movement's words, worked out once rather than on every keystroke.
///
/// Both spellings of the name are kept: as written, and with other names
/// rewritten. The rewritten one alone would lose "Lat Pull Down" halfway
/// through typing "pull down", at "pull d", and bring it back a letter later.
class _Haystack {
  _Haystack(Exercise exercise)
    : _lowerName = exercise.name.toLowerCase(),
      _name = <String>{
        ...ExerciseLookup._wordsOf(exercise.name, canonical: false),
        ...ExerciseLookup._wordsOf(exercise.name, canonical: true),
      },
      _rest = <String>{
        ...ExerciseLookup._wordsOf(exercise.muscleGroup, canonical: true),
        ...ExerciseLookup._wordsOf(exercise.equipment, canonical: true),
      };

  final String _lowerName;
  final Set<String> _name;
  final Set<String> _rest;

  /// Null when a word matches nothing.
  _Rank? rank(List<String> words, String query) {
    var typos = 0;
    var outsideName = 0;
    for (final word in words) {
      if (_startsAny(_name, word)) continue;
      if (_startsAny(_rest, word)) {
        outsideName++;
        continue;
      }
      if (word.length > 4 && (_nearAny(_name, word) || _nearAny(_rest, word))) {
        typos++;
        continue;
      }
      return null;
    }
    return _Rank(
      typos: typos,
      startsWith: _lowerName.startsWith(query.trim().toLowerCase()),
      outsideName: outsideName,
    );
  }

  static bool _startsAny(Set<String> words, String prefix) =>
      words.any((w) => w.startsWith(prefix));

  /// One edit from a word, or from the start of one, since the lifter may be
  /// part-way through typing it.
  static bool _nearAny(Set<String> words, String typed) {
    for (final w in words) {
      for (var n = typed.length - 1; n <= typed.length + 1; n++) {
        if (n < 1 || n > w.length) continue;
        if (_withinOneEdit(typed, w.substring(0, n))) return true;
      }
    }
    return false;
  }

  /// Whether [a] and [b] are at most one edit apart: a letter added, dropped
  /// or changed, or two neighbouring letters swapped.
  static bool _withinOneEdit(String a, String b) {
    if (a == b) return true;
    if ((a.length - b.length).abs() > 1) return false;
    var i = 0;
    while (i < a.length && i < b.length && a[i] == b[i]) {
      i++;
    }
    final restA = a.substring(i);
    final restB = b.substring(i);
    if (restA.length > restB.length) return restA.substring(1) == restB;
    if (restB.length > restA.length) return restB.substring(1) == restA;
    // Same length: one letter changed, or two neighbours swapped.
    if (restA.substring(1) == restB.substring(1)) return true;
    return restA.length >= 2 &&
        restA[0] == restB[1] &&
        restA[1] == restB[0] &&
        restA.substring(2) == restB.substring(2);
  }
}
