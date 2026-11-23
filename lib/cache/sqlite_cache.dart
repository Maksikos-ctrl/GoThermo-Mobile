import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'local_cache.dart';

/// The phone's offline copy, in one SQLite file. Rows are tagged with an
/// owner (server + user), so two accounts never see each other's chats.
class SqliteCache implements LocalCache {
  SqliteCache._(this._db, this._owner);

  final Database _db;
  final String _owner;

  static Future<SqliteCache> open(String owner) async {
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      '$dir/gothermo_cache.db',
      version: 1,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE kv ('
            'owner TEXT NOT NULL, k TEXT NOT NULL, v TEXT NOT NULL, PRIMARY KEY (owner, k))');
        await db.execute('CREATE TABLE msgs ('
            'owner TEXT NOT NULL, channel TEXT NOT NULL, id TEXT NOT NULL, '
            'at INTEGER NOT NULL, json TEXT NOT NULL, PRIMARY KEY (owner, channel, id))');
        await db.execute('CREATE INDEX msgs_by_time ON msgs (owner, channel, at)');
      },
    );
    return SqliteCache._(db, owner);
  }

  @override
  Future<Object?> readValue(String key) async {
    final rows = await _db.query('kv', columns: ['v'], where: 'owner = ? AND k = ?', whereArgs: [_owner, key]);
    return rows.isEmpty ? null : jsonDecode(rows.first['v']! as String);
  }

  @override
  Future<void> writeValue(String key, Object? json) => _db.insert(
        'kv',
        {'owner': _owner, 'k': key, 'v': jsonEncode(json)},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  @override
  Future<List<Map<String, dynamic>>> readMessages(String channel, {int limit = cacheKeepPerChannel}) async {
    final rows = await _db.query(
      'msgs',
      columns: ['json'],
      where: 'owner = ? AND channel = ?',
      whereArgs: [_owner, channel],
      orderBy: 'at DESC, id DESC',
      limit: limit,
    );
    final out = <Map<String, dynamic>>[];
    for (final r in rows.reversed) {
      final j = jsonDecode(r['json']! as String);
      if (j is Map<String, dynamic>) out.add(j);
    }
    return out;
  }

  @override
  Future<void> putMessages(String channel, List<CachedMessage> items) async {
    if (items.isEmpty) return;
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final m in items) {
        batch.insert(
          'msgs',
          {'owner': _owner, 'channel': channel, 'id': m.id, 'at': m.at, 'json': jsonEncode(m.json)},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      batch.rawDelete(
        'DELETE FROM msgs WHERE owner = ? AND channel = ? AND id NOT IN ('
        'SELECT id FROM msgs WHERE owner = ? AND channel = ? ORDER BY at DESC, id DESC LIMIT ?)',
        [_owner, channel, _owner, channel, cacheKeepPerChannel],
      );
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> deleteMessage(String channel, String id) =>
      _db.delete('msgs', where: 'owner = ? AND channel = ? AND id = ?', whereArgs: [_owner, channel, id]);

  @override
  Future<void> clear() async {
    await _db.delete('kv', where: 'owner = ?', whereArgs: [_owner]);
    await _db.delete('msgs', where: 'owner = ?', whereArgs: [_owner]);
  }
}
