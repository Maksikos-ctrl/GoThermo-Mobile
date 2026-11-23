import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One full set of colours.
class AppColors {
  const AppColors({
    required this.id,
    required this.name,
    required this.brightness,
    required this.bgPrimary,
    required this.bgSecondary,
    required this.bgTertiary,
    required this.border,
    required this.textPrimary,
    required this.textMuted,
    this.danger = const Color(0xFFED4245),
    this.success = const Color(0xFF23A55A),
    this.warning = const Color(0xFFF0B232),
    this.offline = const Color(0xFF80848E),
  });

  final String id;
  final String name;
  final Brightness brightness;
  final Color bgPrimary;
  final Color bgSecondary;
  final Color bgTertiary;
  final Color border;
  final Color textPrimary;
  final Color textMuted;
  final Color danger;
  final Color success;
  final Color warning;
  final Color offline;
}

const midnightColors = AppColors(
  id: 'midnight',
  name: 'Midnight',
  brightness: Brightness.dark,
  bgPrimary: Color(0xFF151C2B),
  bgSecondary: Color(0xFF1E283E),
  bgTertiary: Color(0xFF232D46),
  border: Color(0xFF2C3A5A),
  textPrimary: Color(0xFFF2F3F5),
  textMuted: Color(0xFF9AA5BD),
);

const graphiteColors = AppColors(
  id: 'graphite',
  name: 'Graphite',
  brightness: Brightness.dark,
  bgPrimary: Color(0xFF1E1F22),
  bgSecondary: Color(0xFF2B2D31),
  bgTertiary: Color(0xFF313338),
  border: Color(0xFF3F4147),
  textPrimary: Color(0xFFF2F3F5),
  textMuted: Color(0xFFA3A6AA),
);

const amoledColors = AppColors(
  id: 'amoled',
  name: 'AMOLED black',
  brightness: Brightness.dark,
  bgPrimary: Color(0xFF000000),
  bgSecondary: Color(0xFF0C0C10),
  bgTertiary: Color(0xFF16161C),
  border: Color(0xFF26262E),
  textPrimary: Color(0xFFF2F3F5),
  textMuted: Color(0xFF9A9CA6),
);

const lightColors = AppColors(
  id: 'light',
  name: 'Light',
  brightness: Brightness.light,
  bgPrimary: Color(0xFFF2F3F5),
  bgSecondary: Color(0xFFFFFFFF),
  bgTertiary: Color(0xFFE8EAEE),
  border: Color(0xFFD4D7DD),
  textPrimary: Color(0xFF1F2329),
  textMuted: Color(0xFF5C6370),
  danger: Color(0xFFD92D30),
  success: Color(0xFF1B8A47),
  warning: Color(0xFFB97800),
  offline: Color(0xFF8A8F98),
);

/// Every choice the person can pick (besides "same as the phone").
const colorSets = <AppColors>[midnightColors, graphiteColors, amoledColors, lightColors];

/// The accent colours on offer; the first is the web app's blue.
const accentChoices = <Color>[
  Color(0xFF5865F2),
  Color(0xFF14B8A6),
  Color(0xFF23A55A),
  Color(0xFFF97316),
  Color(0xFFEC4899),
  Color(0xFF8B5CF6),
];

/// The colours for a saved choice. [system] decides what "same as the phone"
/// means: Midnight when the phone is dark, Light when it is light.
AppColors resolveColors(String mode, Brightness system) {
  if (mode == 'system') return system == Brightness.dark ? midnightColors : lightColors;
  for (final c in colorSets) {
    if (c.id == mode) return c;
  }
  return midnightColors;
}

/// The colours in use right now. The theme screen changes them with [apply];
/// the app then rebuilds, so these are plain getters, not constants.
class Palette {
  static AppColors _c = midnightColors;
  static Color _accent = accentChoices.first;

  static void apply(AppColors colors, Color accent) {
    _c = colors;
    _accent = accent;
  }

  static Brightness get brightness => _c.brightness;
  static Color get bgPrimary => _c.bgPrimary;
  static Color get bgSecondary => _c.bgSecondary;
  static Color get bgTertiary => _c.bgTertiary;
  static Color get border => _c.border;
  static Color get textPrimary => _c.textPrimary;
  static Color get textMuted => _c.textMuted;
  static Color get accent => _accent;
  static Color get danger => _c.danger;
  static Color get success => _c.success;
  static Color get warning => _c.warning;
  static Color get offline => _c.offline;
}

ThemeData buildTheme() {
  final dark = Palette.brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.accent,
    brightness: Palette.brightness,
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
    appBarTheme: AppBarTheme(
      backgroundColor: Palette.bgSecondary,
      foregroundColor: Palette.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Palette.bgSecondary,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.bgTertiary,
      contentTextStyle: TextStyle(color: Palette.textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.bgTertiary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Palette.accent, width: 1.5),
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
    listTileTheme: ListTileThemeData(iconColor: Palette.textMuted),
  );
}
