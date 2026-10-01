import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// A tab that counts how many times it has been built from nothing, which is
/// what losing its state would look like.
class _Counted extends StatefulWidget {
  const _Counted(this.name, this.inits);

  final String name;
  final Map<String, int> inits;

  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    widget.inits[widget.name] = (widget.inits[widget.name] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: Center(
      child: TextButton(onPressed: () {}, child: Text(widget.name)),
    ),
  );
}

/// The tab roots used to change in one frame. They are kept the same way and
/// now move, and what must not change is everything `IndexedStack` promised.
void main() {
  Future<Map<String, int>> pump(
    WidgetTester tester,
    int index, {
    Map<String, int>? inits,
    bool reduceMotion = false,
  }) async {
    final Map<String, int> counts = inits ?? <String, int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: TabStack(
              index: index,
              children: <Widget>[
                _Counted('one', counts),
                _Counted('two', counts),
                _Counted('three', counts),
              ],
            ),
          ),
        ),
      ),
    );
    return counts;
  }

  double opacityOf(WidgetTester tester, String name) => tester
      .widget<Opacity>(
        find.ancestor(
          of: find.text(name, skipOffstage: false),
          matching: find.byType(Opacity),
        ),
      )
      .opacity;

  testWidgets('shows one tab and keeps the others built', (tester) async {
    final inits = await pump(tester, 0);

    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsNothing);
    expect(find.text('two', skipOffstage: false), findsOneWidget);
    expect(inits, <String, int>{'one': 1, 'two': 1, 'three': 1});
  });

  testWidgets('a change of tab rebuilds nothing from scratch', (tester) async {
    final inits = await pump(tester, 0);
    await pump(tester, 2, inits: inits);
    await tester.pumpAndSettle();
    await pump(tester, 1, inits: inits);
    await tester.pumpAndSettle();

    expect(inits, <String, int>{'one': 1, 'two': 1, 'three': 1});
    expect(find.text('two'), findsOneWidget);
    expect(find.text('one'), findsNothing);
  });

  testWidgets('the change is drawn: both are on screen part way through', (
    tester,
  ) async {
    final inits = await pump(tester, 0);
    await pump(tester, 1, inits: inits);
    // A sixth of the way in: the old tab is still fading out.
    await tester.pump(const Duration(milliseconds: 70));

    expect(find.text('one'), findsOneWidget);
    expect(opacityOf(tester, 'one'), inExclusiveRange(0, 1));
    expect(opacityOf(tester, 'two'), 0, reason: 'not started arriving yet');

    await tester.pump(const Duration(milliseconds: 200));
    expect(opacityOf(tester, 'one'), 0);
    expect(opacityOf(tester, 'two'), inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(find.text('one'), findsNothing);
    expect(opacityOf(tester, 'two'), 1);
  });

  testWidgets('a tab arrives from the side it lives on', (tester) async {
    final inits = await pump(tester, 0);
    final double rest = tester.getCenter(find.text('one')).dx;

    await pump(tester, 1, inits: inits);
    await tester.pump(const Duration(milliseconds: 220));
    expect(
      tester.getCenter(find.text('two')).dx,
      greaterThan(rest),
      reason: 'the tab to the right comes in from the right',
    );
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('two')).dx, rest);

    await pump(tester, 0, inits: inits);
    await tester.pump(const Duration(milliseconds: 220));
    expect(
      tester.getCenter(find.text('one')).dx,
      lessThan(rest),
      reason: 'and the tab to the left from the left',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a tab on its way out takes no taps', (tester) async {
    var taps = 0;
    Widget stack(int index) => MaterialApp(
      home: Scaffold(
        body: TabStack(
          index: index,
          children: <Widget>[
            SizedBox.expand(
              child: TextButton(
                onPressed: () => taps++,
                child: const Text('leaving'),
              ),
            ),
            const SizedBox.expand(),
          ],
        ),
      ),
    );
    await tester.pumpWidget(stack(0));
    await tester.pumpWidget(stack(1));
    await tester.pump(const Duration(milliseconds: 60));

    await tester.tap(find.text('leaving'), warnIfMissed: false);

    expect(taps, 0);
    await tester.pumpAndSettle();
  });

  testWidgets('with Reduce Motion on, the change is immediate', (tester) async {
    final inits = await pump(tester, 0, reduceMotion: true);
    await pump(tester, 1, inits: inits, reduceMotion: true);
    await tester.pump();

    expect(find.text('one'), findsNothing);
    expect(find.text('two'), findsOneWidget);
    expect(opacityOf(tester, 'two'), 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
