import 'dart:convert';

/// How many messages of one channel the phone keeps for offline reading.
const int cacheKeepPerChannel = 200;

/// One message as it is stored: its place in the channel plus its JSON.
class CachedMessage {
  const CachedMessage(this.id, this.at, this.json);

  final String id;

  /// When it was sent, in milliseconds since 1970 (for ordering).
  final int at;
  final Map<String, dynamic> json;
}

/// What the phone remembers between runs, so chats open at once and can be
/// read without a connection. The server stays the single source of truth.
abstract class LocalCache {
  /// Small named values: the channel list, people, unread counts.
  Future<Object?> readValue(String key);
  Future<void> writeValue(String key, Object? json);

  /// The newest [limit] messages of a channel, oldest first.
  Future<List<Map<String, dynamic>>> readMessages(String channel, {int limit = cacheKeepPerChannel});

  /// Adds or replaces messages (matched by id) and keeps only the newest
  /// [cacheKeepPerChannel] of the channel.
  Future<void> putMessages(String channel, List<CachedMessage> items);
  Future<void> deleteMessage(String channel, String id);

  /// Forgets everything (signing out).
  Future<void> clear();
}

/// Keeps everything in memory; used by tests and as the fallback.
class MemoryCache implements LocalCache {
  final Map<String, String> _values = {};
  final Map<String, Map<String, CachedMessage>> _messages = {};

  @override
  Future<Object?> readValue(String key) async {
    final v = _values[key];
    return v == null ? null : jsonDecode(v);
  }

  @override
  Future<void> writeValue(String key, Object? json) async => _values[key] = jsonEncode(json);

  List<CachedMessage> _sorted(String channel) {
    final list = (_messages[channel] ?? const <String, CachedMessage>{}).values.toList()
      ..sort((a, b) {
        final c = a.at.compareTo(b.at);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return list;
  }

  @override
  Future<List<Map<String, dynamic>>> readMessages(String channel, {int limit = cacheKeepPerChannel}) async {
    final list = _sorted(channel);
    final from = list.length > limit ? list.length - limit : 0;
    return [for (final m in list.sublist(from)) jsonDecode(jsonEncode(m.json)) as Map<String, dynamic>];
  }

  @override
  Future<void> putMessages(String channel, List<CachedMessage> items) async {
    final map = _messages[channel] ??= {};
    for (final m in items) {
      map[m.id] = m;
    }
    final list = _sorted(channel);
    if (list.length > cacheKeepPerChannel) {
      for (final m in list.sublist(0, list.length - cacheKeepPerChannel)) {
        map.remove(m.id);
      }
    }
  }

  @override
  Future<void> deleteMessage(String channel, String id) async => _messages[channel]?.remove(id);

  @override
  Future<void> clear() async {
    _values.clear();
    _messages.clear();
  }
}

/// Wraps a cache so that a broken disk or database can never break the app:
/// every failure just means "nothing cached".
class GuardedCache implements LocalCache {
  GuardedCache(this._inner);

  final LocalCache _inner;

  Future<T> _safe<T>(Future<T> Function() run, T fallback) async {
    try {
      return await run();
    } on Object {
      return fallback;
    }
  }

  @override
  Future<Object?> readValue(String key) => _safe(() => _inner.readValue(key), null);

  @override
  Future<void> writeValue(String key, Object? json) => _safe(() => _inner.writeValue(key, json), null);

  @override
  Future<List<Map<String, dynamic>>> readMessages(String channel, {int limit = cacheKeepPerChannel}) =>
      _safe(() => _inner.readMessages(channel, limit: limit), const <Map<String, dynamic>>[]);

  @override
  Future<void> putMessages(String channel, List<CachedMessage> items) =>
      _safe(() => _inner.putMessages(channel, items), null);

  @override
  Future<void> deleteMessage(String channel, String id) => _safe(() => _inner.deleteMessage(channel, id), null);

  @override
  Future<void> clear() => _safe(() => _inner.clear(), null);
}
