import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'avatar_color.dart';

/// A person's picture (a `data:` URL from the server) or their coloured initial.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.username, this.picture, this.size = 40});

  final String username;
  final String? picture;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bytes = _decode(picture);
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: bytes != null
            ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
            : ColoredBox(
                color: avatarColor(username),
                child: Center(
                  child: Text(
                    username.isEmpty ? '?' : username.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: size * 0.42,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  static Uint8List? _decode(String? dataUrl) {
    if (dataUrl == null || !dataUrl.startsWith('data:image/')) return null;
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(dataUrl.substring(comma + 1));
    } on FormatException {
      return null;
    }
  }
}
