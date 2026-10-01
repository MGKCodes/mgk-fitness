import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/recording/data/live_readout_recorder.dart';
import 'package:mgk_run/src/features/recording/data/platform_live_readout.dart';
import 'package:mgk_run/src/features/recording/domain/live_readout.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/run_recorder.dart';
import 'package:mgk_units/mgk_units.dart';

/// A recorder a test can drive by hand.
class _Recorder implements RunRecorder {
  final _points = StreamController<RunPoint>.broadcast(sync: true);
  final _statuses = StreamController<RecorderStatus>.broadcast(sync: true);
  final List<String> calls = <String>[];

  @override
  RecorderStatus status = RecorderStatus.idle;

  @override
  RecorderProblem? problem;

  /// What [start] leaves behind, standing in for a permission refused.
  RecorderProblem? problemOnStart;

  @override
  Duration elapsed = Duration.zero;

  @override
  Duration? sinceLastFix = Duration.zero;

  @override
  RunPoint? lastFix;

  void fix(RunPoint point) {
    lastFix = point;
    _points.add(point);
  }

  void _set(RecorderStatus next) {
    status = next;
    _statuses.add(next);
  }

  @override
  Future<void> start() async {
    calls.add('start');
    problem = problemOnStart;
    if (problem == null) _set(RecorderStatus.recording);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _set(RecorderStatus.paused);
  }

  @override
  Future<void> resume() async {
    calls.add('resume');
    _set(RecorderStatus.recording);
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    _set(RecorderStatus.stopped);
  }

  @override
  Future<void> discard() async {
    calls.add('discard');
    _set(RecorderStatus.stopped);
  }

  @override
  Stream<RunPoint> get points => _points.stream;

  @override
  Stream<RecorderStatus> get statusChanges => _statuses.stream;

  @override
  Stream<RecorderProblem?> get problems =>
      const Stream<RecorderProblem?>.empty();
}

/// Writes down what the lock screen was told.
class _Readout implements LiveRunReadout {
  final List<LiveRunStatus> shown = <LiveRunStatus>[];
  int prepared = 0;
  int ended = 0;

  /// Throws from every call, standing in for a platform that refuses.
  bool broken = false;

  @override
  Future<void> prepare() async {
    prepared++;
  }

  @override
  Future<void> show(LiveRunStatus status) async {
    if (broken) throw StateError('no');
    shown.add(status);
  }

  @override
  Future<void> end() async {
    ended++;
  }
}

/// **A phone in an armband is a locked phone.** The run's distance, time and
/// pace were on the in-run screen and nowhere else, so for the whole of every
/// run they were behind a passcode.
void main() {
  // A run heading north at five minutes a kilometre: a fix a second, about
  // 3.3 m apart.
  final DateTime began = DateTime(2026, 10, 2, 7);
  RunPoint at(int second) => RunPoint(
    latitude: 53.8 + second * 0.00003,
    longitude: -1.55,
    accuracyMeters: 5,
    timestamp: began.add(Duration(seconds: second)),
  );

  late _Recorder inner;
  late _Readout readout;
  late DateTime clock;
  late LiveReadoutRecorder recorder;

  setUp(() {
    inner = _Recorder();
    readout = _Readout();
    clock = began;
    recorder = LiveReadoutRecorder(
      inner,
      readout,
      unit: UnitSystem.metric,
      now: () => clock,
    );
  });

  /// Runs [seconds] of the run, a fix a second.
  void run(int from, int seconds) {
    for (var s = from; s < from + seconds; s++) {
      clock = began.add(Duration(seconds: s));
      inner.elapsed = Duration(seconds: s);
      inner.fix(at(s));
    }
  }

  group('the recorder that tells the lock screen', () {
    test('says so the moment the run starts', () async {
      await recorder.start();

      expect(inner.calls, <String>['start']);
      expect(readout.shown, hasLength(1));
      expect(readout.shown.single.distance, '0.00 km');
      expect(readout.shown.single.pace, '--:-- /km');
      expect(readout.shown.single.paused, isFalse);
    });

    test('refreshes every few seconds, not on every fix', () async {
      await recorder.start();
      run(1, 20);

      // The first, then one every four seconds: far fewer than twenty.
      expect(readout.shown.length, inInclusiveRange(5, 7));
    });

    test('gives the figures the in-run screen gives', () async {
      await recorder.start();
      run(1, 120);

      final LiveRunStatus last = readout.shown.last;
      // 120 fixes 3.3 m apart is about 400 m, at about five minutes a
      // kilometre.
      expect(last.distance, matches(RegExp(r'^0\.[34]\d km$')));
      expect(last.pace, matches(RegExp(r'^[45]:\d\d /km$')));
      expect(last.elapsed.inSeconds, inInclusiveRange(116, 120));
    });

    test('says paused at once, and resumed at once', () async {
      await recorder.start();
      run(1, 10);
      final int before = readout.shown.length;

      // One second on, well inside the four between refreshes.
      clock = clock.add(const Duration(seconds: 1));
      await recorder.pause();
      expect(readout.shown.length, before + 1);
      expect(readout.shown.last.paused, isTrue);

      await recorder.resume();
      expect(readout.shown.length, before + 2);
      expect(readout.shown.last.paused, isFalse);
    });

    test('takes it down when the run is finished', () async {
      await recorder.start();
      run(1, 10);
      await recorder.stop();

      expect(inner.calls.last, 'stop');
      expect(readout.ended, 1);

      // And a fix that arrives late shows nothing again.
      final int shown = readout.shown.length;
      inner.fix(at(11));
      expect(readout.shown.length, shown);
    });

    test('and when it is discarded', () async {
      await recorder.start();
      await recorder.discard();

      expect(inner.calls.last, 'discard');
      expect(readout.ended, 1);
    });

    test('announces nothing for a run that could not start', () async {
      inner.problemOnStart = RecorderProblem.permissionDenied;
      await recorder.start();

      expect(readout.shown, isEmpty);
      expect(recorder.problem, RecorderProblem.permissionDenied);
    });

    test('a readout that fails changes nothing about the run', () async {
      readout.broken = true;
      final errors = <Object>[];

      await runZonedGuarded(() async {
        await recorder.start();
        run(1, 10);
        await recorder.pause();
        await recorder.stop();
      }, (error, stack) => errors.add(error));

      expect(inner.calls, <String>['start', 'pause', 'stop']);
      // What it throws is the caller's to swallow, and the platform readout
      // does. Nothing here turned it into a failed run.
      expect(inner.status, RecorderStatus.stopped);
    });

    test('everything else is the recorder underneath', () async {
      await recorder.start();
      run(1, 3);

      expect(recorder.status, RecorderStatus.recording);
      expect(recorder.elapsed, inner.elapsed);
      expect(recorder.lastFix, inner.lastFix);
      expect(recorder.sinceLastFix, inner.sinceLastFix);
    });
  });

  group('over the platform channel', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];

    tearDown(() {
      calls.clear();
      messenger.setMockMethodCallHandler(PlatformLiveReadout.channel, null);
    });

    test('the figures go across as the native side reads them', () async {
      messenger.setMockMethodCallHandler(PlatformLiveReadout.channel, (
        call,
      ) async {
        calls.add(call);
        return true;
      });
      const PlatformLiveReadout platform = PlatformLiveReadout();

      await platform.prepare();
      await platform.show(
        const LiveRunStatus(
          distance: '5.02 km',
          pace: '5:31 /km',
          elapsed: Duration(minutes: 27, seconds: 41),
          paused: false,
        ),
      );
      await platform.end();

      expect(calls.map((c) => c.method), <String>['prepare', 'show', 'end']);
      expect(calls[1].arguments, <String, Object>{
        'distance': '5.02 km',
        'pace': '5:31 /km',
        'elapsedSeconds': 1661,
        'elapsed': '27:41',
        'paused': false,
      });
      // Written in MainActivity.kt and LiveRunChannel.swift too.
      expect(PlatformLiveReadout.channel.name, 'com.mgkcodes.fitness.run/live');
    });

    test('a platform with no native half is not an error', () async {
      // No handler: every call throws MissingPluginException, as it does in
      // a widget test and on the web.
      const PlatformLiveReadout platform = PlatformLiveReadout();

      await platform.prepare();
      await platform.show(
        const LiveRunStatus(
          distance: '0.00 km',
          pace: '--:-- /km',
          elapsed: Duration.zero,
          paused: false,
        ),
      );
      await platform.end();
    });

    test('nor is one that refuses', () async {
      messenger.setMockMethodCallHandler(
        PlatformLiveReadout.channel,
        (call) async => throw PlatformException(code: 'no'),
      );
      await const PlatformLiveReadout().end();
    });
  });
}
