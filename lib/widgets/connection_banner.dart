import 'package:flutter/material.dart';

import '../theme.dart';

/// A thin strip that slides in while the live connection is down.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: visible
          ? Container(
              key: const Key('offline-banner'),
              width: double.infinity,
              color: Palette.warning.withAlpha(40),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Reconnecting...', style: TextStyle(fontSize: 12.5)),
                ],
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}
