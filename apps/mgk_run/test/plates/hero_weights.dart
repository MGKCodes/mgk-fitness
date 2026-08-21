import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

import 'plate.dart';

/// The hero numeral at every weight the package actually ships.
///
/// `w200` is deliberately absent. The package ships Inter at 100/300/400/500/
/// 600/700/800/900 — there is no ExtraLight — so asking for `w200` resolved to
/// Thin, and the old plate's second row was the first row with different
/// tracking. A plate that offers a weight which does not exist is a plate that
/// lies about what was chosen.
void main() {
  testWidgets('hero weights', (WidgetTester tester) async {
    const List<(String, FontWeight, double)> rows =
        <(String, FontWeight, double)>[
          ('w100 Thin  ·  tracking -2  (was)', FontWeight.w100, -2),
          ('w100 Thin  ·  -1  (what w200 really drew)', FontWeight.w100, -1),
          ('w300 Light  ·  -1  (now)', FontWeight.w300, -1),
          ('w300 Light  ·  0', FontWeight.w300, 0),
          ('w400 Regular  ·  0', FontWeight.w400, 0),
        ];

    await plate(
      tester,
      'hero_weights',
      Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: rows.length,
            separatorBuilder: (_, _) =>
                const Divider(height: AppSpacing.xl, color: AppColors.elevated),
            itemBuilder: (BuildContext context, int i) {
              final (String label, FontWeight weight, double tracking) =
                  rows[i];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SectionLabel(label, emphasis: LabelEmphasis.stat),
                  const SizedBox(height: AppSpacing.sm),
                  // 0.45 on purpose: a decimal with a zero in front of it is
                  // the case that breaks, and it is what a run reads for its
                  // first half-kilometre.
                  HeroNumeral(
                    label: 'DISTANCE',
                    value: 0.45,
                    unit: 'km',
                    size: 96,
                    weight: weight,
                    letterSpacing: tracking,
                    animate: false,
                  ),
                ],
              );
            },
          ),
        ),
      ),
      size: const Size(393, 1500),
    );
  });
}
