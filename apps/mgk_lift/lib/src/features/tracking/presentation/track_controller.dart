import 'package:flutter/material.dart';
import 'package:mgk_units/mgk_units.dart';

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
        ),
      ),
    );
  }
}
