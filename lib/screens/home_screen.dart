import 'package:flutter/material.dart';

import '../models/channel.dart';
import '../models/message.dart';
import '../state/app_controller.dart';
import '../state/chat_controller.dart';
import '../theme.dart';
import '../util/gif_url.dart';
import '../util/time_format.dart';
import '../widgets/avatar.dart';
import '../widgets/connection_banner.dart';
import '../widgets/motion.dart';
import 'chat_screen.dart';
import 'new_channel_sheet.dart';
import 'new_message_sheet.dart';
import 'profile_sheet.dart';
import 'search_screen.dart';

/// Channels and direct messages, with unread badges.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.app, required this.chat});

  final AppController app;
  final ChatController chat;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)..addListener(_tabChanged);

  void _tabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  int _unreadIn(List<Channel> list) => list.fold(0, (sum, c) => sum + (widget.chat.unread[c.name] ?? 0));

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final me = chat.me;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 16,
            title: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset('assets/logo.png', width: 28, height: 28),
                ),
                const SizedBox(width: 10),
                const Text('GoThermo'),
              ],
            ),
            actions: [
              IconButton(
                key: const Key('search'),
                tooltip: 'Search messages',
                icon: const Icon(Icons.search),
                onPressed: () => Navigator.of(context).push(riseRoute<void>(SearchScreen(chat: chat))),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: InkWell(
                  key: const Key('profile-button'),
                  customBorder: const CircleBorder(),
                  onTap: () => showProfileSheet(context, widget.app, chat),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: PresenceAvatar(
                      username: me,
                      picture: chat.avatarOf(me),
                      status: chat.statusOf(me) == 'offline' ? 'online' : chat.statusOf(me),
                      size: 32,
                      ring: Palette.bgSecondary,
                    ),
                  ),
                ),
              ),
            ],
            bottom: TabBar(
              controller: _tabs,
              indicatorColor: Palette.accent,
              dividerColor: Palette.border,
              tabs: [
                _tab('Channels', _unreadIn(chat.channels)),
                _tab('Direct', _unreadIn(chat.dms)),
              ],
            ),
          ),
          body: Column(
            children: [
              ConnectionBanner(visible: chat.started && !chat.connected),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _ChannelList(chat: chat, channels: chat.channels, direct: false),
                    _ChannelList(chat: chat, channels: _dmsByActivity(), direct: true),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutBack,
            transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
            child: _tabs.index == 1
                ? FloatingActionButton.extended(
                    key: const Key('new-message'),
                    heroTag: 'new-message',
                    onPressed: () => showNewMessageSheet(context, chat),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('New message'),
                  )
                : FloatingActionButton.extended(
                    key: const Key('new-channel'),
                    heroTag: 'new-channel',
                    onPressed: () => showNewChannelSheet(context, chat),
                    icon: const Icon(Icons.add),
                    label: const Text('New channel'),
                  ),
          ),
        );
      },
    );
  }

  List<Channel> _dmsByActivity() {
    final list = List<Channel>.of(widget.chat.dms);
    DateTime when(Channel c) =>
        widget.chat.lastMessage[c.name]?.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
    list.sort((a, b) => when(b).compareTo(when(a)));
    return list;
  }

  Tab _tab(String label, int unread) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: unread > 0
                ? Padding(padding: const EdgeInsets.only(left: 6), child: _Badge(count: unread))
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Palette.danger, borderRadius: BorderRadius.circular(10)),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
        child: Text(
          count > 99 ? '99+' : '$count',
          key: ValueKey<int>(count),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _ChannelList extends StatelessWidget {
  const _ChannelList({required this.chat, required this.channels, required this.direct});

  final ChatController chat;
  final List<Channel> channels;
  final bool direct;

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (!chat.started) {
      body = ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < 6; i++)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Skeleton(width: 44, height: 44, radius: 22),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Skeleton(width: 120, height: 13), SizedBox(height: 8), Skeleton(height: 11)],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    } else if (channels.isEmpty) {
      body = ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: PopIn(
              child: Column(
                children: [
                  Icon(direct ? Icons.chat_bubble_outline : Icons.tag, size: 44, color: Palette.textMuted),
                  const SizedBox(height: 10),
                  Text(
                    direct ? 'No direct messages yet' : (chat.error ?? 'No channels yet'),
                    style: TextStyle(color: Palette.textMuted),
                  ),
                  if (direct) Text('Tap "New message" to start one', style: TextStyle(color: Palette.textMuted)),
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      body = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: channels.length,
        itemBuilder: (context, i) => _ChannelTile(chat: chat, channel: channels[i]),
      );
    }
    return RefreshIndicator(onRefresh: chat.refreshLists, child: body);
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.chat, required this.channel});

  final ChatController chat;
  final Channel channel;

  String _preview(Message m) {
    final String body;
    if (m.isCall) {
      body = 'Call';
    } else if (m.isFile) {
      body = m.fileName.isEmpty ? 'File' : m.fileName;
    } else if (gifUrlOf(m.text) != null) {
      body = 'GIF';
    } else {
      body = m.text.replaceAll('\n', ' ');
    }
    if (m.user == chat.me) return 'You: $body';
    return channel.isDm ? body : '${m.user}: $body';
  }

  @override
  Widget build(BuildContext context) {
    final unread = chat.unread[channel.name] ?? 0;
    final last = chat.lastMessage[channel.name];
    final peer = channel.isDm ? channel.others(chat.me).firstOrNull ?? '' : '';
    final subtitle = last != null ? _preview(last) : channel.description;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ChatScreen(chat: chat, channel: channel.name)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (channel.isDm)
              PresenceAvatar(username: peer, picture: chat.avatarOf(peer), status: chat.statusOf(peer), size: 44)
            else
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Palette.bgTertiary, borderRadius: BorderRadius.circular(14)),
                child: Icon(channel.isPrivate ? Icons.lock_outline : Icons.tag, color: Palette.textMuted),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.title(chat.me),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500),
                  ),
                  if (subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: unread > 0 ? Palette.textPrimary : Palette.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (last != null)
                  Text(
                    shortStamp(last.timestamp, DateTime.now()),
                    style: TextStyle(fontSize: 11.5, color: unread > 0 ? Palette.accent : Palette.textMuted),
                  ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: unread > 0
                      ? Padding(padding: const EdgeInsets.only(top: 4), child: _Badge(count: unread))
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
