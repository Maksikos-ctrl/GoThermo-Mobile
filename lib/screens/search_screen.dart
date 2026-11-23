import 'dart:async';

import 'package:flutter/material.dart';

import '../api/rpc_client.dart';
import '../models/message.dart';
import '../state/chat_controller.dart';
import '../theme.dart';
import '../util/time_format.dart';
import '../widgets/avatar.dart';
import '../widgets/motion.dart';
import 'chat_screen.dart';

/// Search across every channel you can read.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.chat});

  final ChatController chat;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  Timer? _debounce;
  List<Message> _results = const [];
  bool _loading = false;
  String _query = '';
  String? _error;
  int _request = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(text.trim()));
  }

  Future<void> _run(String q) async {
    final mine = ++_request;
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
    });
    try {
      final found = await widget.chat.api.search(widget.chat.token, widget.chat.me, q);
      if (!mounted || mine != _request) return;
      setState(() {
        _results = found;
        _loading = false;
      });
    } on RpcException catch (e) {
      if (!mounted || mine != _request) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const Key('search-field'),
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search messages',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _loading
            ? const Center(key: ValueKey('loading'), child: CircularProgressIndicator())
            : _error != null
                ? Center(key: const ValueKey('error'), child: Text(_error!))
                : _query.isEmpty
                    ? Center(
                        key: ValueKey('hint'),
                        child: Text('Type to search all your channels', style: TextStyle(color: Palette.textMuted)),
                      )
                    : _results.isEmpty
                        ? Center(
                            key: const ValueKey('none'),
                            child: Text('Nothing found for "$_query"', style: TextStyle(color: Palette.textMuted)),
                          )
                        : ListView.builder(
                            key: const ValueKey('results'),
                            itemCount: _results.length,
                            itemBuilder: (context, i) {
                              final m = _results[i];
                              return PopIn(
                                rise: 8,
                                child: ListTile(
                                  leading: Avatar(username: m.user, picture: chat.avatarOf(m.user), size: 40),
                                  title: Text(
                                    '${m.user}  in ${chat.titleOf(m.channel)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    m.text.replaceAll('\n', ' '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Text(
                                    shortStamp(m.timestamp, DateTime.now()),
                                    style: TextStyle(color: Palette.textMuted, fontSize: 11.5),
                                  ),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => ChatScreen(chat: chat, channel: m.channel),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
      ),
    );
  }
}
