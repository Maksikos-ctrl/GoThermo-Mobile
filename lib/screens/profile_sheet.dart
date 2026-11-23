import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../state/app_controller.dart';
import '../state/chat_controller.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/toast.dart';

/// Your picture, status, the server and sign out.
Future<void> showProfileSheet(BuildContext context, AppController app, ChatController chat) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _Profile(app: app, chat: chat, parent: context),
  );
}

class _Profile extends StatefulWidget {
  const _Profile({required this.app, required this.chat, required this.parent});

  final AppController app;
  final ChatController chat;
  final BuildContext parent;

  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  bool _busy = false;

  Future<void> _pickPicture() async {
    if (_busy) return;
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
      if (picked == null) return;
      setState(() => _busy = true);
      final error = await widget.chat.setAvatar(await picked.readAsBytes());
      if (!mounted) return;
      setState(() => _busy = false);
      toastIfError(context, error);
    } on Object {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, 'Could not open your photos. Check the app\'s permissions in Settings.');
      }
    }
  }

  Future<void> _removePicture() async {
    setState(() => _busy = true);
    final error = await widget.chat.removeAvatar();
    if (!mounted) return;
    setState(() => _busy = false);
    toastIfError(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final me = chat.me;
        final user = chat.userOf(me);
        final email = chat.session.user.email;
        final status = chat.statusOf(me) == 'away' ? 'away' : 'online';
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  key: const Key('change-picture'),
                  onTap: _pickPicture,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Avatar(username: me, picture: user?.avatar, size: 92),
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Palette.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Palette.bgSecondary, width: 3),
                        ),
                        child: _busy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.photo_camera, size: 16, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(me, style: Theme.of(context).textTheme.titleLarge),
                if (email.isNotEmpty) Text(email, style: const TextStyle(color: Palette.textMuted)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final s in const ['online', 'away'])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          key: Key('status-$s'),
                          avatar: StatusDot(status: s, size: 12, ring: Palette.bgSecondary),
                          label: Text(s == 'online' ? 'Online' : 'Away'),
                          selected: status == s,
                          onSelected: (_) => chat.setStatus(s),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (user?.avatar != null)
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Remove picture'),
                    onTap: _busy ? null : _removePicture,
                  ),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('Server'),
                  subtitle: Text(widget.app.serverUrl.replaceFirst('https://', '')),
                ),
                ListTile(
                  key: const Key('sign-out'),
                  leading: const Icon(Icons.logout, color: Palette.danger),
                  title: const Text('Sign out', style: TextStyle(color: Palette.danger)),
                  onTap: () {
                    Navigator.pop(context);
                    widget.app.signOut();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
