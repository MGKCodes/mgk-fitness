import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_run/src/features/coaching/domain/session_effort.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/recording/domain/run_recorder.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';
import 'package:mgk_run/src/features/recording/presentation/route_map.dart';
import 'package:mgk_units/mgk_units.dart';

import 'plate.dart';

/// Every state of the in-run screen, captured in one pass for a contact sheet.
///
/// The point of a board is comparison: a state that looks fine alone often
/// looks wrong beside its neighbours, and the states that never get looked at
/// are exactly the ones that ship broken. Each entry names what it is for, so
/// the sheet reads as a review rather than a gallery.
///
/// Regenerate with:
///
///     flutter test test/plates/board.dart
///
/// Basemap tiles are absent throughout — the test framework answers every
/// network image with a 400. The map's ground, its route and its position
/// marker are all real; only the tile art is missing.
void main() {
  late DateTime clock;

  FakeRunRecorder recorder({
    RecorderProblem? failsWith,
    Duration acquireAfter = Duration.zero,
    int? traceLength,
    Duration? pacePerKm,
  }) {
    clock = DateTime(2026, 1, 1, 8);
    return FakeRunRecorder(
      interval: const Duration(milliseconds: 20),
      failsWith: failsWith,
      acquireAfter: acquireAfter,
      // A trace that runs out is how the fake starves the screen of fixes
      // *without* leaving the recording state — which is the only way to reach
      // the signal-lost readout. Pausing looks similar from the inside and is
      // not the same screen at all: it says Paused, and offers Resume.
      trace: traceLength == null && pacePerKm == null
          ? null
          : demoRunTrace(
              pacePerKm: pacePerKm,
            ).take(traceLength ?? 440).toList(),
      now: () => clock,
    );
  }

  /// Steps the trace forward, moving the clock in the same 3-second step the
  /// canned trace uses so elapsed time and distance stay consistent.
  Future<void> Function(WidgetTester) advance(int points) =>
      (WidgetTester tester) async {
        await tester.pump();
        for (int i = 0; i < points; i++) {
          clock = clock.add(const Duration(seconds: 3));
          await tester.pump(const Duration(milliseconds: 20));
        }
      };

  const PlannedSession easy5k = PlannedSession(
    weekday: DateTime.monday,
    kind: SessionKind.easy,
    distanceMeters: 5000,
  );

  Widget screen(
    FakeRunRecorder rec, {
    PlannedSession? session = easy5k,
    SessionKind? kind,
  }) => RecordingScreen(
    recorder: rec,
    plannedSession: kind == null
        ? session
        : PlannedSession(
            weekday: DateTime.monday,
            kind: kind,
            distanceMeters: 5000,
          ),
    paces: session == null
        ? null
        : TrainingPaces.fromRace(
            Distance.meters(5000),
            const Duration(minutes: 24, seconds: 30),
          ),
    onCancel: () {},
  );

  /// One capture. Named rather than numbered in the call, so reordering the
  /// board does not silently renumber every file in the sheet.
  Future<void> shot(
    WidgetTester tester,
    String name,
    Widget child, {
    Size size = kPhone,
    Future<void> Function(WidgetTester)? drive,
  }) => plate(tester, name, child, size: size, drive: drive);

  group('planned session', () {
    testWidgets('acquiring', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder(
        acquireAfter: const Duration(seconds: 30),
      );
      await shot(
        tester,
        '00-acquiring',
        screen(rec),
        drive: (WidgetTester t) async => t.pump(),
      );
      await rec.stop();
    });

    testWidgets('early', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder();
      await shot(tester, '01-early', screen(rec), drive: advance(5));
      await rec.stop();
    });

    testWidgets('warming', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder();
      await shot(tester, '02-warming', screen(rec), drive: advance(40));
      await rec.stop();
    });

    testWidgets('warmed', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder();
      await shot(tester, '03-warmed', screen(rec), drive: advance(125));
      await rec.stop();
    });

    testWidgets('deep', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder();
      await shot(tester, '04-deep', screen(rec), drive: advance(400));
      await rec.stop();
    });

    testWidgets('paused', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder();
      await shot(
        tester,
        '05-paused',
        screen(rec),
        drive: (WidgetTester t) async {
          await advance(125)(t);
          await rec.pause();
          await t.pump();
        },
      );
      await rec.stop();
    });

    testWidgets('lapped', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder();
      await shot(
        tester,
        '06-lapped',
        screen(rec),
        drive: (WidgetTester t) async {
          await advance(80)(t);
          await t.tap(find.text('Lap'));
          await advance(80)(t);
        },
      );
      await rec.stop();
    });

    testWidgets('sheet open', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder();
      await shot(
        tester,
        '07-sheet-open',
        screen(rec),
        drive: (WidgetTester t) async {
          await advance(125)(t);
          // Drag the sheet to its full detent — the state nobody reads while
          // moving, and therefore the one least often looked at.
          await t.drag(find.text('DISTANCE'), const Offset(0, -420));
          // Settle through [advance] rather than one long pump. A 400 ms pump
          // fires twenty of the trace's 20 ms timers while the injected clock
          // stands still, so distance runs ahead of elapsed and the readout
          // starts contradicting its own splits — a plate that looks like a
          // bug is worse than no plate.
          await advance(20)(t);
        },
      );
      await rec.stop();
    });

    testWidgets('panned away from the runner', (WidgetTester tester) async {
      // The recentre control, which appears **only** once somebody has moved
      // the map (ADR-0031) — so it exists in no other plate and can be looked
      // at nowhere else on this machine.
      final FakeRunRecorder rec = recorder();
      await shot(
        tester,
        '23-panned',
        screen(rec),
        drive: (WidgetTester t) async {
          await advance(125)(t);
          // Through the widget's own callback: driving flutter_map's gesture
          // detector here would be plating flutter_map rather than this screen.
          t.widget<RouteMap>(find.byType(RouteMap)).onUserPan!();
          await advance(5)(t);
        },
      );
      await rec.stop();
    });

    testWidgets('peeked, with the map full screen', (
      WidgetTester tester,
    ) async {
      // The third detent (ADR-0031): a handle and two figures, so the map has
      // the screen. Dragged down rather than set, because what is worth seeing
      // is that the drag lands there and that the content swapped rather than
      // being clipped.
      final FakeRunRecorder rec = recorder();
      await shot(
        tester,
        '24-peek',
        screen(rec),
        drive: (WidgetTester t) async {
          await advance(125)(t);
          await t.drag(find.text('DISTANCE'), const Offset(0, 300));
          await advance(20)(t);
        },
      );
      await rec.stop();
    });

    testWidgets('signal lost', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder(traceLength: 125);
      await shot(
        tester,
        '08-signal-lost',
        screen(rec),
        drive: (WidgetTester t) async {
          await advance(125)(t);
          // The trace is spent, so no fix arrives again — but the run is still
          // recording and the clock is still running. This is the state that
          // used to show three confident bars over a distance that had stopped
          // moving.
          await advance(30)(t);
        },
      );
      await rec.stop();
    });
  });

  // The band for an easy 5 k off a 24:30 time trial is 6:24–6:55. Three runs
  // at the same distance, differing only in pace, so the three verdicts can be
  // read against each other rather than one at a time.
  //
  // This is the whole reason demoRunTrace takes a pace: on the default loop the
  // screen says PICK IT UP at every distance, and a board that can only render
  // one of three states cannot be used to judge the other two.
  group('verdicts', () {
    final TrainingPaces paces = TrainingPaces.fromRace(
      Distance.meters(5000),
      const Duration(minutes: 24, seconds: 30),
    );

    /// Derived from the band rather than typed in, so these stay outside it if
    /// the pace model ever moves.
    Duration under(SessionKind kind) => Duration(
      seconds: bandFor(kind, paces)!.slow.secondsPerKilometer.round() + 75,
    );
    Duration over(SessionKind kind) => Duration(
      seconds: bandFor(kind, paces)!.fast.secondsPerKilometer.round() - 75,
    );

    for (final (String name, SessionKind kind, Duration pace)
        in <(String, SessionKind, Duration)>[
          ('19-easy-under', SessionKind.easy, under(SessionKind.easy)),
          ('20-easy-over', SessionKind.easy, over(SessionKind.easy)),
          (
            '21-threshold-under',
            SessionKind.threshold,
            under(SessionKind.threshold),
          ),
          (
            '22-threshold-over',
            SessionKind.threshold,
            over(SessionKind.threshold),
          ),
        ]) {
      testWidgets(name, (WidgetTester tester) async {
        final FakeRunRecorder rec = recorder(pacePerKm: pace);
        await shot(tester, name, screen(rec, kind: kind), drive: advance(125));
        await rec.stop();
      });
    }
  });

  group('no plan', () {
    testWidgets('early', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder();
      await shot(
        tester,
        '09-unplanned-early',
        screen(rec, session: null),
        drive: advance(5),
      );
      await rec.stop();
    });

    testWidgets('running', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder();
      await shot(
        tester,
        '10-unplanned-running',
        screen(rec, session: null),
        drive: advance(125),
      );
      await rec.stop();
    });
  });

  group('problems', () {
    testWidgets('permission denied', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder(
        failsWith: RecorderProblem.permissionDenied,
      );
      await shot(
        tester,
        '11-permission-denied',
        screen(rec),
        drive: (WidgetTester t) async => t.pump(),
      );
      await rec.stop();
    });

    testWidgets('permission denied forever', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder(
        failsWith: RecorderProblem.permissionDeniedForever,
      );
      await shot(
        tester,
        '12-permission-forever',
        screen(rec),
        drive: (WidgetTester t) async => t.pump(),
      );
      await rec.stop();
    });

    testWidgets('location services off', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder(
        failsWith: RecorderProblem.locationServicesOff,
      );
      await shot(
        tester,
        '13-services-off',
        screen(rec),
        drive: (WidgetTester t) async => t.pump(),
      );
      await rec.stop();
    });

    testWidgets('approximate location only', (WidgetTester tester) async {
      // New in build 26 (C26 on the test sheet). An iPhone with Precise
      // Location off used to sit on "Acquiring GPS" and save a 0 m run; the
      // recorder now reports it as its own problem, with the one fix that
      // works.
      final FakeRunRecorder rec = recorder(
        failsWith: RecorderProblem.reducedAccuracy,
      );
      await shot(
        tester,
        '25-precise-off',
        screen(rec),
        drive: (WidgetTester t) async => t.pump(),
      );
      await rec.stop();
    });

    testWidgets('location failed', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder(
        failsWith: RecorderProblem.locationFailed,
      );
      await shot(
        tester,
        '14-location-failed',
        screen(rec),
        drive: (WidgetTester t) async => t.pump(),
      );
      await rec.stop();
    });
  });

  group('leaving a run', () {
    testWidgets('finishing, while the run is being saved', (
      WidgetTester tester,
    ) async {
      // New in build 26 (C24). A double tap on Finish used to make two runs;
      // the controls now hold a spinner until the first tap has settled. The
      // save is held open here so the plate can see the moment it lasts.
      clock = DateTime(2026, 1, 1, 8);
      final Completer<void> saving = Completer<void>();
      final _SlowStop rec = _SlowStop(
        saving.future,
        interval: const Duration(milliseconds: 20),
        now: () => clock,
      );
      await shot(
        tester,
        '26-finishing',
        screen(rec),
        drive: (WidgetTester t) async {
          await advance(125)(t);
          await rec.pause();
          await t.pump();
          await t.tap(find.text('Finish'));
          // Far enough into the spinner's sweep that it reads as one: at a
          // third of a second it is a single dot.
          await t.pump(const Duration(milliseconds: 300));
          await t.pump(const Duration(milliseconds: 450));
        },
      );
      saving.complete();
      await tester.pump();
    });

    testWidgets('back mid-run asks first', (WidgetTester tester) async {
      // New in build 26 (C22/C23). Back and the iOS edge swipe used to pop
      // the screen and leave the run recording out of sight. Every way out now
      // meets this question; the close button is the one a plate can press.
      final FakeRunRecorder rec = recorder();
      await shot(
        tester,
        '27-discard',
        screen(rec),
        drive: (WidgetTester t) async {
          await advance(125)(t);
          await t.tap(find.byTooltip('Cancel run'));
          await advance(10)(t);
        },
      );
      await rec.stop();
    });
  });

  group('other phones', () {
    testWidgets('small early', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder();
      await shot(
        tester,
        '15-small-early',
        screen(rec),
        size: kSmallPhone,
        drive: advance(5),
      );
      await rec.stop();
    });

    testWidgets('small warmed', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder();
      await shot(
        tester,
        '16-small-warmed',
        screen(rec),
        size: kSmallPhone,
        drive: advance(125),
      );
      await rec.stop();
    });

    testWidgets('max early', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder();
      await shot(
        tester,
        '17-max-early',
        screen(rec),
        size: kMaxPhone,
        drive: advance(5),
      );
      await rec.stop();
    });

    testWidgets('max warmed', (WidgetTester tester) async {
      final FakeRunRecorder rec = recorder();
      await shot(
        tester,
        '18-max-warmed',
        screen(rec),
        size: kMaxPhone,
        drive: advance(125),
      );
      await rec.stop();
    });
  });
}

/// A recorder whose save takes as long as [_saving] says, so the finishing
/// state — which lasts a fraction of a second on a phone — can be looked at.
class _SlowStop extends FakeRunRecorder {
  _SlowStop(this._saving, {super.interval, super.now});

  final Future<void> _saving;

  @override
  Future<void> stop() async {
    await _saving;
    await super.stop();
  }
}
