import 'package:flutter/material.dart';

import '../api/rpc_client.dart';
import '../state/chat_controller.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/toast.dart';
import 'chat_screen.dart';

/// Pick a person to start a direct message with.
Future<void> showNewMessageSheet(BuildContext context, ChatController chat) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NewMessage(chat: chat, parent: context),
  );
}

class _NewMessage extends StatefulWidget {
  const _NewMessage({required this.chat, required this.parent});

  final ChatController chat;

  /// The screen under the sheet, used to open the chat after the sheet closes.
  final BuildContext parent;

  @override
  State<_NewMessage> createState() => _NewMessageState();
}

class _NewMessageState extends State<_NewMessage> {
  String _filter = '';
  bool _busy = false;

  Future<void> _start(String username) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final channel = await widget.chat.directMessageWith(username);
      if (!mounted || !widget.parent.mounted) return;
      final navigator = Navigator.of(widget.parent);
      Navigator.pop(context);
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => ChatScreen(chat: widget.chat, channel: channel.name),
      ));
    } on RpcException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.chat.people
        .where((u) => u.username.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                key: const Key('people-search'),
                onChanged: (v) => setState(() => _filter = v.trim()),
                decoration: const InputDecoration(
                  hintText: 'Search people',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: people.isEmpty
                  ? const Center(child: Text('Nobody found', style: TextStyle(color: Palette.textMuted)))
                  : ListView.builder(
                      itemCount: people.length,
                      itemBuilder: (context, i) {
                        final u = people[i];
                        return ListTile(
                          enabled: !_busy,
                          leading: PresenceAvatar(
                            username: u.username,
                            picture: u.avatar,
                            status: widget.chat.statusOf(u.username),
                            size: 40,
                            ring: Palette.bgSecondary,
                          ),
                          title: Text(u.username),
                          subtitle: Text(
                            widget.chat.statusOf(u.username),
                            style: TextStyle(color: statusColor(widget.chat.statusOf(u.username)), fontSize: 12),
                          ),
                          onTap: () => _start(u.username),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
