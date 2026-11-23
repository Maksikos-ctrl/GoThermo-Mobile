import 'package:flutter/material.dart';

import '../state/chat_controller.dart';
import '../theme.dart';
import '../util/time_format.dart';
import '../widgets/avatar_color.dart';
import '../widgets/toast.dart';
import 'thread_screen.dart';

/// Messages pinned in one channel.
class PinnedScreen extends StatefulWidget {
  const PinnedScreen({super.key, required this.chat, required this.channel});

  final ChatController chat;
  final String channel;

  @override
  State<PinnedScreen> createState() => _PinnedScreenState();
}

class _PinnedScreenState extends State<PinnedScreen> {
  @override
  void initState() {
    super.initState();
    widget.chat.loadPins(widget.channel);
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    return Scaffold(
      appBar: AppBar(title: const Text('Pinned messages')),
      body: ListenableBuilder(
        listenable: chat,
        builder: (context, _) {
          final pins = chat.pinsOf(widget.channel);
          if (pins.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Nothing is pinned here yet.\nLong-press a message and choose Pin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Palette.textMuted),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: pins.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final p = pins[i];
              final m = p.message;
              return Material(
                color: Palette.bgSecondary,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => ThreadScreen(chat: chat, parent: m)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(m.user, style: TextStyle(fontWeight: FontWeight.w700, color: avatarColor(m.user))),
                                  const SizedBox(width: 8),
                                  Text(clock(m.timestamp), style: TextStyle(color: Palette.textMuted, fontSize: 11.5)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                m.isFile ? '📎 ${m.fileName}' : m.text,
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (p.pinnedBy.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text('Pinned by ${p.pinnedBy}', style: TextStyle(color: Palette.textMuted, fontSize: 11.5)),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          key: Key('unpin-${m.id}'),
                          tooltip: 'Unpin',
                          icon: const Icon(Icons.push_pin),
                          onPressed: () async {
                            final error = await chat.unpin(m);
                            if (context.mounted) toastIfError(context, error);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
