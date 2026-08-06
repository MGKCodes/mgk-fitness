import 'package:flutter/painting.dart';

/// The suite's greyscale colour tokens.
///
/// Shared across every app so they read as one product (ADR-0009). Originated
/// in Liftio's `constants/Colors.ts`, carried into Runio, and now the single
/// definition both draw from.
abstract final class AppColors {
  /// App background — charcoal, not pure black.
  static const bg = Color(0xFF1A1A1A);

  /// Cards.
  static const surface = Color(0xFF2D2D2D);

  /// Inputs, elevated surfaces, borders.
  static const elevated = Color(0xFF404040);

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9CA3AF);
  static const textTertiary = Color(0xFF6B7280);

  /// Primary control — silver.
  static const primary = Color(0xFFC0C0C0);
  static const onPrimary = Color(0xFF1A1A1A);

  /// Status only — never decorative.
  static const success = Color(0xFF16A34A);
  static const danger = Color(0xFFDC2626);
}
