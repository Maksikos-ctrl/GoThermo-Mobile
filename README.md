# GoThermo Mobile

The iOS and Android app for [GoThermo](https://github.com/Maksikos-ctrl/GoThermo), written in Flutter.

It is one more client of the same GoThermo server the web and desktop apps use: it signs in with the same accounts and calls the same `POST /rpc/<Method>` API, so channels, people and messages are shared. It never talks to Postgres or Redis directly.

## Status

Built in layers, each one runnable on its own:

- [x] 1. Skeleton: theme, server client, sign in / create account (invite code), saved session, channel list
- [ ] 2. Chat: messages, sending, live updates (WebSocket), unread, avatars, markdown
- [ ] 3. Reactions, emoji, GIFs, threads, files, decisions and tasks
- [ ] 4. Calls (1:1 and group) and push notifications
- [ ] 5. Reports, settings, store builds

## Run it

You need [Flutter](https://docs.flutter.dev/get-started/install) (stable), Xcode for iOS and Android Studio for Android.

```bash
git clone https://github.com/Maksikos-ctrl/GoThermo-Mobile.git
cd GoThermo-Mobile
./tool/setup.sh        # creates android/ and ios/, patches them, flutter pub get
flutter test
flutter run            # simulator or phone
```

The app starts connected to `https://gothermo-team.duckdns.org`; tap the server name on the sign-in screen to use another server.

Signing in as the admin (`admin` in the email box) works, but the admin panel itself lives in the web app.

## How it fits together

```
lib/api/rpc_client.dart     POST /rpc/<Method>, the same protocol as the web app
lib/api/gothermo_api.dart   typed calls (Login, CheckAuth, GetChannels, ...)
lib/models/                 User, Session, Channel
lib/state/                  token + server address storage, AppController
lib/screens/                login, channel list
lib/widgets/                Avatar (same colours as web and desktop)
lib/theme.dart              the Midnight palette
```

The token is kept in the system keychain / keystore.
