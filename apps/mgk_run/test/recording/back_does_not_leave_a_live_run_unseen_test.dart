// Regression for EDGE-2: RecordingScreen had no PopScope, so the Android
// back button / predictive-back gesture (and the iOS edge swipe, which drives
// the same route-pop machinery) popped the screen outright. HomeShell reads
// the null pop result as "not finished" and the recorder it never touched
// keeps recording, unseen: GPS and the "Recording your run" foreground
// service both stay on, and fixes keep piling into a run nobody can see or
// ever finishes. See the throwaway reproduction under
// .claude/worktrees/review-edge/apps/mgk_run/test/zz_edge_review/back_pops_live_run_test.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/run_recorder.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// Tracks exactly which lifecycle methods were called, the way the review's
/// own throwaway fakes do — `FakeRunRecorder` (the shared preview/test fake)
/// makes `stop()` and `discard()` indistinguishable from the outside, and
/// telling them apart is the point of the `dispose()` half of this fix.
class _TrackingRecorder implements RunRecorder {
  final List<String> calls = <String>[];
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
  Duration get elapsed => const Duration(minutes: 12);
  @override
  Future<void> start() async {
    calls.add('start');
    _status = RecorderStatus.recording;
  }

  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> resume() async => calls.add('resume');
  @override
  Future<void> stop() async {
    calls.add('stop');
    _status = RecorderStatus.stopped;
  }

  @override
  Future<void> discard() async {
    calls.add('discard');
    _status = RecorderStatus.stopped;
  }
}

void main() {
  testWidgets(
    'system Back mid-run opens the discard dialog instead of leaving',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final recorder = _TrackingRecorder();
      Object? popResult = 'not popped';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    popResult = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (routeContext) => RecordingScreen(
                          recorder: recorder,
                          onFinish: () => Navigator.of(routeContext).pop(true),
                          onCancel: () => Navigator.of(routeContext).pop(false),
                        ),
                      ),
                    );
                  },
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(RecordingScreen), findsOneWidget);
      expect(recorder.calls, <String>['start']);

      // The Android back button / predictive back.
      //
      // `pump(duration)` rather than `pumpAndSettle`: the screen is still
      // recording, so its own 1-second ticker is a live periodic timer that
      // `pumpAndSettle` would wait on forever (the same reason a busy
      // `PrimaryButton`'s spinner needs it, per CONTRIBUTING.md's testing
      // notes).
      final handled = await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(handled, isTrue);
      // Still here: Back opened the same choice the close button does,
      // rather than leaving with the recorder running unseen.
      expect(find.byType(RecordingScreen), findsOneWidget);
      expect(popResult, 'not popped');
      expect(find.text('Discard this run?'), findsOneWidget);
      expect(recorder.calls, <String>['start']); // neither stop nor discard

      // Confirm the discard from the dialog it opened.
      await tester.tap(find.text('Discard'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(RecordingScreen), findsNothing);
      expect(popResult, false);
      expect(recorder.calls, <String>['start', 'discard']);
    },
  );

  testWidgets(
    'dispose() discards a recorder still running when the screen is torn '
    'down some other way',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final recorder = _TrackingRecorder();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RecordingScreen(recorder: recorder),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(recorder.calls, <String>['start']);
      expect(recorder.status, RecorderStatus.recording);

      // Not a Back gesture and not a Navigator pop — the ancestor route is
      // simply replaced, the way a hot restart or an unrelated rebuild
      // could unmount this screen without ever asking it to leave.
      await tester.pumpWidget(const SizedBox());

      expect(recorder.calls, <String>['start', 'discard']);
    },
  );
}
