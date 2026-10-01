import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/live_readout.dart';
import 'package:mgk_ui/mgk_ui.dart';

class _Readout implements LiveRunReadout {
  final List<String> calls = <String>[];
  final List<LiveRunStatus> shown = <LiveRunStatus>[];

  @override
  Future<void> prepare() async => calls.add('prepare');

  @override
  Future<void> show(LiveRunStatus status) async {
    calls.add('show');
    shown.add(status);
  }

  @override
  Future<void> end() async => calls.add('end');
}

/// The join the unit tests cannot see: that the app hands the recorder it
/// actually records with to the lock screen, and asks for what the platform
/// needs while the runner is still looking at the screen
/// ([ADR-0045](../../docs/decisions/0045-the-runs-figures-on-the-lock-screen.md)).
void main() {
  Future<_Readout> pumpHome(WidgetTester tester) async {
    final readout = _Readout();
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'runner@example.com'),
          historySource: () async => const [],
          recorderFactory: () =>
              FakeRunRecorder(interval: const Duration(milliseconds: 500)),
          liveReadout: readout,
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return readout;
  }

  testWidgets('it is asked for on the way to the start screen, not at Start', (
    tester,
  ) async {
    final readout = await pumpHome(tester);
    expect(readout.calls, isEmpty);

    await tester.tap(find.text('Record a run'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Asked, and nothing shown: no run is being recorded yet.
    expect(readout.calls, <String>['prepare']);
  });

  testWidgets('and the run it records is the run the lock screen is told of', (
    tester,
  ) async {
    final readout = await pumpHome(tester);

    await tester.tap(find.text('Record a run'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Start'));
    // The count-in, and a few seconds of the run.
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(readout.calls.where((c) => c == 'show'), isNotEmpty);
    expect(readout.shown.first.paused, isFalse);
    expect(readout.calls, isNot(contains('end')));
  });
}
