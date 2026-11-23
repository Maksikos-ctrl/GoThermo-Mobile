import 'package:flutter/material.dart';

import 'app.dart';
import 'cache/sqlite_cache.dart';
import 'state/session_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(GoThermoApp(store: PlatformSessionStore(), cacheOpener: SqliteCache.open));
}
