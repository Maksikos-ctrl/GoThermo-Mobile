import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/message.dart';
import 'decisions_screen.dart';
import 'pinned_screen.dart';
import 'thread_screen.dart';
import '../state/chat_controller.dart';
import '../theme.dart';
import '../util/mime.dart';
import '../util/time_format.dart';
import '../widgets/avatar.dart';
import '../widgets/composer.dart';
import '../widgets/connection_banner.dart';
import '../widgets/gif_picker.dart';
import '../widgets/message_actions.dart';
import '../widgets/message_row.dart';
import '../widgets/motion.dart';
import '../widgets/toast.dart';
import '../widgets/typing_indicator.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chat, required this.channel});

  final ChatController chat;

  /// The channel's name (for a direct message, `dm_<a>_<b>`).
  final String channel;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _Row {
  const _Row.day(this.label)
      : message = null,
        header = false;
  const _Row.message(Message this.message, this.header) : label = '';

  final Message? message;
  final bool header;
  final String label;
}

class _ChatScreenState extends State<ChatScreen> {
  final _scroll = ScrollController();
  final _picker = ImagePicker();

  /// Bubbles already on screen; only newcomers animate in.
  final Set<String> _known = {};
  bool _primed = false;
  DateTime? _newestAtOpen;
  bool _showJump = false;
  bool _uploading = false;

  ChatController get chat => widget.chat;
  String get channel => widget.channel;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) chat.open(channel);
    });
  }

  @override
  void dispose() {
    chat.close(channel);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 320) chat.loadOlder(channel);
    final far = pos.pixels > 500;
    if (far != _showJump) setState(() => _showJump = far);
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
      }
    });
  }

  void _send(String text) {
    chat.send(channel, text);
    _toBottom();
  }

  Future<void> _gif() async {
    final url = await showGifPicker(context, chat);
    if (url != null) _send(url);
  }

  Future<void> _attach(AttachChoice choice) async {
    try {
      switch (choice) {
        case AttachChoice.gallery:
          await _sendPicked(await _picker.pickImage(source: ImageSource.gallery, maxWidth: 2048, imageQuality: 88));
        case AttachChoice.camera:
          await _sendPicked(await _picker.pickImage(source: ImageSource.camera, maxWidth: 2048, imageQuality: 88));
        case AttachChoice.file:
          final result = await FilePicker.platform.pickFiles(withData: true);
          final file = result?.files.isNotEmpty == true ? result!.files.first : null;
          final bytes = file?.bytes;
          if (file != null && bytes != null) await _upload(bytes, file.name, null);
      }
    } on Object {
      if (mounted) showToast(context, 'Could not open that. Check the app\'s permissions in Settings.');
    }
  }

  Future<void> _sendPicked(XFile? picked) async {
    if (picked == null) return;
    await _upload(await picked.readAsBytes(), picked.name, picked.mimeType);
  }

  Future<void> _upload(Uint8List bytes, String name, String? mime) async {
    setState(() => _uploading = true);
    final error = await chat.sendFile(
      channel,
      name,
      (mime == null || mime.isEmpty) ? mimeFromName(name) : mime,
      bytes,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    toastIfError(context, error);
    if (error == null) _toBottom();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: _title(),
            actions: [..._callButtons(), _channelMenu()],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(2),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _uploading ? 1 : 0,
                child: _uploading ? const LinearProgressIndicator(minHeight: 2) : const SizedBox(height: 2),
              ),
            ),
          ),
          body: Column(
            children: [
              ConnectionBanner(visible: chat.started && !chat.connected),
              Expanded(child: _body()),
              TypingIndicator(names: chat.typingIn(channel)),
              Composer(
                onTyping: () => chat.announceTyping(channel),
                mentionable: chat.mentionable,
                hint: 'Message ${chat.titleOf(channel)}',
                onSend: _send,
                onAttach: _attach,
                onGif: chat.gifsEnabled ? _gif : null,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _title() {
    final c = chat.channelNamed(channel);
    final isDm = c?.isDm ?? channel.startsWith('dm_');
    if (isDm) {
      final others = c?.others(chat.me) ?? const <String>[];
      final peer = others.isNotEmpty ? others.first : chat.titleOf(channel);
      final status = chat.statusOf(peer);
      return Row(
        children: [
          PresenceAvatar(
            username: peer,
            picture: chat.avatarOf(peer),
            status: status,
            size: 34,
            ring: Palette.bgSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(chat.titleOf(channel), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17)),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    status,
                    key: ValueKey<String>(status),
                    style: TextStyle(fontSize: 12, color: statusColor(status)),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final subtitle = (c?.description.isNotEmpty ?? false)
        ? c!.description
        : (c?.isPrivate ?? false)
            ? 'Private channel'
            : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(chat.titleOf(channel), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17)),
        if (subtitle != null)
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Palette.textMuted)),
      ],
    );
  }

  /// Voice and video call buttons, for a conversation with exactly one other person.
  Widget _channelMenu() {
    final pins = chat.pinsOf(channel).length;
    return PopupMenuButton<String>(
      key: const Key('channel-menu'),
      tooltip: 'More',
      onSelected: (v) {
        final page = v == 'pins'
            ? PinnedScreen(chat: chat, channel: channel)
            : DecisionsScreen(chat: chat, channel: channel);
        Navigator.of(context).push(riseRoute<void>(page));
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          key: const Key('menu-pins'),
          value: 'pins',
          child: Text(pins == 0 ? 'Pinned messages' : 'Pinned messages ($pins)'),
        ),
        const PopupMenuItem<String>(
          key: Key('menu-decisions'),
          value: 'decisions',
          child: Text('Decisions & tasks'),
        ),
      ],
    );
  }

  List<Widget> _callButtons() {
    final ch = chat.channelNamed(channel);
    final calls = chat.calls;
    if (ch == null || !ch.isDm || calls == null) return const [];
    final others = ch.others(chat.me);
    if (others.length != 1) return const [];
    final peer = others.first;
    final ready = chat.connected && !calls.busy;
    return [
      IconButton(
        key: const Key('call-voice'),
        tooltip: 'Voice call',
        icon: const Icon(Icons.call_outlined),
        onPressed: ready ? () => calls.start(peer) : null,
      ),
      IconButton(
        key: const Key('call-video'),
        tooltip: 'Video call',
        icon: const Icon(Icons.videocam_outlined),
        onPressed: ready ? () => calls.start(peer, video: true) : null,
      ),
      const SizedBox(width: 4),
    ];
  }

  Widget _body() {
    final feed = chat.feed(channel);
    final messages = chat.messagesOf(channel);

    if (!feed.loaded) {
      if (chat.error != null && !feed.loading) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(chat.error!, textAlign: TextAlign.center),
              TextButton(onPressed: () => chat.loadNewest(channel), child: const Text('Try again')),
            ],
          ),
        );
      }
      return const MessageSkeletons();
    }

    if (!_primed) {
      _primed = true;
      _known.addAll(messages.map((m) => m.stableKey));
      _newestAtOpen = messages.isEmpty ? null : messages.last.timestamp;
    }

    if (messages.isEmpty) {
      return Center(
        child: PopIn(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('👋', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 8),
              Text('No messages in ${chat.titleOf(channel)} yet', style: TextStyle(color: Palette.textMuted)),
              Text('Say hi!', style: TextStyle(color: Palette.textMuted)),
            ],
          ),
        ),
      );
    }

    final now = DateTime.now();
    final rows = <_Row>[];
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final prev = i > 0 ? messages[i - 1] : null;
      final newDay = prev == null || !sameDay(prev.timestamp, m.timestamp);
      if (newDay) rows.add(_Row.day(dayLabel(m.timestamp, now)));
      final header = newDay ||
          prev.user != m.user ||
          prev.isCall ||
          m.isCall ||
          prev.isPost ||
          m.isPost ||
          m.timestamp.difference(prev.timestamp).inMinutes >= 5;
      rows.add(_Row.message(m, header));
    }

    final fresh = <String>{};
    final opened = _newestAtOpen;
    for (final m in messages) {
      if (!_known.contains(m.stableKey) && (opened == null || m.timestamp.isAfter(opened))) {
        fresh.add(m.stableKey);
      }
    }
    _known.addAll(messages.map((m) => m.stableKey));

    return Stack(
      children: [
        ListView.builder(
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          itemCount: rows.length + 1,
          itemBuilder: (context, index) {
            if (index == rows.length) return _top(feed);
            final row = rows[rows.length - 1 - index];
            final m = row.message;
            if (m == null) return DayChip(key: ValueKey<String>('day-$index-${row.label}'), label: row.label);
            return PopIn(
              key: ValueKey<String>(m.stableKey),
              enabled: fresh.contains(m.stableKey),
              child: MessageRow(
                message: m,
                chat: chat,
                showHeader: row.header,
                onLongPress: () => showMessageActions(context, chat, m),
                onOpenThread: () => Navigator.of(context).push(riseRoute<void>(ThreadScreen(chat: chat, parent: m))),
              ),
            );
          },
        ),
        Positioned(
          right: 14,
          bottom: 12,
          child: AnimatedScale(
            scale: _showJump ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            child: FloatingActionButton.small(
              key: const Key('jump-down'),
              heroTag: 'jump-down-$channel',
              onPressed: _toBottom,
              child: const Icon(Icons.keyboard_arrow_down),
            ),
          ),
        ),
      ],
    );
  }

  Widget _top(ChannelFeed feed) {
    if (feed.hasMore && feed.loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (feed.hasMore) return const SizedBox(height: 16);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        'This is the start of ${chat.titleOf(channel)}',
        textAlign: TextAlign.center,
        style: TextStyle(color: Palette.textMuted, fontSize: 12.5),
      ),
    );
  }
}
