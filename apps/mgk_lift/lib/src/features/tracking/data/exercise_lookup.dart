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
/// It deliberately stops there. Nothing here guesses at near-misses or edit
/// distance, because the failure is asymmetric: no image costs a lifter
/// nothing, and the *wrong* image on the card they are looking at mid-set is
/// worse than a blank one.
class ExerciseLookup {
  ExerciseLookup([List<Exercise>? catalogue])
    : this._(catalogue ?? exerciseCatalogue);

  ExerciseLookup._(List<Exercise> catalogue)
    : _byKey = <String, Exercise>{
        for (final e in catalogue) _normalise(e.name): e,
      },
      _byWords = _indexByWords(catalogue);

  final Map<String, Exercise> _byKey;

  /// Keyed by the movement's words, sorted and singularised. See [_wordKey].
  final Map<String, Exercise> _byWords;

  /// The catalogue entry for [name], or null if it is a movement of their own.
  ///
  /// Exact first, so a name that matches a catalogue entry outright can never
  /// be pulled to a different one by the looser pass.
  Exercise? find(String name) =>
      _byKey[_normalise(name)] ?? _byWords[_wordKey(name)];

  /// Everything, for the picker.
  Iterable<Exercise> get all => _byKey.values;

  /// Catalogue entries whose name or muscle group contains [query].
  List<Exercise> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return all.toList()..sort((a, b) => a.name.compareTo(b.name));
    }
    return all
        .where(
          (e) =>
              e.name.toLowerCase().contains(q) ||
              e.muscleGroup.toLowerCase().contains(q) ||
              e.equipment.toLowerCase().contains(q),
        )
        .toList()
      ..sort((a, b) {
        // Names that *start* with the query first — typing "bench" should not
        // bury "Barbell Bench Press" under everything that merely mentions it.
        final aStarts = a.name.toLowerCase().startsWith(q);
        final bStarts = b.name.toLowerCase().startsWith(q);
        if (aStarts != bStarts) return aStarts ? -1 : 1;
        return a.name.compareTo(b.name);
      });
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
