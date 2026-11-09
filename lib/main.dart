import 'package:flutter/material.dart';

import 'app.dart';
import 'state/session_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(GoThermoApp(store: PlatformSessionStore()));
}
