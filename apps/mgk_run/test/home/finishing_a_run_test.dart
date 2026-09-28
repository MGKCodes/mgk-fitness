import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/history/data/drift_run_repository.dart';
import 'package:mgk_run/src/features/history/data/run_editor.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/data/location_source.dart';
import 'package:mgk_run/src/features/recording/data/recording_run_recorder.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';
import 'package:mgk_run/src/features/recording/presentation/run_start_screen.dart';
import 'package:mgk_run/src/features/recording/presentation/run_summary_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// A chat backend that records what it was asked, so the hand-off can be
/// asserted on the question rather than on the reply.
class _RecordingChat implements CoachChatClient {
  final List<String> asked = <String>[];

  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async {
    asked.add(message);
    return const ChatTurn(reply: 'Noted.');
  }
}

class _FakeLocationSource implements LocationSource {
  final StreamController<RunPoint> _controller =
      StreamController<RunPoint>.broadcast();

  @override
  Stream<RunPoint> get fixes => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  void emit(RunPoint point) => _controller.add(point);

  Future<void> dispose() => _controller.close();
}

/// **What happens after the finish line.**
///
/// The first field test recorded 10 km, watched it for an hour, pressed Finish
/// — and the screen simply vanished. `onFinish` was
/// `Navigator.of(routeContext).pop()`, so an hour of effort ended with the
/// display going away and nothing to look at.
///
/// This drives the whole path with nothing stubbed in the middle: a real Drift
/// database, the real recorder writing to it, the log read back out of it, and
/// the summary opened from what was actually stored. That last part is
/// deliberate rather than convenient — reading the run back is the cheap
/// end-to-end check ADR-0023 says the log stopped being, and if the write path
/// breaks, this screen is the first thing to say so.
void main() {
  late AppDatabase db;
  late _FakeLocationSource source;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    source = _FakeLocationSource();
  });

  tearDown(() async {
    await source.dispose();
    await db.close();
  });

  /// The shell wired the way `main.dart` wires it: the log read from Drift, the
  /// editor over the same database, and no backup behind either.
  Widget shell({CoachChatClient? chat}) => MaterialApp(
    theme: AppTheme.dark,
    home: HomeShell(
      // Pinned, because one of these asks the coach about the run on screen,
      // and the coach is the paid half (ADR-0030). Unpinned it was `free`, and
      // passed -- which is what an ungated `_askCoach` looks like from a test.
      access: CoachAccess.subscribed,
      auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
      historySource: DriftRunRepository(db).fetchRuns,
      runEditor: RunEditor(db: db),
      recorderFactory: () => RecordingRunRecorder(source: source, db: db),
      chatClient: chat,
    ),
  );

  /// Frames, and real time between them.
  ///
  /// Frames rather than `pumpAndSettle` because the in-run screen carries a
  /// [Pulse] on its status dot while recording, which never settles — the trap
  /// the other recording tests document. And [WidgetTester.runAsync] between
  /// them because there is a real database on the path: `pump` turns Flutter's
  /// fake clock, which is not the clock sqlite's futures complete on, so a
  /// widget test that only pumps waits forever for a write that finished
  /// immediately.
  Future<void> settle(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> recordAndFinish(
    WidgetTester tester, {
    CoachChatClient? chat,
  }) async {
    await tester.pumpWidget(shell(chat: chat));
    await settle(tester);

    await tester.tap(find.text('Record a run'));
    await settle(tester);

    // **The clock no longer starts on that tap.** `RunStartScreen` comes first
    // and the recorder is not built until its count-in ends, so the first
    // seconds of a run are no longer spent putting a phone away. Four pumps of
    // a second each: three for the count, one for the tick that fires `onStart`.
    expect(find.byType(RunStartScreen), findsOneWidget);
    await tester.tap(find.text('Start'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await settle(tester);
    expect(find.byType(RecordingScreen), findsOneWidget);

    final start = DateTime.now();
    for (var i = 0; i <= 12; i++) {
      source.emit(
        RunPoint(
          latitude: 0,
          longitude: i * 0.001,
          accuracyMeters: 5,
          timestamp: start.add(Duration(seconds: i * 5)),
        ),
      );
    }
    await settle(tester);

    // Two acts, which is the point of the control model: a run cannot end from
    // the running state at all.
    await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
    await settle(tester, 3);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Finish'));
    await settle(tester, 10);
  }

  testWidgets('finishing lands on the run just recorded', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await recordAndFinish(tester);

    expect(find.byType(RecordingScreen), findsNothing);
    expect(find.byType(RunSummaryScreen), findsOneWidget);
    expect(find.text('Run complete'), findsOneWidget);
  });

  testWidgets('with the route and the splits that were just written', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await recordAndFinish(tester);

    final screen = tester.widget<RunSummaryScreen>(
      find.byType(RunSummaryScreen),
    );
    expect(screen.justFinished, isTrue);
    expect(screen.summary.id, isNotNull);
    expect(
      screen.summary.hasRoute,
      isTrue,
      reason: 'the trace came back out of the database it was written to',
    );
    expect(
      screen.summary.splits,
      isNotEmpty,
      reason: 'splits are written on stop now, not only by a restore',
    );
    // And the same run is in the log behind it.
    expect(await DriftRunRepository(db).fetchRuns(), hasLength(1));
  });

  testWidgets('and Done closes it, leaving the runner on Home', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await recordAndFinish(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await settle(tester, 8);

    expect(find.byType(RunSummaryScreen), findsNothing);
    // "Record **another** run", because Home has noticed the run that just
    // finished. This read "Record a run" until Home's today tile learned to
    // answer off the log for a runner with no plan — the offer of a second run
    // is the tile agreeing with the log behind it.
    expect(find.text('Record another run'), findsWidgets);
  });

  testWidgets('the coach can be asked about the run on screen', (tester) async {
    // `RunNote` says one true thing and then stops, by design — a coach who
    // says five things about one run is not coaching. This is the way past that
    // ceiling, at the moment the runner cares most about the answer, and it
    // lands in the *one* conversation rather than standing up a second one.
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final chat = _RecordingChat();
    await recordAndFinish(tester, chat: chat);

    await tester.tap(find.text('Ask your coach about this run'));
    await settle(tester, 10);

    expect(chat.asked, hasLength(1));
    expect(chat.asked.single, contains('just finished'));
    expect(
      chat.asked.single,
      contains('km'),
      reason: 'the question carries the run’s own numbers',
    );
  });

  testWidgets('discarding a run leads nowhere, as it should', (tester) async {
    // The case the completion screen must not fire on. A runner who backed out
    // — or whose permission was refused, so nothing was ever recorded — must
    // not be handed the *previous* run's summary as though they had just done
    // it. `runFinishedSince` answers with nothing, and nothing opens.
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(shell());
    await settle(tester);
    await tester.tap(find.text('Record a run'));
    await settle(tester);

    await tester.tap(find.text('Start'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await settle(tester);

    await tester.tap(find.byTooltip('Cancel run'));
    await settle(tester, 3);
    await tester.tap(find.text('Discard'));
    await settle(tester, 10);

    expect(find.byType(RecordingScreen), findsNothing);
    expect(find.byType(RunSummaryScreen), findsNothing);
  });
}
