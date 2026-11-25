import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/app.dart';
import 'package:gothermo_mobile/calls/call_types.dart';
import 'package:gothermo_mobile/state/google_auth.dart';
import 'package:gothermo_mobile/state/session_store.dart';
import 'package:gothermo_mobile/theme.dart';

import 'support/call_fakes.dart';
import 'support/fakes.dart';

Future<void> launch(
  WidgetTester tester, {
  required FakeServer server,
  MemorySessionStore? store,
  FakeGoogleAuth? google,
  FakeConnector? connector,
  FakeEngine? engine,
}) async {
  await tester.pumpWidget(GoThermoApp(
    store: store ?? MemorySessionStore(),
    httpClient: server.client,
    connector: connector ?? FakeConnector(),
    googleAuth: google ?? FakeGoogleAuth(),
    callEngine: engine ?? FakeEngine(),
    callTones: SilentTones(),
  ));
  await tester.pumpAndSettle();
}

/// Removes the app so its timers stop before the test ends.
Future<void> close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

Future<void> signIn(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('email')), 'ann@x.io');
  await tester.enterText(find.byKey(const Key('password')), 'right-pw');
  await tester.tap(find.byKey(const Key('submit')));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => Palette.apply(midnightColors, accentChoices.first));

  testWidgets('shows the sign-in screen when nobody is signed in', (tester) async {
    await launch(tester, server: FakeServer());
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byKey(const Key('email')), findsOneWidget);
    expect(find.byKey(const Key('google')), findsOneWidget);
    await close(tester);
  });

  testWidgets('a wrong password shows the server message', (tester) async {
    final server = FakeServer()..loginError = 'incorrect email or password';
    await launch(tester, server: server);
    await signIn(tester);
    expect(find.text('incorrect email or password'), findsOneWidget);
    await close(tester);
  });

  testWidgets('signing in lists channels, signing out goes back', (tester) async {
    final store = MemorySessionStore();
    await launch(tester, server: FakeServer(), store: store);
    await signIn(tester);

    expect(find.text('general'), findsOneWidget);
    expect(find.text('random'), findsOneWidget);
    expect(store.token, 'tok');

    await tester.tap(find.byKey(const Key('profile-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(store.token, isNull);
    await close(tester);
  });

  testWidgets('Google sign-in works and a closed window does nothing', (tester) async {
    final google = FakeGoogleAuth();
    final store = MemorySessionStore();
    await launch(tester, server: FakeServer(), store: store, google: google);

    await tester.tap(find.byKey(const Key('google')));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(store.token, isNull);

    google.token = 'google-access';
    await tester.tap(find.byKey(const Key('google')));
    await tester.pumpAndSettle();
    expect(find.text('general'), findsOneWidget);
    expect(store.token, 'tok');
    await close(tester);
  });

  testWidgets('a saved token signs in without asking', (tester) async {
    await launch(tester, server: FakeServer(), store: MemorySessionStore(token: 'saved'));
    expect(find.text('general'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a saved token the server refuses is dropped', (tester) async {
    final store = MemorySessionStore(token: 'expired');
    await launch(tester, server: FakeServer(), store: store);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(store.token, isNull);
    await close(tester);
  });

  testWidgets('the Direct tab lists conversations', (tester) async {
    await launch(tester, server: FakeServer(), store: MemorySessionStore(token: 'saved'));
    await tester.tap(find.text('Direct'));
    await tester.pumpAndSettle();
    expect(find.text('bob'), findsOneWidget);
    await close(tester);
  });

  testWidgets('opening a channel shows its messages and sending adds one', (tester) async {
    final server = FakeServer()
      ..messages['general'] = [msgJson('1', 'bob', 'hello from bob')];
    await launch(tester, server: server, store: MemorySessionStore(token: 'saved'));
    await tester.tap(find.text('general'));
    await tester.pumpAndSettle();
    expect(find.text('hello from bob'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('message-field')), 'hi there');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send')));
    await tester.pumpAndSettle();
    expect(server.lastSentText, 'hi there');
    expect(find.text('hi there'), findsOneWidget);
    await close(tester);
  });

  testWidgets('the Appearance screen switches the theme and remembers it', (tester) async {
    final store = MemorySessionStore(token: 'saved');
    await launch(tester, server: FakeServer(), store: store);

    await tester.tap(find.byKey(const Key('profile-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appearance')));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsWidgets);

    await tester.tap(find.byKey(const Key('theme-light')));
    await tester.pumpAndSettle();
    expect(Palette.brightness, Brightness.light);
    expect(store.prefs['theme.mode'], 'light');

    await tester.tap(find.byKey(const Key('accent-2')));
    await tester.pumpAndSettle();
    expect(Palette.accent, accentChoices[2]);
    await close(tester);
  });

  testWidgets('an incoming call opens the call screen; answering and hanging up work', (tester) async {
    final connector = FakeConnector();
    final engine = FakeEngine();
    await launch(tester, server: FakeServer(), store: MemorySessionStore(token: 'saved'), connector: connector, engine: engine);

    connector.current.push('call_offer', {
      'to': 'ann',
      'from': 'bob',
      'sdp': {'type': 'offer', 'sdp': 'theirs'},
    });
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Incoming voice call'), findsOneWidget);
    expect(find.byKey(const Key('call-accept')), findsOneWidget);

    await tester.tap(find.byKey(const Key('call-accept')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(connector.current.sent.any((f) => f['type'] == 'call_answer'), isTrue);
    expect(find.text('Connecting...'), findsOneWidget);

    engine.peer.states.add(PeerState.connected);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('call-end')), findsOneWidget);

    await tester.tap(find.byKey(const Key('call-end')));
    await tester.pumpAndSettle();
    expect(connector.current.sent.any((f) => f['type'] == 'call_end'), isTrue);
    expect(find.byKey(const Key('call-end')), findsNothing);
    expect(find.text('general'), findsOneWidget);
    await close(tester);
  });

  testWidgets('declining an incoming call sends a reject', (tester) async {
    final connector = FakeConnector();
    await launch(tester, server: FakeServer(), store: MemorySessionStore(token: 'saved'), connector: connector);
    connector.current.push('call_offer', {
      'to': 'ann',
      'from': 'bob',
      'sdp': {'type': 'offer', 'sdp': 'theirs'},
    });
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('call-decline')));
    await tester.pumpAndSettle();
    expect(connector.current.sent.any((f) => f['type'] == 'call_reject'), isTrue);
    expect(find.byKey(const Key('call-accept')), findsNothing);
    await close(tester);
  });

  testWidgets('the call button in a direct message starts a call', (tester) async {
    final connector = FakeConnector();
    final engine = FakeEngine();
    await launch(tester, server: FakeServer(), store: MemorySessionStore(token: 'saved'), connector: connector, engine: engine);

    await tester.tap(find.text('Direct'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('call-voice')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    final offer = connector.current.sent.lastWhere((f) => f['type'] == 'call_offer');
    expect((offer['payload'] as Map)['to'], 'bob');
    expect(find.text('Calling...'), findsOneWidget);

    await tester.tap(find.byKey(const Key('call-end')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('call-end')), findsNothing);
    await close(tester);
  });

  testWidgets('a message can be answered in a thread', (tester) async {
    final server = FakeServer()..messages['general'] = [msgJson('1', 'bob', 'hello from bob')];
    await launch(tester, server: server, store: MemorySessionStore(token: 'saved'));
    await tester.tap(find.text('general'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('hello from bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-thread')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('thread-field')), 'my reply');
    await tester.pump();
    await tester.tap(find.byKey(const Key('thread-send')));
    await tester.pumpAndSettle();
    expect(server.replies['1']!.single['text'], 'my reply');
    expect(find.text('my reply'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a pinned message shows up in the pinned list', (tester) async {
    final server = FakeServer()..messages['general'] = [msgJson('1', 'bob', 'hello from bob')];
    await launch(tester, server: server, store: MemorySessionStore(token: 'saved'));
    await tester.tap(find.text('general'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('hello from bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-pin')));
    await tester.pumpAndSettle();
    expect(server.pinned, contains('1'));

    await tester.tap(find.byKey(const Key('channel-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-pins')));
    await tester.pumpAndSettle();
    expect(find.text('Pinned by bob'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a message from somebody else can be reported', (tester) async {
    final server = FakeServer()..messages['general'] = [msgJson('1', 'bob', 'buy my stuff')];
    await launch(tester, server: server, store: MemorySessionStore(token: 'saved'));
    await tester.tap(find.text('general'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('buy my stuff'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-report')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reason-spam')));
    await tester.pumpAndSettle();
    expect(server.reports, ['1:spam']);
    expect(find.text('Report sent. Thank you'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a channel can be made from the phone and then deleted', (tester) async {
    final server = FakeServer();
    await launch(tester, server: server, store: MemorySessionStore(token: 'saved'));
    await tester.tap(find.byKey(const Key('new-channel')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('channel-name')), 'My Plans');
    await tester.tap(find.byKey(const Key('channel-create')));
    await tester.pumpAndSettle();
    expect(server.channelCalls, ['create:my-plans']);
    expect(find.byKey(const Key('message-field')), findsOneWidget);

    await tester.tap(find.byKey(const Key('channel-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-leave-delete')));
    await tester.pumpAndSettle();
    expect(server.channelCalls, ['create:my-plans', 'delete:my-plans']);
    expect(find.text('my-plans'), findsNothing);
    await close(tester);
  });

  testWidgets('typing @ offers names, and tapping one fills it in', (tester) async {
    final server = FakeServer()..messages['general'] = [msgJson('1', 'bob', 'hello')];
    await launch(tester, server: server, store: MemorySessionStore(token: 'saved'));
    await tester.tap(find.text('general'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('message-field')), 'hi @bo');
    await tester.pump();
    expect(find.byKey(const Key('mention-bob')), findsOneWidget);
    expect(find.byKey(const Key('mention-cy')), findsNothing);
    await tester.tap(find.byKey(const Key('mention-bob')));
    await tester.pump();
    expect(find.text('hi @bob '), findsOneWidget);
    expect(find.byKey(const Key('mention-list')), findsNothing);
    await close(tester);
  });
}
