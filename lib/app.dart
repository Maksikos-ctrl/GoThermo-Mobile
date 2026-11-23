import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api/socket.dart';
import 'screens/admin_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/app_controller.dart';
import 'state/chat_controller.dart';
import 'state/google_auth.dart';
import 'state/session_store.dart';
import 'theme.dart';
import 'widgets/avatar.dart';

class GoThermoApp extends StatefulWidget {
  const GoThermoApp({
    super.key,
    required this.store,
    this.httpClient,
    this.connector,
    this.googleAuth,
  });

  final SessionStore store;
  final http.Client? httpClient;
  final SocketConnector? connector;
  final GoogleAuth? googleAuth;

  @override
  State<GoThermoApp> createState() => _GoThermoAppState();
}

class _GoThermoAppState extends State<GoThermoApp> with WidgetsBindingObserver {
  late final AppController _controller = AppController(
    store: widget.store,
    httpClient: widget.httpClient,
    connector: widget.connector,
    google: widget.googleAuth,
  );
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller.resumed();
  }

  Widget _home() {
    switch (_controller.state) {
      case AuthState.starting:
        return const Scaffold(
          key: ValueKey('starting'),
          body: Center(child: CircularProgressIndicator()),
        );
      case AuthState.signedOut:
        return LoginScreen(key: const ValueKey('login'), controller: _controller);
      case AuthState.signedIn:
        final chat = _controller.chat;
        if (chat == null) return AdminScreen(key: const ValueKey('admin'), controller: _controller);
        return HomeScreen(key: ValueKey(chat), app: _controller, chat: chat);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoThermo',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      navigatorKey: _navigator,
      builder: (context, child) => NoticeHost(
        app: _controller,
        navigator: _navigator,
        child: child ?? const SizedBox.shrink(),
      ),
      home: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _home(),
        ),
      ),
    );
  }
}

/// Slides a banner in from the top when a message arrives in a conversation
/// you are not looking at. Tap it to open that conversation.
class NoticeHost extends StatefulWidget {
  const NoticeHost({super.key, required this.app, required this.navigator, required this.child});

  final AppController app;
  final GlobalKey<NavigatorState> navigator;
  final Widget child;

  @override
  State<NoticeHost> createState() => _NoticeHostState();
}

class _NoticeHostState extends State<NoticeHost> {
  StreamSubscription<Notice>? _sub;
  ChatController? _watching;
  Notice? _shown;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_rewire);
    _rewire();
  }

  @override
  void dispose() {
    widget.app.removeListener(_rewire);
    _sub?.cancel();
    _hide?.cancel();
    super.dispose();
  }

  void _rewire() {
    final chat = widget.app.chat;
    if (identical(chat, _watching)) return;
    _sub?.cancel();
    _watching = chat;
    _sub = chat?.notices.listen(_show);
    if (chat == null && _shown != null) {
      _hide?.cancel();
      if (mounted) setState(() => _shown = null);
    }
  }

  void _show(Notice n) {
    if (!mounted) return;
    setState(() => _shown = n);
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _shown = null);
    });
  }

  void _open(Notice n) {
    final chat = _watching;
    setState(() => _shown = null);
    if (chat == null) return;
    widget.navigator.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => ChatScreen(chat: chat, channel: n.message.channel)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = _shown;
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: n == null
                  ? const SizedBox.shrink(key: ValueKey('none'))
                  : Padding(
                      key: ValueKey(n.message.id),
                      padding: const EdgeInsets.all(10),
                      child: Material(
                        color: Palette.bgTertiary,
                        elevation: 6,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          key: const Key('notice'),
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _open(n),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Avatar(
                                  username: n.message.user,
                                  picture: _watching?.avatarOf(n.message.user),
                                  size: 36,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${n.message.user} · ${n.title}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                                      ),
                                      Text(
                                        n.message.isFile ? 'Sent a file' : n.message.text.replaceAll('\n', ' '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Palette.textMuted, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
