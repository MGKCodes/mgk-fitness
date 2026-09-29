// Regression for EDGE-6: Finish had no busy guard, so it stayed live through
// a slow stop() (a Health read plus a backup push). A second tap re-entered
// _finish, called stop() again and popped the route a second time — which
// pops whatever is under it too, landing on a blank screen the app had to be
// killed to leave. See the throwaway reproduction under
// .claude/worktrees/review-edge/apps/mgk_run/test/zz_edge_review/double_finish_test.dart,
// whose route structure (copied from HomeShell._startRun) this borrows.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/run_recorder.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';
import 'package:mgk_run/src/features/recording/presentation/run_start_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

class _SlowStopRecorder implements RunRecorder {
  _SlowStopRecorder([this.stopTakes = const Duration(seconds: 3)]);
  final Duration stopTakes;
  int stops = 0;
  RecorderStatus _status = RecorderStatus.idle;
  final _points = StreamController<RunPoint>.broadcast();
  final _statuses = StreamController<RecorderStatus>.broadcast();
  final _problems = StreamController<RecorderProblem?>.broadcast();
  @override
  Stream<RunPoint> get points => _points.stream;
  @override
  Stream<RecorderStatus> get statusChanges => _statuses.stream;
  @override
  RecorderStatus get status => _status;
  @override
  RecorderProblem? get problem => null;
  @override
  Stream<RecorderProblem?> get problems => _problems.stream;
  @override
  RunPoint? get lastFix => null;
  @override
  Duration? get sinceLastFix => null;
  @override
  Duration get elapsed => const Duration(minutes: 30);
  void _set(RecorderStatus s) {
    _status = s;
    _statuses.add(s);
  }

  @override
  Future<void> start() async => _set(RecorderStatus.recording);
  @override
  Future<void> pause() async => _set(RecorderStatus.paused);
  @override
  Future<void> resume() async => _set(RecorderStatus.recording);
  @override
  Future<void> stop() async {
    stops++;
    await Future<void>.delayed(stopTakes);
    _set(RecorderStatus.stopped);
  }

  @override
  Future<void> discard() async {}
}

class _Obs extends NavigatorObserver {
  final List<String> log = <String>[];
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      log.add('pop ${route.settings.name}');
}

/// Pushes the same three-route shape `HomeShell._startRun` does — Home,
/// count-in, recording — and reports how many times Home's `.then` saw a
/// result. Shared by both tests below so the only difference between "fast"
/// and "slow" is the gap between taps.
Future<void> _openARun(
  WidgetTester tester,
  _SlowStopRecorder recorder,
  _Obs obs,
  List<bool?> finishedResults,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      navigatorObservers: <NavigatorObserver>[obs],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              child: const Text('Record a run'),
              onPressed: () {
                Navigator.of(context)
                    .push<bool>(
                      MaterialPageRoute<bool>(
                        settings: const RouteSettings(name: 'start'),
                        builder: (routeContext) => RunStartScreen(
                          countIn: Duration.zero,
                          onCancel: () => Navigator.of(routeContext).pop(false),
                          onStart: () async {
                            final bool? finished =
                                await Navigator.of(routeContext).push<bool>(
                                  MaterialPageRoute<bool>(
                                    settings: const RouteSettings(
                                      name: 'recording',
                                    ),
                                    builder: (recordContext) => RecordingScreen(
                                      recorder: recorder,
                                      onFinish: () =>
                                          Navigator.of(recordContext).pop(true),
                                      onCancel: () => Navigator.of(
                                        recordContext,
                                      ).pop(false),
                                    ),
                                  ),
                                );
                            if (!routeContext.mounted) return;
                            Navigator.of(routeContext).pop(finished ?? false);
                          },
                        ),
                      ),
                    )
                    .then((f) => finishedResults.add(f));
              },
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Record a run'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.tap(find.text('Start'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  expect(find.byType(RecordingScreen), findsOneWidget);
}

void main() {
  testWidgets('a slow double-tap on Finish stops once and pops exactly once', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final recorder = _SlowStopRecorder();
    final obs = _Obs();
    final finishedResults = <bool?>[];

    await _openARun(tester, recorder, obs, finishedResults);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Finish'));
    await tester.pump(const Duration(milliseconds: 1500));
    // Nothing has visibly finished yet, but Finish is no longer live: the
    // busy guard has already disabled it and put a spinner where its icon
    // was, in place of the old dead window where a second tap looked free.
    expect(find.text('Finish'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(OutlinedButton, 'Finish'),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Finish')); // the second tap: hits nothing
    await tester.pump(const Duration(milliseconds: 1600)); // stop() returns
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    expect(recorder.stops, 1);
    expect(obs.log.where((p) => p == 'pop /'), isEmpty);
    expect(finishedResults, <bool?>[true]);
    expect(find.text('Record a run'), findsOneWidget);
  });

  testWidgets('a fast double-tap on Finish (50 ms apart) also pops once', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final recorder = _SlowStopRecorder(const Duration(milliseconds: 300));
    final obs = _Obs();
    final finishedResults = <bool?>[];

    await _openARun(tester, recorder, obs, finishedResults);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Finish'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Finish')); // arrives while still busy
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(recorder.stops, 1);
    expect(obs.log.where((p) => p == 'pop /'), isEmpty);
    expect(find.text('Record a run'), findsOneWidget);
  });
}
