import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/state/session_store.dart';
import 'package:gothermo_mobile/state/theme_settings.dart';

void main() {
  group('theme settings', () {
    test('start as "same as the phone", first accent, normal text', () async {
      final s = ThemeSettings(MemorySessionStore());
      await s.load();
      expect(s.mode, 'system');
      expect(s.accent, 0);
      expect(s.textScale, 1.0);
    });

    test('choices are saved and come back', () async {
      final store = MemorySessionStore();
      final a = ThemeSettings(store);
      await a.setMode('amoled');
      await a.setAccent(3);
      await a.setTextScale(1.15);

      final b = ThemeSettings(store);
      await b.load();
      expect(b.mode, 'amoled');
      expect(b.accent, 3);
      expect(b.textScale, 1.15);
    });

    test('nonsense values are ignored', () async {
      final store = MemorySessionStore();
      store.prefs['theme.mode'] = 'neon';
      store.prefs['theme.accent'] = '99';
      store.prefs['theme.textScale'] = '7';
      final s = ThemeSettings(store);
      await s.load();
      expect(s.mode, 'system');
      expect(s.accent, 0);
      expect(s.textScale, 1.0);

      await s.setMode('neon');
      await s.setAccent(-1);
      await s.setTextScale(2);
      expect(s.mode, 'system');
      expect(store.prefs.containsKey('theme.mode') && store.prefs['theme.mode'] == 'neon', isTrue); // untouched seed
    });

    test('listeners hear about a change once', () async {
      final s = ThemeSettings(MemorySessionStore());
      var n = 0;
      s.addListener(() => n++);
      await s.setMode('light');
      await s.setMode('light');
      expect(n, 1);
    });
  });
}
