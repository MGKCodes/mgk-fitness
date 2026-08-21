import 'package:flutter/material.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../planning/domain/coach_planner.dart';
import '../../planning/domain/planned_movement.dart';
import '../../planning/domain/session_from_plan.dart';
import '../domain/session.dart';
import '../domain/session_recorder.dart';
import 'active_session_screen.dart';

/// Starts or resumes a session and puts the active screen on top.
///
/// Separated from the surface so the surface stays a widget that draws things
/// and this holds the one rule worth getting right: **an interrupted session is
/// offered back, never overwritten.**
///
/// The recorder refuses a second concurrent session, so without this a lifter
/// who force-quit mid-workout would tap "Start" and get an exception. What they
/// should get is the session they were already in.
class TrackController {
  const TrackController(this.recorder);

  final SessionRecorder recorder;

  /// Resumes the open session if there is one, otherwise starts a fresh one.
  Future<void> openSession(
    BuildContext context, {
    MassUnit massUnit = MassUnit.kilograms,
    VoidCallback? onDone,
    CoachPlanner? planner,
    List<Session> log = const <Session>[],
  }) async {
    final Session session = await recorder.current() ?? await recorder.start();

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ActiveSessionScreen(
          recorder: recorder,
          session: session,
          massUnit: massUnit,
          onFinished: onDone,
          planner: planner,
          log: log,
        ),
      ),
    );
  }

  /// Starts today's planned session, movements and targets already in.
  ///
  /// **Resuming still wins.** An open session is offered back exactly as it is
  /// for a plain start: filling a plan over the top of one somebody is halfway
  /// through would destroy the sets they had already logged, which is the worst
  /// thing this app could do.
  Future<void> openPlanned(
    BuildContext context,
    String title,
    List<PlannedMovement> movements, {
    MassUnit massUnit = MassUnit.kilograms,
    void Function(Session session)? onStarted,
    VoidCallback? onDone,
    CoachPlanner? planner,
    List<Session> log = const <Session>[],
    void Function(String replaced, PlannedMovement with_)? onSwapped,
  }) async {
    final open = await recorder.current();
    final session =
        open ?? await SessionFromPlan(recorder).start(title, movements);
    if (open == null) onStarted?.call(session);

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ActiveSessionScreen(
          recorder: recorder,
          session: session,
          massUnit: massUnit,
          onFinished: onDone,
          planner: planner,
          log: log,
          onSwapped: onSwapped,
        ),
      ),
    );
  }
}
