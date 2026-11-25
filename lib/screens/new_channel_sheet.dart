import 'package:flutter/material.dart';

import '../state/chat_controller.dart';
import '../theme.dart';
import '../util/channel_name.dart';
import '../widgets/avatar.dart';
import '../widgets/toast.dart';
import 'chat_screen.dart';

/// Make a channel: a name, a line about it, public or private (with the people to invite).
Future<void> showNewChannelSheet(BuildContext context, ChatController chat) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NewChannel(chat: chat, parent: context),
  );
}

class _NewChannel extends StatefulWidget {
  const _NewChannel({required this.chat, required this.parent});

  final ChatController chat;
  final BuildContext parent;

  @override
  State<_NewChannel> createState() => _NewChannelState();
}

class _NewChannelState extends State<_NewChannel> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final Set<String> _members = {};
  bool _private = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    final name = channelNameFrom(_name.text);
    final problem = channelNameProblem(name);
    if (problem != null) {
      showToast(context, problem);
      return;
    }
    setState(() => _busy = true);
    final r = await widget.chat.createChannel(
      name: name,
      description: _description.text,
      isPrivate: _private,
      members: _members.toList(),
    );
    if (!mounted) return;
    final c = r.channel;
    if (c == null) {
      setState(() => _busy = false);
      showToast(context, r.error ?? 'Could not create the channel');
      return;
    }
    if (!widget.parent.mounted) return;
    final navigator = Navigator.of(widget.parent);
    Navigator.pop(context);
    navigator.push(MaterialPageRoute<void>(builder: (_) => ChatScreen(chat: widget.chat, channel: c.name)));
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.chat.people;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('New channel', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                key: const Key('channel-name'),
                controller: _name,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Name', prefixText: '# ', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('channel-description'),
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'What is it for? (optional)', isDense: true),
              ),
              SwitchListTile(
                key: const Key('channel-private'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Private'),
                subtitle: Text(
                  _private ? 'Only the people you pick can see it' : 'Everybody on the server can join',
                  style: TextStyle(color: Palette.textMuted, fontSize: 12.5),
                ),
                value: _private,
                onChanged: (v) => setState(() => _private = v),
              ),
              if (_private) ...[
                Text('Invite', style: TextStyle(color: Palette.textMuted, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3),
                  child: people.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text('Nobody else is here yet', style: TextStyle(color: Palette.textMuted)),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final u in people)
                              CheckboxListTile(
                                key: Key('invite-${u.username}'),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                secondary: Avatar(username: u.username, picture: u.avatar, size: 30),
                                title: Text(u.username),
                                value: _members.contains(u.username),
                                onChanged: (v) => setState(() {
                                  if (v == true) {
                                    _members.add(u.username);
                                  } else {
                                    _members.remove(u.username);
                                  }
                                }),
                              ),
                          ],
                        ),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('channel-create'),
                  onPressed: _busy ? null : _create,
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Create channel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
