import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gothermo_mobile/app.dart';
import 'package:gothermo_mobile/state/google_auth.dart';
import 'package:gothermo_mobile/state/session_store.dart';

import 'support/fakes.dart';

Future<void> launch(
  WidgetTester tester, {
  required FakeServer server,
  MemorySessionStore? store,
  FakeGoogleAuth? google,
  FakeConnector? connector,
}) async {
  await tester.pumpWidget(GoThermoApp(
    store: store ?? MemorySessionStore(),
    httpClient: server.client,
    connector: connector ?? FakeConnector(),
    googleAuth: google ?? FakeGoogleAuth(),
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
}
