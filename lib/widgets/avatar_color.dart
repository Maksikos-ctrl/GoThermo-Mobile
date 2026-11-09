import 'package:flutter/material.dart';

const _colors = <Color>[
  Color(0xFF5865F2),
  Color(0xFFED4245),
  Color(0xFF2DA160),
  Color(0xFFC79A12),
  Color(0xFFD6409F),
  Color(0xFFE8603C),
  Color(0xFF4F7FD9),
  Color(0xFF9B59B6),
];

int _i32(int v) => v.toSigned(32);

/// The same colour for the same name as on the web and desktop apps. It copies
/// that code's arithmetic exactly (32-bit shift, UTF-16 units).
Color avatarColor(String username) {
  var hash = 0;
  for (final c in username.codeUnits) {
    hash = c + (_i32(_i32(hash) << 5) - hash);
  }
  return _colors[hash.abs() % _colors.length];
}
