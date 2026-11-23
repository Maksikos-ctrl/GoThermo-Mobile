import 'package:flutter/material.dart';

import '../state/theme_settings.dart';
import '../theme.dart';
import '../widgets/avatar.dart';

/// Theme, accent colour and text size.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key, required this.settings});

  final ThemeSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Appearance')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              const _Preview(),
              const SizedBox(height: 20),
              _Heading('Theme'),
              for (final mode in ThemeSettings.modes)
                _ThemeTile(
                  mode: mode,
                  selected: settings.mode == mode,
                  onTap: () => settings.setMode(mode),
                ),
              const SizedBox(height: 20),
              _Heading('Accent colour'),
              Wrap(
                spacing: 14,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < accentChoices.length; i++)
                    GestureDetector(
                      key: Key('accent-$i'),
                      onTap: () => settings.setAccent(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: accentChoices[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: settings.accent == i ? Palette.textPrimary : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: settings.accent == i ? 1 : 0,
                          child: const Icon(Icons.check, color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              _Heading('Text size'),
              Row(
                children: [
                  for (final scale in ThemeSettings.textScales)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ChoiceChip(
                          key: Key('scale-$scale'),
                          showCheckmark: false,
                          label: SizedBox(
                            width: double.infinity,
                            child: Text(
                              _scaleLabel(scale),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          selected: settings.textScale == scale,
                          onSelected: (_) => settings.setTextScale(scale),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static String _scaleLabel(double s) {
    if (s < 1) return 'Small';
    if (s == 1) return 'Normal';
    if (s < 1.2) return 'Large';
    return 'Huge';
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(color: Palette.textMuted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8),
      ),
    );
  }
}

/// A small chat sample drawn with the colours in use.
class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.bgPrimary,
        border: Border.all(color: Palette.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Avatar(username: 'Ann', size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ann', style: TextStyle(fontWeight: FontWeight.w700, color: Palette.textPrimary)),
                    Text('Lunch at 1? The new place is open.', style: TextStyle(color: Palette.textPrimary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: Palette.accent, borderRadius: BorderRadius.circular(16)),
              child: const Text('Sounds good!', style: TextStyle(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 10),
          Text('Online now', style: TextStyle(color: Palette.success, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.mode, required this.selected, required this.onTap});

  final String mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSystem = mode == ThemeSettings.systemMode;
    final colors = isSystem ? null : colorSets.firstWhere((c) => c.id == mode);
    final title = isSystem ? 'Same as the phone' : colors!.name;
    final subtitle = isSystem ? 'Light by day, Midnight at night' : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Palette.bgSecondary,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: Key('theme-$mode'),
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? Palette.accent : Palette.border, width: selected ? 2 : 1),
            ),
            child: Row(
              children: [
                _Swatch(colors: colors),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 16, color: Palette.textPrimary)),
                      if (subtitle != null)
                        Text(subtitle, style: TextStyle(fontSize: 12.5, color: Palette.textMuted)),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: selected ? 1 : 0,
                  child: Icon(Icons.check_circle, color: Palette.accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Three stripes showing a theme's colours; half and half for "system".
class _Swatch extends StatelessWidget {
  const _Swatch({required this.colors});

  final AppColors? colors;

  @override
  Widget build(BuildContext context) {
    final left = colors ?? lightColors;
    final right = colors ?? midnightColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 56,
        height: 40,
        child: Row(
          children: [
            Expanded(child: ColoredBox(color: left.bgPrimary, child: Center(child: _bar(left.bgTertiary)))),
            Expanded(child: ColoredBox(color: right.bgPrimary, child: Center(child: _bar(right.bgTertiary)))),
          ],
        ),
      ),
    );
  }

  Widget _bar(Color c) => Container(
        width: 18,
        height: 8,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
      );
}
