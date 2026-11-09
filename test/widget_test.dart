import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/app.dart';
import 'package:gothermo_mobile/state/session_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response reply(Object? result) => http.Response(jsonEncode({'result': result}), 200);

/// A tiny fake server: one account, two channels.
MockClient fakeServer() => MockClient((req) async {
      final method = req.url.pathSegments.last;
      final args = jsonDecode(req.body) as List<dynamic>;
      switch (method) {
        case 'Login':
          if (args[0] == 'ann@x.io' && args[1] == 'right-pw') {
            return reply({'username': 'ann', 'email': 'ann@x.io', 'token': 'tok'});
          }
          return http.Response(jsonEncode({'error': 'incorrect email or password'}), 200);
        case 'CheckAuth':
          return reply(args[0] == 'saved' ? jsonEncode({'username': 'ann'}) : '');
        case 'GetChannels':
          return reply([
            {'id': '1', 'name': 'general', 'isPrivate': false},
            {'id': '2', 'name': 'launch-plan', 'isPrivate': true},
          ]);
        case 'Logout':
          return reply(true);
      }
      return http.Response(jsonEncode({'error': 'unknown method'}), 404);
    });

void main() {
  testWidgets('shows the sign-in screen when nobody is signed in', (tester) async {
    await tester.pumpWidget(GoThermoApp(store: MemorySessionStore(), httpClient: fakeServer()));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byKey(const Key('email')), findsOneWidget);
  });

  testWidgets('a wrong password shows the server message', (tester) async {
    await tester.pumpWidget(GoThermoApp(store: MemorySessionStore(), httpClient: fakeServer()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('email')), 'ann@x.io');
    await tester.enterText(find.byKey(const Key('password')), 'nope');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(find.text('incorrect email or password'), findsOneWidget);
  });

  testWidgets('signing in lists the channels, signing out goes back', (tester) async {
    final store = MemorySessionStore();
    await tester.pumpWidget(GoThermoApp(store: store, httpClient: fakeServer()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('email')), 'ann@x.io');
    await tester.enterText(find.byKey(const Key('password')), 'right-pw');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.text('general'), findsOneWidget);
    expect(find.text('launch-plan'), findsOneWidget);
    expect(store.token, 'tok');

    await tester.tap(find.byKey(const Key('sign-out')));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(store.token, isNull);
  });

  testWidgets('a saved token signs in without asking', (tester) async {
    final store = MemorySessionStore(token: 'saved');
    await tester.pumpWidget(GoThermoApp(store: store, httpClient: fakeServer()));
    await tester.pumpAndSettle();
    expect(find.text('general'), findsOneWidget);
  });

  testWidgets('a saved token the server refuses is dropped', (tester) async {
    final store = MemorySessionStore(token: 'expired');
    await tester.pumpWidget(GoThermoApp(store: store, httpClient: fakeServer()));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(store.token, isNull);
  });
}
