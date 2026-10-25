import 'package:flutter/material.dart';

/// The F&F design system palette (from the UI reference).
abstract final class AppColors {
  /// Primary actions: blue.
  static const Color primary = Color(0xFF2563EB);

  /// Secondary / positive accents: green.
  static const Color secondary = Color(0xFF10B981);

  /// Warm accent: orange (pending, highlights).
  static const Color accent = Color(0xFFF59E0B);

  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF22C55E);

  /// Dark navy body text.
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);

  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);

  // Soft tints used behind badges and icons.
  static const Color primarySoft = Color(0xFFDBEAFE);
  static const Color primaryOnSoft = Color(0xFF1D4ED8);
  static const Color secondarySoft = Color(0xFFD1FAE5);
  static const Color secondaryOnSoft = Color(0xFF047857);
  static const Color accentSoft = Color(0xFFFEF3C7);
  static const Color accentOnSoft = Color(0xFFB45309);
  static const Color errorSoft = Color(0xFFFEE2E2);
  static const Color errorOnSoft = Color(0xFFB91C1C);

  /// Kept for code that still refers to the seed.
  static const Color seed = primary;
}
