/// Build-time settings. Pass them with `--dart-define`, e.g.
///   flutter run --dart-define=GOOGLE_IOS_CLIENT_ID=123-abc.apps.googleusercontent.com
///
/// Only the iOS Google client id is needed here. On Android Google finds the
/// client by package name + signing key, and the server's web client id is
/// asked from the server itself.
const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
