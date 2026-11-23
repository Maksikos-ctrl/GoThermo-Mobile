import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import '../theme.dart';
import '../widgets/motion.dart';

/// Admin accounts are managed on the web or desktop app; this phone app is
/// for chatting, so it just says so.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GoThermo')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: PopIn(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 56, color: Palette.textMuted),
                const SizedBox(height: 16),
                Text('Signed in as admin', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text(
                  'Admin tools live in the web and desktop apps. Sign in with a regular account to chat here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Palette.textMuted),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  key: const Key('sign-out'),
                  onPressed: controller.signOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
