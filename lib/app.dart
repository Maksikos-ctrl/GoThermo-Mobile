import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api/socket.dart';
import 'cache/local_cache.dart';
import 'calls/call_types.dart';
import 'screens/admin_screen.dart';
import 'screens/call_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/app_controller.dart';
import 'state/call_controller.dart';
import 'state/chat_controller.dart';
import 'state/google_auth.dart';
import 'state/session_store.dart';
import 'notifications/notifier.dart';
import 'state/theme_settings.dart';
import 'theme.dart';
import 'widgets/avatar.dart';
import 'widgets/toast.dart';

class GoThermoApp extends StatefulWidget {
  const GoThermoApp({
    super.key,
    required this.store,
    this.httpClient,
    this.connector,
    this.googleAuth,
    this.callEngine,
    this.callTones,
    this.cacheOpener,
    this.notifier,
  });

  final SessionStore store;
  final http.Client? httpClient;
  final SocketConnector? connector;
  final GoogleAuth? googleAuth;
  final CallEngine? callEngine;

  /// Opens the offline copy of one account's chats; null keeps nothing on the phone.
  final Future<LocalCache> Function(String owner)? cacheOpener;
  final CallTones? callTones;

  /// Shows phone notifications; null keeps them off.
  final Notifier? notifier;

  @override
  State<GoThermoApp> createState() => _GoThermoAppState();
}

class _GoThermoAppState extends State<GoThermoApp> with WidgetsBindingObserver {
  late final AppController _controller = AppController(
    store: widget.store,
    httpClient: widget.httpClient,
    connector: widget.connector,
    google: widget.googleAuth,
    callEngine: widget.callEngine,
    callTones: widget.callTones,
    cacheOpener: widget.cacheOpener,
    notifier: widget.notifier,
  );
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyPalette();
    _controller.theme.addListener(_themeChanged);
    _controller.start();
    unawaited(_controller.setUpNotifications());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.theme.removeListener(_themeChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.resumed();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _controller.paused();
    }
  }

  @override
  void didChangePlatformBrightness() {
    if (_controller.theme.mode == ThemeSettings.systemMode) _themeChanged();
  }

  /// Puts the chosen colours into [Palette] (the screens read them from there).
  void _applyPalette() {
    final settings = _controller.theme;
    final system = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    Palette.apply(resolveColors(settings.mode, system), accentChoices[settings.accent]);
  }

  /// Colours changed: update them and rebuild everything on screen, including
  /// screens that are already open under the current one.
  void _themeChanged() {
    if (!mounted) return;
    _applyPalette();
    setState(() {});
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    (context as Element).visitChildren(mark);
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
      builder: (context, child) {
        final scale = _controller.theme.textScale;
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: scale == 1.0 ? media : media.copyWith(textScaler: TextScaler.linear(scale)),
          child: CallHost(
            app: _controller,
            navigator: _navigator,
            child: NoticeHost(
              app: _controller,
              navigator: _navigator,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
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
  StreamSubscription<String>? _opens;
  ChatController? _watching;
  Notice? _shown;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_rewire);
    _opens = widget.app.opens.listen(_openChannel);
    _rewire();
  }

  @override
  void dispose() {
    widget.app.removeListener(_rewire);
    _opens?.cancel();
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
    setState(() => _shown = null);
    _openChannel(n.message.channel);
  }

  void _openChannel(String channel) {
    final chat = _watching;
    if (chat == null) return;
    widget.navigator.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => ChatScreen(chat: chat, channel: channel)),
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
                                        style: TextStyle(color: Palette.textMuted, fontSize: 13),
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

/// Opens the call screen when a call starts or comes in, and shows what went
/// wrong when one fails.
class CallHost extends StatefulWidget {
  const CallHost({super.key, required this.app, required this.navigator, required this.child});

  final AppController app;
  final GlobalKey<NavigatorState> navigator;
  final Widget child;

  @override
  State<CallHost> createState() => _CallHostState();
}

class _CallHostState extends State<CallHost> {
  CallController? _watching;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_rewire);
    _rewire();
  }

  @override
  void dispose() {
    widget.app.removeListener(_rewire);
    _watching?.removeListener(_onCall);
    super.dispose();
  }

  void _rewire() {
    final call = widget.app.call;
    if (identical(call, _watching)) return;
    _watching?.removeListener(_onCall);
    _watching = call;
    call?.addListener(_onCall);
  }

  void _onCall() {
    final call = _watching;
    final chat = widget.app.chat;
    if (call == null || chat == null) return;
    if (call.phase != CallPhase.idle && !_open) {
      _open = true;
      widget.navigator.currentState
          ?.push(
            PageRouteBuilder<void>(
              opaque: true,
              transitionDuration: const Duration(milliseconds: 250),
              pageBuilder: (_, __, ___) => CallScreen(call: call, chat: chat),
              transitionsBuilder: (_, animation, __, page) => FadeTransition(opacity: animation, child: page),
            ),
          )
          .whenComplete(() => _open = false);
    }
    final message = call.error;
    if (message != null) {
      call.clearError();
      final context = widget.navigator.currentContext;
      if (context != null) showToast(context, message);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
