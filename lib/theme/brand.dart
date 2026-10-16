import 'package:flutter/material.dart';

// the accent is the steel blue of the raccoon's hoodie, on neutrals tinted toward it
class Brand {
  static const surface = Color(0xFF070C10);
  static const raised = Color(0xFF11171C);
  static const raised2 = Color(0xFF1C2228);
  static const line = Color(0xFF2D343A);
  static const ink = Color(0xFFE7ECF0);
  static const muted = Color(0xFF98A0A5);
  static const faint = Color(0xFF747B81);
  static const accent = Color(0xFF62B5E4);
  static const accentInk = Color(0xFF031826);
  static const success = Color(0xFF62C689);
  static const error = Color(0xFFF75C61);

  // 4pt scale
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 24.0;
  static const s6 = 32.0;
  static const s7 = 48.0;

  static ThemeData theme() {
    const scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: accentInk,
      secondary: accent,
      onSecondary: accentInk,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: muted,
      surfaceContainerLowest: surface,
      surfaceContainerLow: raised,
      surfaceContainer: raised,
      surfaceContainerHigh: raised2,
      surfaceContainerHighest: raised2,
      outline: line,
      outlineVariant: line,
      error: error,
      onError: Color(0xFF2A0709),
    );

    // five steps, each at least 1.25 apart: 12, 15, 19, 24, 30
    final karla = ThemeData.dark().textTheme.apply(fontFamily: 'Karla', bodyColor: ink, displayColor: ink);
    final text = karla.copyWith(
      headlineMedium: karla.headlineMedium?.copyWith(fontSize: 30, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -0.3),
      titleLarge: karla.titleLarge?.copyWith(fontSize: 24, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.2),
      titleMedium: karla.titleMedium?.copyWith(fontSize: 19, fontWeight: FontWeight.w700, height: 1.25),
      bodyLarge: karla.bodyLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w500, height: 1.5),
      bodyMedium: karla.bodyMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w400, height: 1.55),
      bodySmall: karla.bodySmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w500, height: 1.5, color: muted),
      labelLarge: karla.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w700, height: 1.2),
      labelMedium: karla.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: 0.4),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      canvasColor: surface,
      textTheme: text,
      splashFactory: InkRipple.splashFactory,
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleMedium,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        indicatorColor: raised2,
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? accent : muted)),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelMedium?.copyWith(color: s.contains(WidgetState.selected) ? ink : muted),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: raised,
        indicatorColor: raised2,
        selectedIconTheme: const IconThemeData(color: accent),
        unselectedIconTheme: const IconThemeData(color: muted),
        selectedLabelTextStyle: text.labelMedium?.copyWith(color: ink),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(color: muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: accentInk,
          disabledBackgroundColor: raised2,
          disabledForegroundColor: faint,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: s5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: line),
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: s5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: text.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        hintStyle: text.bodyMedium?.copyWith(color: faint),
        labelStyle: text.bodyMedium?.copyWith(color: muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: s4, vertical: s3),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: accent, width: 2)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: raised2,
        side: const BorderSide(color: line),
        labelStyle: text.labelMedium?.copyWith(color: ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        showCheckmark: false,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: raised2,
        contentTextStyle: text.bodyMedium,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: line)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent, linearTrackColor: raised2),
      listTileTheme: const ListTileThemeData(iconColor: muted, textColor: ink),
    );
  }
}
