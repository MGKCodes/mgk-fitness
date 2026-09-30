import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/run_recorder.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// Finishing (screen board R29): both controls show a spinner while the run
/// is saved. The rings sat against their labels, and Resume's was dark
/// `onPrimary` on the grey of a disabled button.
void main() {
  testWidgets('each ring is in its label colour, clear of the label', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final recorder = _HeldStop();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(recorder: recorder, onCancel: () {}),
      ),
    );
    await recorder.start();
    await tester.pump();
    await recorder.pause();
    await tester.pump();

    await tester.tap(find.text('Finish'));
    // Two frames: the buttons take their disabled state on the frame after
    // the one that disables them.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    for (final label in <String>['Resume', 'Finish']) {
      final text = find.text(label);
      final ring = find.descendant(
        of: find.ancestor(of: text, matching: find.byType(Row)).first,
        matching: find.byType(CircularProgressIndicator),
      );
      expect(ring, findsOneWidget, reason: label);

      final inked = tester
          .renderObject<RenderParagraph>(text)
          .text
          .style
          ?.color;
      expect(
        tester.widget<CircularProgressIndicator>(ring).color,
        inked,
        reason: '$label: the ring is drawn in what the label is drawn in',
      );
      final gap = tester.getTopLeft(text).dx - tester.getTopRight(ring).dx;
      expect(gap, greaterThanOrEqualTo(8), reason: '$label: $gap pt apart');
    }
    // The disabled fill is not what onPrimary was chosen for.
    final resumeRing = find.descendant(
      of: find
          .ancestor(of: find.text('Resume'), matching: find.byType(Row))
          .first,
      matching: find.byType(CircularProgressIndicator),
    );
    expect(
      tester.widget<CircularProgressIndicator>(resumeRing).color,
      AppColors.textTertiary,
    );

    recorder.saved.complete();
    await tester.pump();
  });
}

/// Pauses, and holds Finish's save open so the spinners stay on screen.
class _HeldStop implements RunRecorder {
  final Completer<void> saved = Completer<void>();
  RecorderStatus _status = RecorderStatus.idle;
  final _points = StreamController<RunPoint>.broadcast();
  final _statuses = StreamController<RecorderStatus>.broadcast();
  final _problems = StreamController<RecorderProblem?>.broadcast();

  void _set(RecorderStatus s) {
    _status = s;
    _statuses.add(s);
  }

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
  Future<void> start() async => _set(RecorderStatus.recording);
  @override
  Future<void> pause() async => _set(RecorderStatus.paused);
  @override
  Future<void> resume() async => _set(RecorderStatus.recording);
  @override
  Future<void> stop() async {
    await saved.future;
    _set(RecorderStatus.stopped);
  }

  @override
  Future<void> discard() async {}
}
