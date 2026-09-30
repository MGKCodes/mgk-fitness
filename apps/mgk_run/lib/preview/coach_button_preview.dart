import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_note.dart';

/// The coach mark, at real size over the real backdrop.
///
/// A swatch on a flat page would prove nothing: the whole question is how glass
/// behaves against the signature photography, and glass over a flat fill is a
/// no-op. Everything here sits on the same backdrop the Plan tab uses.
final Map<String, WidgetBuilder> coachButtonPreviewScreens =
    <String, WidgetBuilder>{
      'coach-mark': (_) => const _MarkSheet(),
      // The reveal, slowed right down. At its real speed every screenshot lands
      // after it has finished, so the open state was being shipped unlooked at.
      'coach-reveal': (_) => const _RevealSheet(),
    };

class _MarkSheet extends StatelessWidget {
  const _MarkSheet();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('The coach mark')),
      body: PhotoBackdrop(
        image: 'assets/images/backgrounds/in-run.jpg',
        scrim: ScrimStrength.grounded,
        opacity: 0.34,
        alignment: Alignment.topCenter,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              220,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            children: const <Widget>[
              _Row(
                label: 'C · the mark',
                note:
                    'The name and the mark are one thing. Card radius, so it '
                    'is every other surface in the app, floating.',
                child: CoachButton(),
              ),
              _Row(
                label: 'C · unread',
                note: 'A dot, not a count. The coach is not a queue.',
                child: CoachButton(hasUnread: true),
              ),
              _Row(
                label: 'C · circle',
                note:
                    'The Material default, for contrast. A circle bottom '
                    "right is somebody else's app.",
                child: _CircleMark(),
              ),
              _Row(
                label: 'Sparkle',
                note:
                    'What it would look like if we kept the AI badge. On '
                    'every AI feature shipped in three years.',
                child: _SparkleMark(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bar open, over the backdrop it will actually sit on.
class _RevealSheet extends StatelessWidget {
  const _RevealSheet();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('The coach speaks')),
    body: PhotoBackdrop(
      image: 'assets/images/backgrounds/in-run.jpg',
      scrim: ScrimStrength.grounded,
      opacity: 0.34,
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: AppSpacing.lg,
              child: const CoachReveal(
                note: CoachNote(
                  headline: 'Longest one yet.',
                  detail:
                      'You went further than you ever have. Recover '
                      'properly.',
                  kind: CoachNoteKind.record,
                ),
                duration: Duration(seconds: 40),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.note, required this.child});

  final String label;
  final String note;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xl),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(width: 104, child: Center(child: child)),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionLabel(label),
              const SizedBox(height: AppSpacing.xs),
              Text(
                note,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CircleMark extends StatelessWidget {
  const _CircleMark();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52,
    height: 52,
    child: GlassSurface(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(26),
      blurSigma: 30,
      tintOpacity: 0.16,
      luminance: 1.22,
      child: const Center(
        child: Text(
          'C',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1,
            letterSpacing: 1,
          ),
        ),
      ),
    ),
  );
}

class _SparkleMark extends StatelessWidget {
  const _SparkleMark();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52,
    height: 52,
    child: GlassSurface(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(AppRadius.card),
      blurSigma: 30,
      tintOpacity: 0.16,
      luminance: 1.22,
      child: const Center(
        child: Icon(Icons.auto_awesome, size: 22, color: AppColors.textPrimary),
      ),
    ),
  );
}
