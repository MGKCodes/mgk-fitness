import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/history/domain/run_draft.dart';

/// Resolving "yesterday's run" to a row.
///
/// The coach is never told a run's id, so it names a day and Dart finds the
/// run. **Refusing is the feature**, not a limitation: two runs on one day is
/// ordinary, and a wrong choice rewrites a run the runner never mentioned in a
/// way that leaves the log looking entirely normal.
void main() {
  DateTime at(int day, [int hour = 7]) => DateTime(2026, 7, day, hour);

  List<DateTime> runs(List<DateTime> l) => l;

  DateTime? resolve(List<DateTime> all, DateTime day) =>
      soleRunOn<DateTime>(all, day, startedAt: (d) => d);

  test('one run on the day is found', () {
    final all = runs(<DateTime>[at(27), at(28), at(29)]);
    expect(resolve(all, at(28)), at(28));
  });

  test('the time of day does not matter, only the date', () {
    // "yesterday's run" is a thing a person says about their own day.
    final all = runs(<DateTime>[at(28, 6), at(27, 20)]);
    expect(resolve(all, DateTime(2026, 7, 28, 23, 59)), at(28, 6));
  });

  test('no run on the day is a refusal', () {
    final all = runs(<DateTime>[at(27), at(29)]);
    expect(resolve(all, at(28)), isNull);
  });

  test('TWO runs on the day is a refusal, not a pick', () {
    // The load-bearing case. An easy morning run and an evening parkrun is a
    // perfectly normal Saturday, and choosing between them silently would
    // rewrite the one the runner did not mean.
    final all = runs(<DateTime>[at(28, 7), at(28, 19)]);
    expect(resolve(all, at(28)), isNull);
  });

  test('three on the day is still a refusal', () {
    final all = runs(<DateTime>[at(28, 6), at(28, 12), at(28, 19)]);
    expect(resolve(all, at(28)), isNull);
  });

  test('an empty log resolves to nothing rather than throwing', () {
    expect(resolve(<DateTime>[], at(28)), isNull);
  });

  test('a day either side is not a near miss', () {
    // No fuzzy matching. "Yesterday" that finds a run from two days ago is a
    // wrong edit wearing a helpful face.
    final all = runs(<DateTime>[at(28)]);
    expect(resolve(all, at(27)), isNull);
    expect(resolve(all, at(29)), isNull);
  });

  // ---- applying a correction ------------------------------------------------

  test('a change touches only what was restated', () {
    // "make it 6k" changes the distance. The duration, effort and notes are
    // the stored ones, not the model's recollection of them.
    const stored = RunDraft(
      distanceMeters: 5000,
      duration: Duration(minutes: 26),
      rpe: 6,
      notes: 'felt easy',
      type: kTypeOutdoor,
    );
    final changed = stored.copyWith(distanceMeters: 6000);

    expect(changed.distanceMeters, 6000);
    expect(changed.duration, const Duration(minutes: 26));
    expect(changed.rpe, 6);
    expect(changed.notes, 'felt easy');
    expect(changed.type, kTypeOutdoor);
  });
}
