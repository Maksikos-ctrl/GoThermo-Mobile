import 'package:flutter/foundation.dart';

import 'session_store.dart';

/// What the person picked on the Appearance screen. Saved on the phone.
class ThemeSettings extends ChangeNotifier {
  ThemeSettings(this._store);

  final SessionStore _store;

  /// `system` follows the phone's light / dark setting; the other ids are the
  /// names in `colorSets` (midnight, graphite, amoled, light).
  static const systemMode = 'system';
  static const modes = ['system', 'midnight', 'graphite', 'amoled', 'light'];
  static const accentCount = 6;
  static const textScales = [0.9, 1.0, 1.15, 1.3];

  String mode = systemMode;
  int accent = 0;
  double textScale = 1.0;

  Future<void> load() async {
    final m = await _store.readPref('theme.mode');
    final a = int.tryParse(await _store.readPref('theme.accent') ?? '');
    final t = double.tryParse(await _store.readPref('theme.textScale') ?? '');
    if (m != null && modes.contains(m)) mode = m;
    if (a != null && a >= 0 && a < accentCount) accent = a;
    if (t != null && textScales.contains(t)) textScale = t;
    notifyListeners();
  }

  Future<void> setMode(String value) async {
    if (!modes.contains(value) || value == mode) return;
    mode = value;
    notifyListeners();
    await _store.writePref('theme.mode', value);
  }

  Future<void> setAccent(int value) async {
    if (value < 0 || value >= accentCount || value == accent) return;
    accent = value;
    notifyListeners();
    await _store.writePref('theme.accent', '$value');
  }

  Future<void> setTextScale(double value) async {
    if (!textScales.contains(value) || value == textScale) return;
    textScale = value;
    notifyListeners();
    await _store.writePref('theme.textScale', '$value');
  }
}
