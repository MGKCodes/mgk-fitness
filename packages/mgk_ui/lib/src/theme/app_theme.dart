import 'package:flutter/material.dart';

import '../motion/page_transitions.dart';
import 'app_colors.dart';

/// The suite theme: pure greyscale, silver primary. Dark only.
abstract final class AppTheme {
  static const _scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    secondary: AppColors.primary,
    onSecondary: AppColors.onPrimary,
    surface: AppColors.bg,
    onSurface: AppColors.textPrimary,
    error: AppColors.danger,
    onError: AppColors.textPrimary,
  );

  /// The bundled typeface, declared in this package's pubspec.
  ///
  /// Set on the theme rather than per widget so nothing can quietly fall back to
  /// the platform default: Inter's metrics differ from SF and Roboto, so a
  /// screen laid out against the wrong face would need reworking.
  ///
  /// The `packages/mgk_ui/` prefix is how Flutter addresses a font a package
  /// supplies. Use this constant rather than writing `'Inter'`, which would
  /// silently resolve to the platform default in a consuming app.
  static const String fontFamily = 'packages/mgk_ui/Inter';

  static ThemeData get dark {
    final base = ThemeData(colorScheme: _scheme, fontFamily: fontFamily);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      // One transition for every platform: Cupertino's horizontal slide is a
      // different motion language from the rest of the suite (see AppMotion).
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.iOS: MgkPageTransitions(),
          TargetPlatform.android: MgkPageTransitions(),
          TargetPlatform.macOS: MgkPageTransitions(),
        },
      ),
      textTheme: base.textTheme.apply(
        fontFamily: fontFamily,
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textTertiary),
        enabledBorder: _inputBorder(AppColors.elevated),
        border: _inputBorder(AppColors.elevated),
        focusedBorder: _inputBorder(AppColors.primary),
        errorBorder: _inputBorder(AppColors.danger),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.elevated,
          disabledForegroundColor: AppColors.textTertiary,
          // Height only. `Size.fromHeight` is `Size(double.infinity, 52)`,
          // which forced **every** FilledButton to full width — so one could
          // only ever be the page's primary action, and an inline or compact
          // use threw "BoxConstraints forces an infinite width" at layout.
          //
          // Full width belongs to [PrimaryButton], which already wraps itself
          // in a `SizedBox(width: double.infinity)`; putting it in the theme as
          // well made the constraint global for no gain.
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          // The family is spelled out because a ButtonStyle's textStyle is
          // handed to Material as the label's *whole* style rather than merged
          // over the text theme — omit it and `fontFamily` resolves to null,
          // so every button label silently renders in SF Pro or Roboto while
          // the rest of the screen is Inter.
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      // Matches the filled button's metrics exactly, so the two can occupy the
      // same slot without the layout shifting — see principle 2 in
      // docs/design.md. Its absence is why Run's delete screen re-specified
      // height, shape and text style by hand.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          disabledForegroundColor: AppColors.textTertiary,
          side: const BorderSide(color: AppColors.elevated),
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          // The family is spelled out because a ButtonStyle's textStyle is
          // handed to Material as the label's *whole* style rather than merged
          // over the text theme — omit it and `fontFamily` resolves to null,
          // so every button label silently renders in SF Pro or Roboto while
          // the rest of the screen is Inter.
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
      ),
      // **A confirmation on the suite's own surface, not a light slab.** Left
      // unset, Material paints a snackbar in the scheme's `inverseSurface`,
      // which this scheme never names and so defaults to `onSurface`: a white
      // bar with dark text across an app that is dark everywhere else. Run's
      // "Withdrawn" confirmation is where a screen board caught it (T15); every
      // snackbar in both apps was the same. Surface and primary text, as the
      // dialogs that confirm things already are.
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surface,
        contentTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: AppColors.textPrimary,
          fontSize: 14,
          height: 1.4,
        ),
        actionTextColor: AppColors.primary,
        closeIconColor: AppColors.textSecondary,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: color),
  );
}
