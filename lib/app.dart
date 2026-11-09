import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'screens/channels_screen.dart';
import 'screens/login_screen.dart';
import 'state/app_controller.dart';
import 'state/session_store.dart';
import 'theme.dart';

class GoThermoApp extends StatefulWidget {
  const GoThermoApp({super.key, required this.store, this.httpClient});

  final SessionStore store;
  final http.Client? httpClient;

  @override
  State<GoThermoApp> createState() => _GoThermoAppState();
}

class _GoThermoAppState extends State<GoThermoApp> {
  late final AppController _controller =
      AppController(store: widget.store, httpClient: widget.httpClient);

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoThermo',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          switch (_controller.state) {
            case AuthState.starting:
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            case AuthState.signedOut:
              return LoginScreen(controller: _controller);
            case AuthState.signedIn:
              return ChannelsScreen(controller: _controller);
          }
        },
      ),
    );
  }
}
