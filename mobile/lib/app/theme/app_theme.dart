import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Material 3 light and dark themes following the F&F reference design: blue
/// primary, green secondary, orange accent, dark-navy text, light backgrounds,
/// rounded cards and buttons, Inter type.
///
/// Every control gets a minimum 48dp touch target so the app stays usable.
abstract final class AppTheme {
  static const double radius = 12;
  static const double cardRadius = 16;
  static const double minTouch = 48;
  static const String fontFamily = 'Inter';

  static ThemeData light() => _build(Brightness.light);

  /// Not used by the app (it always runs in the light theme); kept so the
  /// design-system tests can still build it.
  static ThemeData dark() => _build(Brightness.dark);

  static ColorScheme _scheme(Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    );
    if (brightness == Brightness.dark) {
      return base.copyWith(
        primary: const Color(0xFF60A5FA),
        secondary: const Color(0xFF34D399),
        tertiary: const Color(0xFFFBBF24),
      );
    }
    return base.copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primarySoft,
      onPrimaryContainer: AppColors.primaryOnSoft,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.secondarySoft,
      onSecondaryContainer: AppColors.secondaryOnSoft,
      tertiary: AppColors.accent,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.accentSoft,
      onTertiaryContainer: AppColors.accentOnSoft,
      error: AppColors.error,
      onError: Colors.white,
      errorContainer: AppColors.errorSoft,
      onErrorContainer: AppColors.errorOnSoft,
      surface: AppColors.background,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      // Cards (Card uses surfaceContainerLow) are white on the light page.
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: const Color(0xFFF1F5F9),
      surfaceContainerHighest: const Color(0xFFF1F5F9),
      outline: const Color(0xFFCBD5E1),
      outlineVariant: AppColors.border,
    );
  }

  static TextTheme _text(TextTheme base, ColorScheme scheme) {
    TextStyle s(double size, double line, FontWeight weight) => TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          height: line / size,
          fontWeight: weight,
          color: scheme.onSurface,
        );
    return base.copyWith(
      // Heading 1 24/32 bold, Heading 2 20/28 semibold, Heading 3 18/24 semibold
      headlineLarge: s(28, 36, FontWeight.w700),
      headlineMedium: s(24, 32, FontWeight.w700),
      headlineSmall: s(20, 28, FontWeight.w600),
      titleLarge: s(18, 24, FontWeight.w600),
      titleMedium: s(16, 24, FontWeight.w600),
      titleSmall: s(14, 20, FontWeight.w600),
      // Body 16/24 regular, caption 14/20 regular
      bodyLarge: s(16, 24, FontWeight.w400),
      bodyMedium: s(14, 20, FontWeight.w400),
      bodySmall: s(12, 16, FontWeight.w400)
          .copyWith(color: scheme.onSurfaceVariant),
      labelLarge: s(14, 20, FontWeight.w600),
      labelMedium: s(12, 16, FontWeight.w500)
          .copyWith(color: scheme.onSurfaceVariant),
      labelSmall: s(11, 16, FontWeight.w500)
          .copyWith(color: scheme.onSurfaceVariant),
    );
  }

  static ThemeData _build(Brightness brightness) {
    final scheme = _scheme(brightness);
    final isLight = brightness == Brightness.light;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
    );
    final text = _text(base.textTheme, scheme);

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      textTheme: text,
      primaryTextTheme: text,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: shape,
          textStyle: text.titleSmall?.copyWith(fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(minTouch, 52),
          shape: shape,
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.primary, width: 1.5),
          textStyle: text.titleSmall?.copyWith(fontSize: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(minTouch, minTouch),
          shape: shape,
          textStyle: text.titleSmall,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(minTouch, minTouch),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? AppColors.surface : scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: border(scheme.outlineVariant),
        enabledBorder: border(scheme.outlineVariant),
        focusedBorder: border(scheme.primary, 2),
        errorBorder: border(scheme.error),
        focusedErrorBorder: border(scheme.error, 2),
        hintStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: isLight ? AppColors.surface : null,
        selectedColor: scheme.primary,
        labelStyle: text.labelLarge,
        secondaryLabelStyle:
            text.labelLarge?.copyWith(color: scheme.onPrimary),
        checkmarkColor: scheme.onPrimary,
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isLight ? AppColors.surface : null,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: shape,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      listTileTheme: const ListTileThemeData(minVerticalPadding: 8),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }
}
