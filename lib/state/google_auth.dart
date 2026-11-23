import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../api/rpc_client.dart';
import '../config.dart';

/// Gets a Google access token on the phone. The GoThermo server checks it and
/// does the actual sign-in.
abstract class GoogleAuth {
  /// The token, or null if the person closed the Google window.
  Future<String?> accessToken();

  Future<void> signOut();
}

class PlatformGoogleAuth implements GoogleAuth {
  PlatformGoogleAuth()
      : _google = GoogleSignIn(
          scopes: const ['email', 'profile'],
          clientId: googleIosClientId.isEmpty ? null : googleIosClientId,
        );

  final GoogleSignIn _google;

  @override
  Future<String?> accessToken() async {
    try {
      // Forget the previous account so the chooser shows every time.
      await _google.signOut();
      final account = await _google.signIn();
      if (account == null) return null;
      final auth = await account.authentication;
      final token = auth.accessToken;
      if (token == null || token.isEmpty) {
        throw RpcException('Google did not give the app a sign-in token');
      }
      return token;
    } on PlatformException catch (e) {
      throw RpcException(_explain(e));
    }
  }

  String _explain(PlatformException e) {
    final text = '${e.code} ${e.message ?? ''}';
    if (text.contains('network')) return 'Google could not be reached. Check your connection.';
    if (text.contains('sign_in_canceled') || text.contains('12501')) return 'Google sign-in was cancelled.';
    if (text.contains('10') || text.contains('DEVELOPER_ERROR')) {
      return 'Google sign-in is not set up for this build yet (Android client: package name + SHA-1).';
    }
    return 'Google sign-in failed (${e.code}).';
  }

  @override
  Future<void> signOut() async {
    try {
      await _google.signOut();
    } on Object {
      // nothing to forget
    }
  }
}

/// For tests: never opens a window.
class FakeGoogleAuth implements GoogleAuth {
  FakeGoogleAuth({this.token});

  String? token;

  @override
  Future<String?> accessToken() async => token;

  @override
  Future<void> signOut() async {}
}
