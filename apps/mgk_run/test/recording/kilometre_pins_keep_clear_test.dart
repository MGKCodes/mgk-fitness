import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/recording/presentation/route_map.dart';

/// **A looped course stacked its kilometre pins into a smudge.** The Royal
/// Parks half put kilometres 1, 9 and 15 on one spot. Pins are thinned in
/// screen space, earlier first, so the fitted route shows one per place and
/// zooming in brings the rest back.
void main() {
  Offset at(Offset o) => o;

  test('a pin on top of an earlier one is not drawn', () {
    final kept = clearOfEachOther<Offset>(
      const <Offset>[
        Offset(100, 100), // km 1
        Offset(200, 100), // km 2
        Offset(104, 102), // km 9, back at km 1
        Offset(300, 100), // km 3
        Offset(98, 99), // km 15, there again
      ],
      at,
      gap: 24,
    );

    expect(kept, const <Offset>[
      Offset(100, 100),
      Offset(200, 100),
      Offset(300, 100),
    ]);
  });

  test('pins with room are all kept', () {
    final spread = <Offset>[for (var i = 0; i < 10; i++) Offset(i * 30.0, 0)];
    expect(clearOfEachOther<Offset>(spread, at, gap: 24), spread);
  });

  test('the same pins drawn further apart, as when zoomed in, come back', () {
    const close = <Offset>[Offset(0, 0), Offset(10, 0)];
    const zoomed = <Offset>[Offset(0, 0), Offset(40, 0)];
    expect(clearOfEachOther<Offset>(close, at, gap: 24), hasLength(1));
    expect(clearOfEachOther<Offset>(zoomed, at, gap: 24), hasLength(2));
  });
}
