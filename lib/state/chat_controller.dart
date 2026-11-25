import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../api/gothermo_api.dart';
import '../api/rpc_client.dart';
import '../api/socket.dart';
import '../cache/local_cache.dart';
import '../models/channel.dart';
import '../models/extras.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../util/mime.dart';
import 'call_controller.dart';

/// The messages of one channel as far as this phone has loaded them.
class ChannelFeed {
  final List<Message> messages = [];
  bool loaded = false;

  /// The saved copy of this channel was already put on screen.
  bool restored = false;
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
    Future<LocalCache> Function()? openCache,
    this.pollEvery = const Duration(seconds: 8),
  })  : _connector = connector ?? const WebSocketConnector(),
        _openCache = openCache,
        _now = clock ?? DateTime.now;

  final GoThermoApi api;
  final Session session;
  final String serverUrl;
  final Duration pollEvery;
  final SocketConnector _connector;
  final DateTime Function() _now;
  final Future<LocalCache> Function()? _openCache;
  LocalCache? _cache;
  Future<void>? _cacheReady;

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

  /// Set by the app so a conversation screen can start a call.
  CallController? calls;

  /// The channel on screen right now, if any.
  String? active;

  /// False while the app is in the background: nothing counts as "being read",
  /// so new messages raise notices (and a phone notification).
  bool foreground = true;

  Stream<Notice> get notices => _notices.stream;

  /// Call signals from other people (offers, answers, candidates, hang-ups).
  Stream<SocketEvent> get signals => _signals.stream;
  final StreamController<SocketEvent> _signals = StreamController<SocketEvent>.broadcast();

  /// Sends a call signal to another person through the server.
  void sendSignal(String type, Map<String, dynamic> payload) => _sendFrame(type, payload);
  final StreamController<Notice> _notices = StreamController<Notice>.broadcast();

  int get totalUnread => unread.values.fold(0, (a, b) => a + b);

  User? userOf(String name) => users[name];
  String? avatarOf(String name) => users[name]?.avatar;
  String statusOf(String name) => users[name]?.status ?? 'offline';

  /// Lower-case names of everybody, for highlighting @mentions.
  Set<String> get knownNames => {for (final u in users.values) u.username.toLowerCase(), me.toLowerCase()};

  /// Names offered when someone types "@".
  List<String> get mentionable => [for (final u in people) u.username];

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
    _typingTimer?.cancel();
    _sub?.cancel();
    _conn?.close();
    _notices.close();
    _signals.close();
    super.dispose();
  }

  // ---- starting ------------------------------------------------------------

  Future<void> start() async {
    await _prepareCache();
    await _restoreLists();
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
      _guard(() async {
        channels = _sortedChannels(await api.channels(token));
        _save('channels', [for (final c in channels) c.toJson()]);
      }),
      _guard(() async {
        dms = await api.dmChannels(token, me);
        _save('dms', [for (final c in dms) c.toJson()]);
      }),
      _guard(() async {
        _setUsers(await api.users(token));
        _save('users', [for (final u in users.values) u.toJson()]);
      }),
      _guard(() async {
        unread
          ..clear()
          ..addAll(await api.unreadCounts(token, me));
        if (active != null) unread[active!] = 0;
        _save('unread', unread);
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
    await _restoreFeed(channel);
    unawaited(loadPins(channel));
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
      _forgetGone(channel, page.messages);
      _merge(channel, page.messages);
      _remember(channel, page.messages);
      if (!f.loaded) f.hasMore = page.hasMore ?? page.messages.length >= pageSize;
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
      _merge(channel, page.messages);
      _remember(channel, page.messages);
      f.hasMore = page.hasMore ?? page.messages.length >= pageSize;
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

  // ---- pins, threads and decisions ------------------------------------------------------

  Future<String?> _try(Future<void> Function() body) async {
    try {
      await body();
      return null;
    } on RpcException catch (e) {
      return e.message;
    }
  }

  final Map<String, List<Pin>> _pins = {};

  List<Pin> pinsOf(String channel) => List.unmodifiable(_pins[channel] ?? const <Pin>[]);

  bool isPinned(String channel, String messageId) =>
      (_pins[channel] ?? const <Pin>[]).any((p) => p.message.id == messageId);

  Future<String?> loadPins(String channel) => _try(() async {
        _pins[channel] = await api.pins(token, channel);
        notifyListeners();
      });

  Future<String?> pin(Message m) => _try(() async {
        await api.pinMessage(token, m.channel, m.id, me);
        await loadPins(m.channel);
      });

  Future<String?> unpin(Message m) => _try(() async {
        await api.unpinMessage(token, m.channel, m.id, me);
        await loadPins(m.channel);
      });

  final Map<String, ThreadData> _threads = {};

  String _threadKey(String channel, String parentId) => '$channel|$parentId';

  ThreadData? threadOf(String channel, String parentId) => _threads[_threadKey(channel, parentId)];

  Future<String?> loadThread(String channel, String parentId) => _try(() async {
        _threads[_threadKey(channel, parentId)] = await api.thread(token, channel, parentId);
        notifyListeners();
      });

  Future<String?> reply(Message parent, String text) {
    final body = text.trim();
    if (body.isEmpty) return Future.value(null);
    return _try(() async {
      final sent = await api.sendReply(token, me, parent.channel, parent.id, body);
      _addReply(parent.channel, parent.id, sent);
    });
  }

  Future<String?> deleteReply(Message reply) => _try(() async {
        await api.deleteReply(token, reply.channel, reply.threadId, reply.id, me);
        _dropReply(reply.channel, reply.threadId, reply.id);
      });

  /// A reply arrived (or changed: edited, reacted to). The same id replaces
  /// the old copy in place, so our own reply never shows twice.
  void _addReply(String channel, String parentId, Message reply) {
    final key = _threadKey(channel, parentId);
    final t = _threads[key];
    if (t == null) return;
    final i = t.replies.indexWhere((r) => r.id == reply.id);
    final list = [...t.replies];
    if (i < 0) {
      list.add(reply);
    } else {
      list[i] = reply;
    }
    _threads[key] = ThreadData(parent: t.parent, replies: list);
    notifyListeners();
  }

  Future<String?> editReply(Message reply, String newText) {
    final text = newText.trim();
    if (text.isEmpty || text == reply.text) return Future.value(null);
    return _try(() async {
      final updated = await api.editReply(token, reply.channel, reply.threadId, reply.id, me, text);
      _addReply(reply.channel, reply.threadId, updated);
    });
  }

  Future<String?> reactToReply(Message reply, String emoji) async {
    final before = reply.reactions;
    _addReply(reply.channel, reply.threadId, reply.copyWith(reactions: toggledReactions(before, emoji, me)));
    try {
      await api.reactToReply(token, reply.channel, reply.threadId, reply.id, emoji, me);
      return null;
    } on RpcException catch (e) {
      _addReply(reply.channel, reply.threadId, reply.copyWith(reactions: before));
      return e.message;
    }
  }

  /// Tells the admins about a message (see [reportReasons]).
  Future<String?> report(Message m, String reason) => _try(() => api.reportMessage(token, me, m.channel, m.id, reason));

  void _dropReply(String channel, String parentId, String id) {
    final key = _threadKey(channel, parentId);
    final t = _threads[key];
    if (t == null) return;
    _threads[key] = ThreadData(parent: t.parent, replies: t.replies.where((r) => r.id != id).toList());
    notifyListeners();
  }

  final Map<String, List<Decision>> _decisions = {};

  List<Decision> decisionsOf(String channel) => List.unmodifiable(_decisions[channel] ?? const <Decision>[]);

  Decision? decisionFor(String channel, String messageId) {
    for (final d in _decisions[channel] ?? const <Decision>[]) {
      if (d.messageId == messageId) return d;
    }
    return null;
  }

  Future<String?> loadDecisions(String channel) => _try(() async {
        _decisions[channel] = await api.decisions(token, channel);
        notifyListeners();
      });

  /// [kind] is `decision` or `task`.
  Future<String?> markDecision(Message m, String kind) => _try(() async {
        await api.markDecision(token, me, m.channel, m.id, kind);
        await loadDecisions(m.channel);
      });

  Future<String?> setDecisionDone(Decision d, bool done) async {
    final list = _decisions[d.channel];
    final before = list;
    if (list != null) {
      _decisions[d.channel] = [for (final x in list) x.messageId == d.messageId ? x.copyWith(done: done, doneBy: done ? me : '') : x];
      notifyListeners();
    }
    final err = await _try(() => api.setDecisionDone(token, me, d.channel, d.messageId, done));
    if (err != null && before != null) {
      _decisions[d.channel] = before;
      notifyListeners();
    }
    return err;
  }

  Future<String?> removeDecision(Decision d) => _try(() async {
        await api.removeDecision(token, me, d.channel, d.messageId);
        _decisions[d.channel] = (_decisions[d.channel] ?? const <Decision>[]).where((x) => x.messageId != d.messageId).toList();
        notifyListeners();
      });

  // ---- the offline copy ------------------------------------------------------------

  Future<void> _prepareCache() => _cacheReady ??= () async {
        final open = _openCache;
        if (open == null) return;
        try {
          _cache = GuardedCache(await open());
        } on Object {
          _cache = null; // no offline copy this time; the app works as before
        }
      }();

  void _save(String key, Object? value) => unawaited(_cache?.writeValue(key, value));

  List<Map<String, dynamic>> _maps(Object? v) =>
      v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

  /// Channels, people and last messages from the last run, so the lists show
  /// at once and still show something with no connection.
  Future<void> _restoreLists() async {
    final cache = _cache;
    if (cache == null) return;
    final ch = _maps(await cache.readValue('channels')).map(Channel.fromJson).toList();
    final dm = _maps(await cache.readValue('dms')).map(Channel.fromJson).toList();
    if (ch.isEmpty && dm.isEmpty) return;
    channels = _sortedChannels(ch);
    dms = dm;
    for (final u in _maps(await cache.readValue('users')).map(User.fromJson)) {
      // Whether somebody is online now is only known from the server.
      users[u.username] = u.copyWith(status: 'offline');
    }
    final counts = await cache.readValue('unread');
    if (counts is Map) {
      counts.forEach((k, v) {
        if (k is String && v is num) unread[k] = v.toInt();
      });
    }
    await Future.wait([
      for (final c in [...channels, ...dms])
        () async {
          final last = _maps(await cache.readMessages(c.name, limit: 1));
          if (last.isNotEmpty) _rememberLast(c.name, Message.fromJson(last.first));
        }(),
    ]);
    await _restoreOutbox();
    started = true;
    notifyListeners();
  }

  /// The cached messages of a channel go on screen before the server answers.
  Future<void> _restoreFeed(String channel) async {
    final cache = _cache;
    final f = feed(channel);
    if (cache == null || f.loaded || f.restored) return;
    f.restored = true;
    final saved = _maps(await cache.readMessages(channel));
    if (saved.isEmpty) return;
    for (final j in saved) {
      _put(f, Message.fromJson(j));
    }
    _sort(f);
    _rememberLast(channel, f.messages.last);
    notifyListeners();
  }

  void _remember(String channel, Iterable<Message> list) {
    final cache = _cache;
    if (cache == null) return;
    final items = [
      for (final m in list)
        if (m.sendState == SendState.sent && m.id.isNotEmpty && !m.id.startsWith('local-'))
          CachedMessage(m.id, m.timestamp.millisecondsSinceEpoch, m.toJson()),
    ];
    if (items.isNotEmpty) unawaited(cache.putMessages(channel, items));
  }

  /// Messages deleted while this phone was away: inside the time the fresh page
  /// covers, whatever the server no longer lists is gone.
  void _forgetGone(String channel, List<Message> page) {
    if (page.isEmpty) return;
    final f = feed(channel);
    final ids = page.map((m) => m.id).toSet();
    final from = page.map((m) => m.timestamp).reduce((a, b) => a.isBefore(b) ? a : b);
    final recent = _now().subtract(const Duration(seconds: 30));
    final gone = f.messages
        .where((m) =>
            m.sendState == SendState.sent &&
            !ids.contains(m.id) &&
            !m.timestamp.isBefore(from) &&
            m.timestamp.isBefore(recent))
        .map((m) => m.id)
        .toList();
    for (final id in gone) {
      f.messages.removeWhere((m) => m.id == id);
      unawaited(_cache?.deleteMessage(channel, id));
    }
  }

  /// Signing out: nothing of this account stays on the phone.
  Future<void> wipeCache() async {
    await _prepareCache();
    final cache = _cache;
    _cache = null; // nothing is written after this
    await cache?.clear();
  }

  // ---- who is typing ---------------------------------------------------------------

  static const typingTtl = Duration(seconds: 5);
  static const typingGap = Duration(seconds: 3);
  final Map<String, Map<String, DateTime>> _typing = {};
  Timer? _typingTimer;
  String _typingSentIn = '';
  DateTime? _typingSentAt;

  /// Other people typing in [channel] right now, by name.
  List<String> typingIn(String channel) {
    final now = _now();
    final names = (_typing[channel] ?? const <String, DateTime>{})
        .entries
        .where((e) => e.value.isAfter(now) && e.key != me)
        .map((e) => e.key)
        .toList()
      ..sort();
    return names;
  }

  /// Tells the others that this phone is typing (at most once every few seconds).
  void announceTyping(String channel) {
    final now = _now();
    final at = _typingSentAt;
    if (channel == _typingSentIn && at != null && now.difference(at) < typingGap) return;
    _typingSentIn = channel;
    _typingSentAt = now;
    _sendFrame('typing', channel);
  }

  void _noteTyping(String channel, String user) {
    if (user == me) return;
    (_typing[channel] ??= {})[user] = _now().add(typingTtl);
    _typingTimer ??= Timer.periodic(const Duration(seconds: 1), (_) => _pruneTyping());
    notifyListeners();
  }

  void _clearTyping(String channel, String user) {
    final inChannel = _typing[channel];
    if (inChannel == null || inChannel.remove(user) == null) return;
    if (inChannel.isEmpty) _typing.remove(channel);
  }

  void _pruneTyping() {
    final now = _now();
    var changed = false;
    for (final users in _typing.values) {
      final before = users.length;
      users.removeWhere((_, until) => !until.isAfter(now));
      if (users.length != before) changed = true;
    }
    _typing.removeWhere((_, users) => users.isEmpty);
    if (_typing.isEmpty) {
      _typingTimer?.cancel();
      _typingTimer = null;
    }
    if (changed) notifyListeners();
  }

  // ---- sending -----------------------------------------------------------------

  Future<void> send(String channel, String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final localId = 'local-${_now().microsecondsSinceEpoch}-${_localSeq++}';
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
    _saveOutbox();
    await _deliver(pending);
  }

  // Messages written with no connection wait here and go out, in order,
  // as soon as the server is reachable again.
  final Set<String> _inFlight = {};
  bool _flushing = false;

  Iterable<Message> get _waiting => [
        for (final f in _feeds.values)
          for (final m in f.messages)
            if (m.sendState == SendState.sending && m.id.startsWith('local-')) m,
      ];

  /// How many messages are waiting for a connection.
  int get waitingCount => _waiting.where((m) => !_inFlight.contains(m.id)).length;

  void _saveOutbox() => _save('outbox', [
        for (final m in _waiting) {'id': m.id, 'channel': m.channel, 'text': m.text, 'at': m.timestamp.millisecondsSinceEpoch},
      ]);

  Future<void> _restoreOutbox() async {
    final saved = await _cache?.readValue('outbox');
    if (saved is! List) return;
    for (final j in saved.whereType<Map<String, dynamic>>()) {
      final id = j['id'];
      final channel = j['channel'];
      final text = j['text'];
      final at = j['at'];
      if (id is! String || channel is! String || text is! String || at is! num) continue;
      final f = feed(channel);
      if (f.messages.any((m) => m.id == id)) continue;
      final m = Message(
        id: id,
        clientId: id,
        user: me,
        text: text,
        channel: channel,
        timestamp: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
        sendState: SendState.sending,
      );
      f.messages.add(m);
      _sort(f);
      _rememberLast(channel, m);
    }
  }

  /// Sends what is waiting, oldest first; stops at the first one that still
  /// cannot get through.
  Future<void> flushOutbox() async {
    if (_flushing || _disposed) return;
    _flushing = true;
    try {
      final queued = _waiting.where((m) => !_inFlight.contains(m.id)).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      for (final m in queued) {
        if (_disposed || !await _deliver(m)) break;
      }
    } finally {
      _flushing = false;
    }
  }

  /// False when the server could not be reached (the message keeps waiting).
  Future<bool> _deliver(Message pending) async {
    _inFlight.add(pending.id);
    try {
      final id = await api.sendMessage(token, me, pending.text, pending.channel);
      final f = feed(pending.channel);
      f.messages.removeWhere((m) => m.id == pending.id);
      if (id.isNotEmpty && !f.messages.any((m) => m.id == id)) {
        final sent = pending.copyWith(id: id, sendState: SendState.sent);
        f.messages.add(sent);
        _remember(pending.channel, [sent]);
      }
      _sort(f);
      _inFlight.remove(pending.id);
      _saveOutbox();
      notifyListeners();
      return true;
    } on RpcException catch (e) {
      _inFlight.remove(pending.id);
      if (e.unreachable) {
        // No connection: keep it, it goes out when the server is back.
        _saveOutbox();
        notifyListeners();
        return false;
      }
      _setState(pending, SendState.failed);
      error = e.message;
      _saveOutbox();
      notifyListeners();
      return true;
    }
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
    _saveOutbox();
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
      _remember(channel, [msg]);
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
      _remember(channel, [f.messages[i]]);
      notifyListeners();
    }
  }

  void _remove(String channel, String id) {
    final f = feed(channel);
    f.messages.removeWhere((x) => x.id == id);
    unawaited(_cache?.deleteMessage(channel, id));
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
      unawaited(flushOutbox());
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
    unawaited(flushOutbox());
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
    unawaited(flushOutbox());
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
      case 'call_offer':
      case 'call_answer':
      case 'call_ice_candidate':
      case 'call_reject':
      case 'call_end':
      case 'call_renegotiate_offer':
      case 'call_renegotiate_answer':
      case 'call_screen_share_status':
        if (!_signals.isClosed) _signals.add(e);
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
      case 'pins_changed':
        final m = _asMap(p);
        final channel = m?['channel'];
        final list = m?['pins'];
        if (channel is String) {
          _pins[channel] = list is List ? list.whereType<Map<String, dynamic>>().map(Pin.fromJson).toList() : <Pin>[];
          notifyListeners();
        }
      case 'thread_reply':
        final m = _asMap(p);
        final channel = m?['channel'];
        final thread = m?['threadId'];
        final raw = _asMap(m?['message']);
        if (channel is String && thread is String && raw != null) _addReply(channel, thread, Message.fromJson(raw));
      case 'thread_reply_deleted':
        final m = _asMap(p);
        final channel = m?['channel'];
        final thread = m?['threadId'];
        final id = m?['messageId'];
        if (channel is String && thread is String && id is String) _dropReply(channel, thread, id);
      case 'typing':
        final m = _asMap(p);
        final channel = m?['channel'];
        final user = m?['username'];
        if (channel is String && user is String) _noteTyping(channel, user);
      case 'channel_created':
        final m = _asMap(p);
        if (m != null) _onChannelCreated(Channel.fromJson(m));
      case 'channel_deleted':
        final m = _asMap(p);
        final name = m?['channel'];
        if (name is String) _removeChannel(name);
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

  void _removeChannel(String name) {
    channels = channels.where((c) => c.name != name).toList();
    dms = dms.where((c) => c.name != name).toList();
    _feeds.remove(name);
    lastMessage.remove(name);
    unread.remove(name);
    notifyListeners();
  }

  /// Makes a channel. Returns it, or the reason it could not be made.
  Future<({Channel? channel, String? error})> createChannel({
    required String name,
    String description = '',
    bool isPrivate = false,
    List<String> members = const [],
  }) async {
    try {
      final c = await api.createChannel(token, name, description.trim(), me,
          isPrivate: isPrivate, members: isPrivate ? members : const []);
      _onChannelCreated(c);
      return (channel: c, error: null);
    } on RpcException catch (e) {
      return (channel: null, error: e.message);
    }
  }

  /// Leaves a private channel.
  Future<String?> leaveChannel(String name) => _try(() async {
        await api.leaveChannel(token, name, me);
        _removeChannel(name);
      });

  /// Deletes a channel you made.
  Future<String?> deleteChannel(String name) => _try(() async {
        await api.deleteChannel(token, name, me);
        _removeChannel(name);
      });

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
    _clearTyping(channel, m.user);
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
    _remember(channel, [m]);

    // A parent that gained a reply arrives again; that is an update, not news.
    final update = m.replyCount > 0 || m.threadId.isNotEmpty;
    if (!existed && !update && m.user != me) {
      if (channel == active && foreground) {
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
