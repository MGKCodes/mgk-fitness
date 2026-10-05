import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../domain/coach.dart';
import 'coach_screen.dart';

/// The coach, as a sheet that comes up over whatever you were doing.
///
/// **Not a fourth destination.** Track, Plan and Profile are the app — three
/// full pages, one nav bar. The coach is not a place you navigate to and come
/// back from; it is something you pull up, say a thing to, and drop. Pushing it
/// as a route said the opposite: a back arrow to a screen you had never left,
/// and a nav bar that vanished while you talked.
///
/// ## Why the glass needs the photograph
///
/// [GlassSurface] is explicit that blur over a flat fill is a no-op — the
/// effect is the distortion of texture, so on the charcoal base a glass panel
/// is a plain panel that costs more. That makes the backdrop load-bearing
/// rather than decorative: without a photograph behind it, this sheet is a grey
/// box with a rounded top.
///
/// `hero_onboarding` rather than the gym plate Track uses. The two are on
/// screen together — the sheet rises over Track — and the same image blurred
/// over itself reads as a smear rather than as a pane in front of something.
class CoachSheet extends StatelessWidget {
  const CoachSheet({
    super.key,
    required this.coach,
    this.transcript,
    this.opener,
    this.massUnit = MassUnit.kilograms,
  });

  final CoachService coach;
  final CoachTranscript? transcript;
  final String? opener;

  /// Passed through to the asked-for values, which are offered in the system
  /// the lifter already uses everywhere else.
  final MassUnit massUnit;

  static Future<void> show(
    BuildContext context, {
    required CoachService coach,
    CoachTranscript? transcript,
    String? opener,
  }) => showCoachSheet<void>(
    context,
    builder: (_) =>
        CoachSheet(coach: coach, transcript: transcript, opener: opener),
  );

  /// The suite's coach sheet (`CoachSheetFrame`, 5 October 2026): the glass,
  /// the radius and the 0.88 that were drawn here are shared with Run's
  /// coach now, and the frame rises above the keyboard, which this sheet did
  /// not.
  @override
  Widget build(BuildContext context) => CoachSheetFrame(
    photo: 'assets/images/backgrounds/hero_onboarding.webp',
    child: CoachScreen(
      coach: coach,
      transcript: transcript,
      opener: opener,
      massUnit: massUnit,
    ),
  );
}
