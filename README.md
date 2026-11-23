# GoThermo Mobile

The iOS and Android app for [GoThermo](https://github.com/Maksikos-ctrl/GoThermo), written in Flutter.

It is one more client of the same GoThermo server the web and desktop apps use: same accounts, same `POST /rpc/<Method>` API, same `/ws` live events. It never talks to Postgres or Redis directly.

## What it does

- Sign in, create an account (invite code) or continue with Google
- Channels and direct messages with unread badges, last-message previews and online / away dots
- Live chat over WebSocket (auto-reconnect, polling fallback), optimistic sending with retry
- Markdown, emoji picker, reactions, edit / delete, GIFs (when the server has GIPHY), photos, camera and files
- Search across channels, profile picture and status, in-app banners for new messages
- Midnight theme and animations matching the web and desktop apps

Not included yet: calls (WebRTC), push notifications when the app is closed (needs Firebase / APNs and device-token storage on the server), creating channels.

## Run it

You need [Flutter](https://docs.flutter.dev/get-started/install) (stable), Xcode for iOS and Android Studio / Android SDK for Android.

```bash
git clone https://github.com/Maksikos-ctrl/GoThermo-Mobile.git
cd GoThermo-Mobile
./tool/setup.sh                      # creates android/ and ios/, patches them, flutter pub get
flutter analyze && flutter test
flutter run                          # simulator or phone
flutter run -d <device id> --dart-define=GOOGLE_IOS_CLIENT_ID=<ios client id>   # with Google on iOS
```

The app starts connected to `https://gothermo-team.duckdns.org`; tap the server name on the sign-in screen to use another server.

## Google sign-in

The phone gets a Google access token and the server's `LoginWithGoogleToken` checks it, so the server's `GOOGLE_CLIENT_ID` (in `.env`) must list **every** client id, comma-separated: web/desktop, Android and iOS.

- **Android**: Google Cloud → Credentials → OAuth client → Android. Package name `com.gothermo.gothermoMobile` and the SHA-1 of your signing key (debug: `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`). Add a release SHA-1 too before publishing.
- **iOS**: OAuth client → iOS with the bundle id from Xcode. Run `GOOGLE_IOS_CLIENT_ID=<id> python3 tool/patch_platforms.py` once (adds the URL scheme) and pass the same id as `--dart-define=GOOGLE_IOS_CLIENT_ID=<id>`.
- Restart the server after changing `.env`.

The **Sign up with Google** button (Create account tab) makes a new account; **Sign in with Google** only signs into an existing one.

## How it fits together

```
lib/api/        RPC client, typed calls, WebSocket
lib/models/     User, Session, Channel, Message, Gif
lib/state/      AppController (auth), ChatController (channels, messages, live events), Google
lib/screens/    login, home, chat, search, profile, new message, admin notice
lib/widgets/    avatars, message rows, composer, emoji / GIF pickers, motion helpers
lib/util/       markdown, time formatting, mime types, emoji data
test/           unit tests for logic, widget tests with a fake server
```
