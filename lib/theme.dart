import 'package:flutter/material.dart';

/// The colours of the web and desktop app's default (Midnight) background.
class Palette {
  static const bgPrimary = Color(0xFF151C2B);
  static const bgSecondary = Color(0xFF1E283E);
  static const bgTertiary = Color(0xFF232D46);
  static const border = Color(0xFF2C3A5A);
  static const textPrimary = Color(0xFFF2F3F5);
  static const textMuted = Color(0xFF9AA5BD);
  static const accent = Color(0xFF5865F2);
  static const danger = Color(0xFFED4245);
  static const success = Color(0xFF23A55A);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: Palette.accent,
    surface: Palette.bgSecondary,
    error: Palette.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.bgPrimary,
    canvasColor: Palette.bgPrimary,
    dividerColor: Palette.border,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.bgSecondary,
      foregroundColor: Palette.textPrimary,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.bgTertiary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Palette.accent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    listTileTheme: const ListTileThemeData(iconColor: Palette.textMuted),
  );
}
