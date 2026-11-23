import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../api/gothermo_api.dart';
import '../api/rpc_client.dart';
import '../api/socket.dart';
import '../models/channel.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../util/mime.dart';

/// The messages of one channel as far as this phone has loaded them.
class ChannelFeed {
  final List<Message> messages = [];
  bool loaded = false;
  bool loading = false;
  bool hasMore = true;
}

/// A new message in a channel the person is not looking at.
class Notice {
  const Notice(this.message, this.title);

  final Message message;

  /// `#general`, or the name of the person in a direct message.
  final String title;
}

const pageSize = 40;

/// [reactions] with [me]'s [emoji] added, or removed if it was already there.
/// Pure, so the same rule works for the optimistic update and in tests.
Map<String, List<String>> toggledReactions(
  Map<String, List<String>> reactions,
  String emoji,
  String me,
) {
  final next = <String, List<String>>{
    for (final e in reactions.entries) e.key: List<String>.of(e.value),
  };
  final people = next[emoji] ?? <String>[];
  if (people.contains(me)) {
    people.remove(me);
  } else {
    people.add(me);
  }
  if (people.isEmpty) {
    next.remove(emoji);
  } else {
    next[emoji] = people;
  }
  return next;
}

/// Everything a signed-in phone knows: channels, people, messages and unread
/// counts, kept fresh by the server's live connection (and by polling while
/// that connection is down).
class ChatController extends ChangeNotifier {
  ChatController({
    required this.api,
    required this.session,
    required this.serverUrl,
    SocketConnector? connector,
    DateTime Function()? clock,
    this.pollEvery = const Duration(seconds: 8),
  })  : _connector = connector ?? const WebSocketConnector(),
        _now = clock ?? DateTime.now;

  final GoThermoApi api;
  final Session session;
  final String serverUrl;
  final Duration pollEvery;
  final SocketConnector _connector;
  final DateTime Function() _now;

  String get me => session.user.username;
  String get token => session.token;

  // ---- what the screens read ---------------------------------------------

  List<Channel> channels = const [];
  List<Channel> dms = const [];
  final Map<String, User> users = {};
  final Map<String, int> unread = {};
  final Map<String, Message> lastMessage = {};
  bool connected = false;
  bool started = false;
  bool gifsEnabled = false;
  String? error;

  /// The channel on screen right now, if any.
  String? active;

  Stream<Notice> get notices => _notices.stream;
  final StreamController<Notice> _notices = StreamController<Notice>.broadcast();

  int get totalUnread => unread.values.fold(0, (a, b) => a + b);

  User? userOf(String name) => users[name];
  String? avatarOf(String name) => users[name]?.avatar;
  String statusOf(String name) => users[name]?.status ?? 'offline';
  List<User> get people => (users.values.where((u) => u.username != me).toList()
    ..sort((a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase())));

  Channel? channelNamed(String name) {
    for (final c in [...channels, ...dms]) {
      if (c.name == name) return c;
    }
    return null;
  }

  String titleOf(String channel) {
    final c = channelNamed(channel);
    if (c == null) return channel;
    return c.isDm ? c.title(me) : '#${c.name}';
  }

  ChannelFeed feed(String channel) => _feeds.putIfAbsent(channel, ChannelFeed.new);
  List<Message> messagesOf(String channel) => List.unmodifiable(feed(channel).messages);

  // ---- internals -----------------------------------------------------------

  final Map<String, ChannelFeed> _feeds = {};
  SocketConnection? _conn;
  StreamSubscription<String>? _sub;
  Timer? _ping;
  Timer? _reconnect;
  Timer? _poll;
  bool _connecting = false;
  bool _disposed = false;
  int _backoff = 0;
  int _localSeq = 0;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ping?.cancel();
    _reconnect?.cancel();
    _poll?.cancel();
    _sub?.cancel();
    _conn?.close();
    _notices.close();
    super.dispose();
  }

  // ---- starting ------------------------------------------------------------

  Future<void> start() async {
    await refreshLists();
    started = true;
    notifyListeners();
    unawaited(_loadGifs());
    _poll = Timer.periodic(pollEvery, (_) => _pollOnce());
    await _connect();
  }

  Future<void> _loadGifs() async {
    gifsEnabled = await api.gifsEnabled(token);
    notifyListeners();
  }

  Future<void> _guard(Future<void> Function() step) async {
    try {
      await step();
    } on RpcException catch (e) {
      error = e.message;
    }
  }

  /// Channels, direct messages, people and unread counts.
  Future<void> refreshLists() async {
    error = null;
    await Future.wait([
      _guard(() async => channels = _sortedChannels(await api.channels(token))),
      _guard(() async => dms = await api.dmChannels(token, me)),
      _guard(() async => _setUsers(await api.users(token))),
      _guard(() async {
        unread
          ..clear()
          ..addAll(await api.unreadCounts(token, me));
        if (active != null) unread[active!] = 0;
      }),
    ]);
    notifyListeners();
  }

  List<Channel> _sortedChannels(List<Channel> list) =>
      List.of(list)..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  void _setUsers(List<User> list) {
    for (final u in list) {
      users[u.username] = u;
    }
  }

  // ---- messages --------------------------------------------------------------

  Future<void> open(String channel) async {
    active = channel;
    unread[channel] = 0;
    _sendFrame('subscribe_channel', channel);
    notifyListeners();
    await loadNewest(channel);
    _markRead(channel);
  }

  void close(String channel) {
    if (active == channel) active = null;
  }

  /// The newest page, merged into what is already there.
  Future<void> loadNewest(String channel) async {
    final f = feed(channel);
    if (f.loading) return;
    f.loading = true;
    notifyListeners();
    try {
      final page = await api.messagesPage(token, channel, limit: pageSize);
      _merge(channel, page);
      if (!f.loaded) f.hasMore = page.length >= pageSize;
      f.loaded = true;
      error = null;
    } on RpcException catch (e) {
      error = e.message;
    } finally {
      f.loading = false;
      notifyListeners();
    }
  }

  /// The page before the oldest message on screen.
  Future<void> loadOlder(String channel) async {
    final f = feed(channel);
    if (f.loading || !f.hasMore || !f.loaded) return;
    final oldest = f.messages.where((m) => m.sendState == SendState.sent).firstOrNull;
    if (oldest == null) return;
    f.loading = true;
    notifyListeners();
    try {
      final page = await api.messagesPage(token, channel, beforeId: oldest.id, limit: pageSize);
      _merge(channel, page);
      f.hasMore = page.length >= pageSize;
    } on RpcException catch (e) {
      error = e.message;
    } finally {
      f.loading = false;
      notifyListeners();
    }
  }

  void _merge(String channel, List<Message> page) {
    final f = feed(channel);
    for (final m in page) {
      _put(f, m);
    }
    _sort(f);
    if (f.messages.isNotEmpty) _rememberLast(channel, f.messages.last);
  }

  void _put(ChannelFeed f, Message m) {
    final i = f.messages.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      f.messages[i] = m;
    } else {
      f.messages.add(m);
    }
  }

  void _sort(ChannelFeed f) {
    f.messages.sort((a, b) {
      final c = a.timestamp.compareTo(b.timestamp);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  }

  void _rememberLast(String channel, Message m) {
    final old = lastMessage[channel];
    if (old == null || !m.timestamp.isBefore(old.timestamp)) lastMessage[channel] = m;
  }

  // ---- sending -----------------------------------------------------------------

  Future<void> send(String channel, String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final localId = 'local-${_localSeq++}';
    final pending = Message(
      id: localId,
      clientId: localId,
      user: me,
      text: body,
      channel: channel,
      timestamp: _now(),
      sendState: SendState.sending,
    );
    final f = feed(channel);
    f.messages.add(pending);
    _sort(f);
    _rememberLast(channel, pending);
    notifyListeners();
    await _deliver(pending);
  }

  Future<void> _deliver(Message pending) async {
    try {
      final id = await api.sendMessage(token, me, pending.text, pending.channel);
      final f = feed(pending.channel);
      f.messages.removeWhere((m) => m.id == pending.id);
      if (id.isNotEmpty && !f.messages.any((m) => m.id == id)) {
        f.messages.add(pending.copyWith(id: id, sendState: SendState.sent));
      }
      _sort(f);
    } on RpcException catch (e) {
      _setState(pending, SendState.failed);
      error = e.message;
    }
    notifyListeners();
  }

  void _setState(Message pending, SendState state) {
    final f = feed(pending.channel);
    final i = f.messages.indexWhere((m) => m.id == pending.id);
    if (i >= 0) f.messages[i] = f.messages[i].copyWith(sendState: state);
  }

  /// Tries again a message that failed to send.
  Future<void> retry(Message failed) async {
    _setState(failed, SendState.sending);
    notifyListeners();
    await _deliver(failed);
  }

  /// Drops a message that failed to send.
  void discard(Message failed) {
    feed(failed.channel).messages.removeWhere((m) => m.id == failed.id);
    notifyListeners();
  }

  /// Returns what went wrong, or null.
  Future<String?> sendFile(String channel, String name, String mime, Uint8List bytes) async {
    try {
      final msg = await api.sendFile(token, me, channel, name, mime, base64Encode(bytes));
      final f = feed(channel);
      _put(f, msg);
      _sort(f);
      _rememberLast(channel, msg);
      notifyListeners();
      return null;
    } on RpcException catch (e) {
      return e.message;
    }
  }

  Future<String?> react(Message m, String emoji) async {
    final before = m.reactions;
    _replace(m.channel, m.id, (cur) => cur.copyWith(reactions: toggledReactions(cur.reactions, emoji, me)));
    try {
      await api.toggleReaction(token, m.id, emoji, me, m.channel);
      return null;
    } on RpcException catch (e) {
      _replace(m.channel, m.id, (cur) => cur.copyWith(reactions: before));
      return e.message;
    }
  }

  Future<String?> edit(Message m, String newText) async {
    final text = newText.trim();
    if (text.isEmpty || text == m.text) return null;
    try {
      final updated = await api.editMessage(token, m.id, m.channel, me, text);
      _replace(m.channel, m.id, (_) => updated);
      return null;
    } on RpcException catch (e) {
      return e.message;
    }
  }

  Future<String?> delete(Message m) async {
    try {
      await api.deleteMessage(token, m.id, m.channel, me);
      _remove(m.channel, m.id);
      return null;
    } on RpcException catch (e) {
      return e.message;
    }
  }

  void _replace(String channel, String id, Message Function(Message) change) {
    final f = feed(channel);
    final i = f.messages.indexWhere((x) => x.id == id);
    if (i >= 0) {
      f.messages[i] = change(f.messages[i]);
      notifyListeners();
    }
  }

  void _remove(String channel, String id) {
    final f = feed(channel);
    f.messages.removeWhere((x) => x.id == id);
    if (f.messages.isNotEmpty) {
      lastMessage[channel] = f.messages.last;
    } else {
      lastMessage.remove(channel);
    }
    notifyListeners();
  }

  void _markRead(String channel) {
    unread[channel] = 0;
    notifyListeners();
    unawaited(_guard(() => api.markRead(token, me, channel)));
  }

  // ---- files ---------------------------------------------------------------------

  final Map<String, Future<Uint8List>> _files = {};

  /// The bytes of an uploaded file. Fetched once, then remembered; a failed
  /// fetch is forgotten so the next look tries again.
  Future<Uint8List> fileBytes(String fileId) {
    final cached = _files[fileId];
    if (cached != null) return cached;
    final f = _fetchFile(fileId);
    _files[fileId] = f;
    f.then<void>((_) {}, onError: (Object _) => _files.remove(fileId));
    return f;
  }

  Future<Uint8List> _fetchFile(String fileId) async {
    final data = await api.fileData(token, fileId);
    final parts = splitDataUrl(data);
    if (parts == null) throw RpcException('The file could not be read');
    try {
      return base64Decode(parts.base64);
    } on FormatException {
      throw RpcException('The file could not be read');
    }
  }

  // ---- direct messages -----------------------------------------------------------

  /// Opens (or creates) the direct message with [username].
  Future<Channel> directMessageWith(String username) async {
    final channel = await api.getOrCreateDm(token, me, username);
    if (!dms.any((c) => c.name == channel.name)) dms = [...dms, channel];
    notifyListeners();
    return channel;
  }

  // ---- profile ---------------------------------------------------------------------

  Future<String?> setAvatar(Uint8List bytes) async {
    try {
      await api.setAvatar(token, me, base64Encode(bytes));
      await _guard(() async => _setUsers(await api.users(token)));
      notifyListeners();
      return null;
    } on RpcException catch (e) {
      return e.message;
    }
  }

  Future<String?> removeAvatar() async {
    try {
      await api.removeAvatar(token, me);
      final u = users[me];
      if (u != null) users[me] = u.copyWith(clearAvatar: true);
      notifyListeners();
      return null;
    } on RpcException catch (e) {
      return e.message;
    }
  }

  void setStatus(String status) {
    _sendFrame('status_change', {'status': status});
    final u = users[me];
    if (u != null) users[me] = u.copyWith(status: status);
    notifyListeners();
  }

  // ---- the live connection -----------------------------------------------------------

  void _sendFrame(String type, Object? payload) {
    final c = _conn;
    if (c == null) return;
    c.send(jsonEncode({'type': type, 'payload': payload}));
  }

  Future<void> _connect() async {
    if (_disposed || _connecting || _conn != null) return;
    _connecting = true;
    try {
      final c = await _connector.connect(socketUri(serverUrl, token));
      if (_disposed) {
        await c.close();
        return;
      }
      _conn = c;
      _backoff = 0;
      connected = true;
      _sub = c.frames.listen(
        _onFrame,
        onDone: _lost,
        onError: (Object _) => _lost(),
        cancelOnError: true,
      );
      _ping = Timer.periodic(const Duration(seconds: 25), (_) => _sendFrame('ping', null));
      if (active != null) _sendFrame('subscribe_channel', active);
      notifyListeners();
      // Catch up on whatever happened while the connection was down.
      unawaited(refreshAll());
    } on Object {
      _lost();
    } finally {
      _connecting = false;
    }
  }

  void _lost() {
    _sub?.cancel();
    _sub = null;
    _ping?.cancel();
    _ping = null;
    final c = _conn;
    _conn = null;
    if (c != null) unawaited(c.close());
    if (connected) {
      connected = false;
      notifyListeners();
    }
    if (_disposed) return;
    final seconds = math.min(30, 1 << math.min(_backoff, 5));
    _backoff++;
    _reconnect?.cancel();
    _reconnect = Timer(Duration(seconds: seconds), _connect);
  }

  /// The app came back to the front: reconnect now rather than after the wait.
  void resumed() {
    if (_disposed) return;
    if (!connected) {
      _reconnect?.cancel();
      _backoff = 0;
      unawaited(_connect());
    }
    unawaited(refreshAll());
  }

  Future<void> refreshAll() async {
    await refreshLists();
    final a = active;
    if (a != null) await loadNewest(a);
  }

  Future<void> _pollOnce() async {
    if (_disposed || connected) return;
    await _guard(() async {
      unread
        ..clear()
        ..addAll(await api.unreadCounts(token, me));
      if (active != null) unread[active!] = 0;
    });
    final a = active;
    if (a != null) await loadNewest(a);
    notifyListeners();
  }

  void _onFrame(String frame) {
    for (final e in parseSocketFrame(frame)) {
      _onEvent(e);
    }
  }

  Map<String, dynamic>? _asMap(Object? v) => v is Map<String, dynamic> ? v : null;

  void _onEvent(SocketEvent e) {
    final p = e.payload;
    switch (e.type) {
      case 'channel_message':
        final m = _asMap(p);
        final raw = _asMap(m?['message']);
        final channel = m?['channel'];
        if (raw != null && channel is String) _onIncoming(channel, Message.fromJson(raw));
      case 'message_deleted':
        final m = _asMap(p);
        final channel = m?['channel'];
        final id = m?['messageId'];
        if (channel is String && id is String) _remove(channel, id);
      case 'channel_created':
        final m = _asMap(p);
        if (m != null) _onChannelCreated(Channel.fromJson(m));
      case 'channel_deleted':
        final m = _asMap(p);
        final name = m?['channel'];
        if (name is String) {
          channels = channels.where((c) => c.name != name).toList();
          dms = dms.where((c) => c.name != name).toList();
          _feeds.remove(name);
          lastMessage.remove(name);
          unread.remove(name);
          notifyListeners();
        }
      case 'status_update':
        final m = _asMap(p);
        final name = m?['username'];
        final status = m?['status'];
        if (name is String && status is String) _setStatus(name, status);
      case 'users_list':
        if (p is List) {
          for (final item in p) {
            final m = _asMap(item);
            if (m != null) {
              final u = User.fromJson(m);
              if (u.username.isNotEmpty) _setStatus(u.username, u.status);
            }
          }
        }
      case 'avatar_changed':
        final m = _asMap(p);
        final name = m?['username'];
        final avatar = m?['avatar'];
        if (name is String) {
          final u = users[name];
          if (u != null) {
            final pic = avatar is String ? avatar : '';
            users[name] = pic.isEmpty ? u.copyWith(clearAvatar: true) : u.copyWith(avatar: pic);
            notifyListeners();
          }
        }
    }
  }

  void _setStatus(String name, String status) {
    final u = users[name];
    if (u == null) {
      users[name] = User(username: name, status: status);
    } else if (u.status != status) {
      users[name] = u.copyWith(status: status);
    } else {
      return;
    }
    notifyListeners();
  }

  void _onChannelCreated(Channel c) {
    if (c.name.isEmpty) return;
    if (c.isDm) {
      if (c.members.contains(me) && !dms.any((x) => x.name == c.name)) dms = [...dms, c];
    } else if (!c.isPrivate || c.members.contains(me)) {
      if (!channels.any((x) => x.name == c.name)) channels = _sortedChannels([...channels, c]);
    }
    notifyListeners();
  }

  void _onIncoming(String channel, Message m) {
    final f = _feeds[channel];
    final existed = f != null && f.messages.any((x) => x.id == m.id);

    if (f != null) {
      if (m.user == me && !existed) {
        // The server's copy of something this phone just sent: swap the
        // placeholder for it so it does not show twice (and keep the bubble).
        final i = f.messages.indexWhere((x) => x.sendState == SendState.sending && x.text == m.text);
        if (i >= 0) {
          m = m.copyWith(clientId: f.messages[i].clientId);
          f.messages.removeAt(i);
        }
      }
      _put(f, m);
      _sort(f);
    }
    _rememberLast(channel, m);

    if (!existed && m.user != me) {
      if (channel == active) {
        _markRead(channel);
      } else {
        unread[channel] = (unread[channel] ?? 0) + 1;
        if (!_notices.isClosed) _notices.add(Notice(m, titleOf(channel)));
      }
    }

    if (channelNamed(channel) == null) unawaited(refreshLists());
    notifyListeners();
  }
}
