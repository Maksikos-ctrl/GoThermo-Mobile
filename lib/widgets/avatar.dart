import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'avatar_color.dart';

final Map<String, Uint8List> _decoded = {};

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
    final cached = _decoded[dataUrl];
    if (cached != null) return cached;
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;
    try {
      final bytes = base64Decode(dataUrl.substring(comma + 1));
      if (_decoded.length > 200) _decoded.clear();
      _decoded[dataUrl] = bytes;
      return bytes;
    } on FormatException {
      return null;
    }
  }
}

Color statusColor(String status) {
  switch (status) {
    case 'online':
      return Palette.success;
    case 'away':
      return Palette.warning;
    case 'dnd':
      return Palette.danger;
    default:
      return Palette.offline;
  }
}

/// The little coloured dot for online / away / offline.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.status, this.size = 12, this.ring});

  final String status;
  final double size;

  /// The colour around the dot; the page background when null.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: statusColor(status),
        shape: BoxShape.circle,
        border: Border.all(color: ring ?? Palette.bgPrimary, width: size * 0.2),
      ),
    );
  }
}

/// An [Avatar] with the person's presence dot in the corner.
class PresenceAvatar extends StatelessWidget {
  const PresenceAvatar({
    super.key,
    required this.username,
    this.picture,
    this.status,
    this.size = 40,
    this.ring,
  });

  final String username;
  final String? picture;
  final String? status;
  final double size;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Avatar(username: username, picture: picture, size: size),
          if (status != null)
            Positioned(
              right: -2,
              bottom: -2,
              child: StatusDot(status: status!, size: size * 0.32, ring: ring),
            ),
        ],
      ),
    );
  }
}
