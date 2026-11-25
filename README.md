# GoThermo Mobile

The iOS and Android app for [GoThermo](https://github.com/Maksikos-ctrl/GoThermo), the team chat with channels, direct messages, threads, decisions and calls. Written in Flutter.

It is one more client of the same GoThermo server the web and desktop apps use: same accounts, same `POST /rpc/<Method>` API, same `/ws` live events. It never talks to Postgres or Redis directly.

## Features

**Chat**
- Sign in, create an account (invite code) or continue with Google
- Channels and direct messages with unread badges, previews and online / away dots
- Live updates over WebSocket (auto-reconnect, polling fallback), typing indicator
- Markdown, emoji, reactions, edit / delete, GIFs (when the server has GIPHY), photos, camera, files
- Search across channels, profile picture and status

**Team tools (same as the web app)**
- **Threads**: reply to any message; the parent shows the reply count, replies arrive live; long-press a reply to react, copy, edit or delete it
- **Pins**: pin a message to a channel, see all pins from the channel menu
- **Decisions**: mark a message as a decision or a task, tick tasks off, remove them
- **@mentions**: type `@` and pick a name (in chats and in thread replies); real people are highlighted in messages, and messages that mention you stand out
- **Channels**: make a public or private channel from the Channels tab (pick who to invite); leave a private channel, or delete one you made, from the ⋮ menu
- **Report**: long-press someone else's message → Report message, pick a reason; the admins see it in the admin panel

**Calls**
- 1:1 voice and video (WebRTC), works with the web and desktop apps
- TURN relay support so calls work across different networks

**Notifications**
- A phone notification for a new message or an incoming call, also when the app is closed (Firebase push); tap it to open the channel

**Offline**
- SQLite copy: chats open at once and the last 200 messages per channel can be read with no connection; signing out wipes it
- Messages written offline wait (and survive closing the app) and are sent in order when the server is back

**Look**
- Themes: Midnight, Graphite, AMOLED, Light, System; 6 accent colours; text size (Profile → Appearance)

Not included yet: push on iOS (needs an Apple developer account and an APNs key in Firebase), group calls, screen share.

## Run it

You need [Flutter](https://docs.flutter.dev/get-started/install) (stable), Xcode for iOS and Android Studio / Android SDK for Android.

```bash
git clone https://github.com/Maksikos-ctrl/GoThermo-Mobile.git
cd GoThermo-Mobile
./tool/setup.sh          # creates android/ and ios/, patches them, flutter pub get
flutter analyze && flutter test
flutter run              # simulator or phone (flutter devices lists them)
```

After changing permissions or adding a plugin, run `python3 tool/patch_platforms.py` again. It is safe to repeat: every edit is skipped when it is already there. It sets the Android permissions (internet, microphone, camera, notifications), core library desugaring for notifications, the app name, and the iOS / macOS usage texts and entitlements.

The app starts connected to `https://gothermo-team.duckdns.org`; tap the server name on the sign-in screen to use another server.

## Google sign-in

The phone gets a Google access token and the server's `LoginWithGoogleToken` checks it, so the server's `GOOGLE_CLIENT_ID` (in `.env`) must list **every** client id, comma-separated: web/desktop, Android and iOS.

- **Android**: Google Cloud → Credentials → OAuth client → Android. Package name `com.gothermo.gothermo_mobile` and the SHA-1 of your signing key (debug: `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`). Add the release SHA-1 before publishing.
- **iOS**: OAuth client → iOS with the bundle id from Xcode. Run `GOOGLE_IOS_CLIENT_ID=<id> python3 tool/patch_platforms.py` once (adds the URL scheme) and run the app with `--dart-define=GOOGLE_IOS_CLIENT_ID=<id>`.
- Restart the server after changing `.env`.

**Sign up with Google** (Create account tab) makes a new account; **Sign in with Google** only signs into an existing one.

## Calls and the server

Calls go peer to peer. Across different networks (phone on mobile data, laptop on Wi-Fi) they need a TURN relay, which the server hands out through `GetIceServers`. On the server this means a `coturn` container and, in `.env`, a `TURN_SECRET`. Open these ports in the firewall / AWS security group: UDP and TCP `3478`, UDP `49152-49252`.

## Notifications

**App in the background.** A system notification appears when a message arrives or a call rings, and goes away when you come back. Messages in the channel you are looking at, your own messages and thread updates stay silent. Android 13+ and iOS ask for permission at launch.

**App closed (push).** The phone registers its Firebase token with the server (`RegisterDevice`), and the server sends a push through Firebase Cloud Messaging when you have no live connection: every message in a direct message or private channel, messages that `@mention` you in a public channel, and incoming calls. Tapping the push opens the channel.

Set-up, once:
1. Firebase console → add an Android app with package `com.gothermo.gothermo_mobile`, download `google-services.json` into `android/app/`, then run `python3 tool/patch_platforms.py` (it adds the Google services plugin to Gradle) and `flutter pub get`.
2. Firebase → Project settings → Service accounts → Generate new private key. Put the file on the server as `secrets/fcm.json` next to `docker-compose.yml` and mount it with `GOTHERMO_FCM_CREDENTIALS=/secrets/fcm.json` (see `SERVER.md`). Keep it out of git.
3. Server: `GOTHERMO_PUSH_PREVIEW=0` keeps message text out of notifications (they say "New message"). With the default, the text passes through Google's servers.

Without `google-services.json` the app builds and works, just without push; a server without the key sends none.

## How it fits together

```
lib/api/            RPC client, typed calls, WebSocket
lib/models/         User, Channel, Message, Pin, Decision, thread data
lib/state/          AppController (sign-in), ChatController (channels, messages, live events,
                    pins, threads, decisions, outbox), CallController, theme settings
lib/cache/          offline copy (SQLite, keyed per account)
lib/calls/          WebRTC engine and call tones
lib/notifications/  Notifier + NotificationCenter (in the background), PushService + PushRegistrar (closed app)
lib/screens/        login, home, chat, thread, pinned, decisions, search, profile, call
lib/widgets/        avatars, message rows and actions, composer, emoji / GIF pickers, motion
lib/util/           markdown, time formatting, mime types, emoji data
test/               unit tests for the logic, widget tests against a fake server
tool/               setup.sh, patch_platforms.py
```

Anything that needs a plugin sits behind a small interface (`LocalCache`, `Notifier`, `CallEngine`, `GoogleAuth`, `SessionStore`) so the logic is tested with plain fakes.

## Tests

```bash
flutter analyze
flutter test
```

## Security notes

- The session token is kept in the platform secure storage; the offline copy is wiped on sign-out.
- Keep `.env` (Google client ids, `TURN_SECRET`, `DATA_KEY`) out of git, and rotate any secret that was ever pasted in a chat or screenshot.
