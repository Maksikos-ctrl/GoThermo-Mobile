import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/widgets/avatar_color.dart';

// The expected colours were produced by running the web app's avatarColor.ts
// on these names, so a person has the same colour on every device.
void main() {
  const expected = {
    'alice': Color(0xFF5865F2),
    'bob': Color(0xFFE8603C),
    'maksikos973-2': Color(0xFF5865F2),
    'irinamartus': Color(0xFF9B59B6),
    'a very long username with many characters to overflow int32 quickly': Color(0xFF9B59B6),
    'Ярослав': Color(0xFFED4245),
  };

  expected.forEach((name, color) {
    test('matches the web colour for "$name"', () {
      expect(avatarColor(name), color);
    });
  });

  test('works for empty and emoji names', () {
    expect(avatarColor(''), isA<Color>());
    expect(avatarColor('😀'), isA<Color>());
  });
}
