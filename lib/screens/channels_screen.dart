import 'package:flutter/material.dart';

import '../api/rpc_client.dart';
import '../models/channel.dart';
import '../state/app_controller.dart';
import '../theme.dart';
import '../widgets/avatar.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  List<Channel> _channels = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = widget.controller.session;
    if (session == null) return;
    try {
      final list = await widget.controller.api.channels(session.token);
      if (!mounted) return;
      setState(() {
        _channels = list;
        _error = null;
        _loading = false;
      });
    } on RpcException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.controller.session?.user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('GoThermo'),
        actions: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Avatar(username: user.username, picture: user.avatar, size: 32),
            ),
          IconButton(
            key: const Key('sign-out'),
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: widget.controller.signOut,
          ),
        ],
      ),
      body: user != null && user.isAdmin
          ? const _AdminNotice()
          : RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(child: Text(_error!, textAlign: TextAlign.center)),
          Center(child: TextButton(onPressed: _load, child: const Text('Try again'))),
        ],
      );
    }
    if (_channels.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          Center(child: Text('No channels yet', style: TextStyle(color: Palette.textMuted))),
        ],
      );
    }
    return ListView.builder(
      itemCount: _channels.length,
      itemBuilder: (context, i) {
        final c = _channels[i];
        return ListTile(
          leading: Icon(c.isPrivate ? Icons.lock_outline : Icons.tag),
          title: Text(c.name),
          subtitle: c.description.isEmpty ? null : Text(c.description, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Messages in #${c.name} come in the next step')),
          ),
        );
      },
    );
  }
}

class _AdminNotice extends StatelessWidget {
  const _AdminNotice();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'You are signed in as the admin. The admin panel is in the web app.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
