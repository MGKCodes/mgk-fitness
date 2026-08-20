import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

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
  });

  final CoachService coach;
  final CoachTranscript? transcript;
  final String? opener;

  /// The share of the screen it opens at. Tall enough that a conversation is a
  /// conversation rather than a peephole, short enough that the surface behind
  /// stays visible — which is what makes this read as *over* Track instead of
  /// as having replaced it.
  static const double _openAt = 0.88;

  static Future<void> show(
    BuildContext context, {
    required CoachService coach,
    CoachTranscript? transcript,
    String? opener,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      // The sheet paints its own photograph and glass, so the default white
      // Material underneath would sit in front of both.
      backgroundColor: Colors.transparent,
      // Above the nav bar rather than inside the body, or the bar draws over
      // the composer.
      useRootNavigator: true,
      isScrollControlled: true,
      // Scrim, not a blackout. Seeing the surface you came from is the
      // difference between a sheet and a screen.
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => FractionallySizedBox(
        heightFactor: _openAt,
        child: CoachSheet(coach: coach, transcript: transcript, opener: opener),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.vertical(
      top: Radius.circular(AppRadius.sheet + 8),
    );
    return ClipRRect(
      borderRadius: radius,
      child: PhotoBackdrop(
        image: 'assets/images/backgrounds/hero_onboarding.webp',
        // Balanced, not grounded. Grounded weights the scrim to the bottom,
        // which is where the conversation actually sits — so it buried the
        // photograph exactly where the glass needed something to refract, and
        // the whole sheet read as flat grey. Balanced keeps the middle open,
        // and the blur is what stops the texture competing with the words.
        scrim: ScrimStrength.balanced,
        // High for a backdrop, because this one is being looked at THROUGH
        // 34px of blur and a tint. At Track's 0.30 the glass had nothing left
        // to work with.
        opacity: 0.62,
        child: GlassSurface(
          borderRadius: radius,
          padding: EdgeInsets.zero,
          // Stronger than a card's. A whole sheet of glass at card settings
          // lets enough of the photograph through to compete with the text,
          // and this one has a conversation to be read on it.
          blurSigma: 34,
          tintOpacity: 0.14,
          child: CoachScreen(
            coach: coach,
            transcript: transcript,
            opener: opener,
          ),
        ),
      ),
    );
  }
}

/// The circle you tap to bring the coach up.
///
/// A single letter, because the mark is permanent and lives over three
/// different screens: a labelled pill at this position competed with whatever
/// primary action the surface underneath already had, and read as a second
/// button rather than as a persistent affordance.
///
/// **The letter is not the label.** `C` means nothing to a screen reader, so
/// the semantics carry the word the visual dropped.
class CoachMark extends StatelessWidget {
  const CoachMark({super.key, required this.hasUnread, required this.onTap});

  final bool hasUnread;
  final VoidCallback onTap;

  static const double diameter = 56;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Coach',
      child: PressScale(
        onTap: onTap,
        child: SizedBox(
          width: diameter,
          height: diameter,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              GlassSurface(
                borderRadius: BorderRadius.circular(diameter),
                padding: EdgeInsets.zero,
                child: const Center(
                  child: Text(
                    'C',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ),
              ),
              if (hasUnread)
                const Positioned(top: 2, right: 2, child: _UnreadDot()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pulses, because the mark is stationary and the dot is small. A note the
/// coach has left is the one thing on this affordance worth noticing.
class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) => Pulse(
    child: Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.bg, width: 2),
      ),
    ),
  );
}
