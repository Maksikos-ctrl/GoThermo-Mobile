import 'package:flutter/material.dart';

import '../models/message.dart';
import '../state/chat_controller.dart';
import '../theme.dart';
import '../widgets/mention_bar.dart';
import '../widgets/message_actions.dart';
import '../widgets/message_row.dart';
import '../widgets/toast.dart';

/// The replies under one message, with a box to answer.
class ThreadScreen extends StatefulWidget {
  const ThreadScreen({super.key, required this.chat, required this.parent});

  final ChatController chat;
  final Message parent;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _text = TextEditingController();
  bool _sending = false;
  bool _loadFailed = false;

  ChatController get chat => widget.chat;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final error = await chat.loadThread(widget.parent.channel, widget.parent.id);
    if (!mounted) return;
    setState(() => _loadFailed = error != null);
    toastIfError(context, error);
  }

  Message get _parent {
    final fresh = chat.threadOf(widget.parent.channel, widget.parent.id)?.parent;
    return fresh ?? widget.parent;
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    final error = await chat.reply(_parent, body);
    if (!mounted) return;
    setState(() => _sending = false);
    if (error == null) {
      _text.clear();
    } else {
      toastIfError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final thread = chat.threadOf(widget.parent.channel, widget.parent.id);
        final replies = thread?.replies ?? const <Message>[];
        return Scaffold(
          appBar: AppBar(title: const Text('Thread')),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  key: const Key('thread-list'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    MessageRow(message: _parent, chat: chat, showHeader: true, showThread: false),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Row(
                        children: [
                          Text(
                            replies.isEmpty ? 'No replies yet' : '${replies.length} ${replies.length == 1 ? 'reply' : 'replies'}',
                            style: TextStyle(color: Palette.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Divider(color: Palette.border, height: 1)),
                        ],
                      ),
                    ),
                    if (thread == null && !_loadFailed)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                      ),
                    if (_loadFailed && thread == null)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: TextButton(onPressed: _load, child: const Text('Could not load. Try again'))),
                      ),
                    for (final r in replies)
                      MessageRow(
                        key: ValueKey<String>(r.id),
                        message: r,
                        chat: chat,
                        showHeader: true,
                        showThread: false,
                        onLongPress: () => showReplyActions(context, chat, r),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(color: Palette.bgSecondary, child: MentionBar(controller: _text, mentionable: chat.mentionable)),
                    Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  decoration: BoxDecoration(color: Palette.bgSecondary, border: Border(top: BorderSide(color: Palette.border))),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('thread-field'),
                          controller: _text,
                          minLines: 1,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(hintText: 'Reply in thread', border: InputBorder.none),
                        ),
                      ),
                      IconButton(
                        key: const Key('thread-send'),
                        icon: _sending
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send_rounded),
                        onPressed: _sending ? null : _send,
                      ),
                    ],
                  ),
                ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
