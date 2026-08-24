import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/ids.dart';

/// **A timestamp is not an identity.**
///
/// Both run-id generators used to be `DateTime.now().microsecondsSinceEpoch`,
/// and both writers upsert, so two rows written inside one clock tick were one
/// row — the second overwriting the first with nothing said. It was found by a
/// test asserting the log's order failing about one run in three on Windows,
/// whose clock is coarse enough that three inserts in a loop routinely share a
/// tick.
///
/// The loop below is the shape that broke it. It is deliberately tight: the
/// point is not that ids differ when generated a second apart, it is that they
/// differ when generated as fast as the machine can manage.
void main() {
  test('ids generated in a tight loop are all distinct', () {
    final ids = <String>{for (var i = 0; i < 5000; i++) newLocalId()};
    expect(ids, hasLength(5000));
  });

  test('the prefix is kept, because it says where a run came from', () {
    expect(newLocalId('manual-'), startsWith('manual-'));
    // And it is still distinguishable from a recorded one, which has none.
    expect(newLocalId(), isNot(startsWith('manual-')));
  });

  test('prefixed ids collide no more than bare ones', () {
    final ids = <String>{for (var i = 0; i < 5000; i++) newLocalId('manual-')};
    expect(ids, hasLength(5000));
  });

  test('ids still lead with the clock, so they sort and read chronologically', () {
    // The timestamp was worth keeping; it was only ever wrong as the *whole*
    // identity. A reader should still be able to tell which run is older.
    final first = newLocalId();
    final second = newLocalId();
    int stampOf(String id) => int.parse(id.split('-').first);
    expect(stampOf(second), greaterThanOrEqualTo(stampOf(first)));
  });
}
