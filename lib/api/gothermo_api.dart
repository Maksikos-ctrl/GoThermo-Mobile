import 'dart:convert';

import '../models/channel.dart';
import '../models/extras.dart';
import '../models/gif.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'rpc_client.dart';

/// Typed calls to the server. Every method here is one the web app uses too.
class GoThermoApi {
  GoThermoApi(this._rpc);

  final RpcClient _rpc;

  Map<String, dynamic> _map(Object? v) {
    if (v is Map<String, dynamic>) return v;
    throw RpcException('Unexpected answer from the server');
  }

  /// [identifier] is an email, or `admin` for the admin account.
  Future<Session> login(String identifier, String password) async {
    final raw = await _rpc.call('Login', [identifier.trim(), password]);
    return _sessionFrom(raw, User.fromJson(_map(raw)));
  }

  Session _sessionFrom(Object? raw, User user) {
    final token = _map(raw)['token'];
    if (token is! String || token.isEmpty) {
      throw RpcException('The server did not return a session');
    }
    return Session(token: token, user: user);
  }

  Future<Session> register(String email, String password, {String invite = ''}) async {
    final raw = await _rpc.call(
      'Register',
      [email.trim(), password],
      headers: invite.trim().isEmpty ? const {} : {'X-Invite-Code': invite.trim()},
    );
    return _sessionFrom(raw, User.fromJson(_map(raw)));
  }

  /// The signed-in person for a saved token, or null when it no longer works.
  Future<User?> check(String token) async {
    final raw = await _rpc.call('CheckAuth', [token]);
    if (raw is! String || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return User.fromJson(decoded);
  }

  Future<void> logout(String token) async {
    await _rpc.call('Logout', [token]);
  }

  Future<List<Channel>> channels(String token) async {
    final raw = await _rpc.call('GetChannels', [token]);
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(Channel.fromJson).toList();
  }

  List<Map<String, dynamic>> _maps(Object? raw) =>
      raw is List ? raw.whereType<Map<String, dynamic>>().toList() : const [];

  /// Everyone on the server, with their status and picture.
  Future<List<User>> users(String token) async {
    final raw = await _rpc.call('GetUsers', [token]);
    return _maps(raw).map(User.fromJson).toList();
  }

  Future<List<Channel>> dmChannels(String token, String username) async {
    final raw = await _rpc.call('GetDMChannels', [token, username]);
    return _maps(raw).map(Channel.fromJson).toList();
  }

  Future<Channel> getOrCreateDm(String token, String me, String other) async {
    final raw = await _rpc.call('GetOrCreateDMChannel', [token, me, other]);
    return Channel.fromJson(_map(raw));
  }

  Future<void> joinChannel(String token, String channel, String username) async {
    await _rpc.call('JoinChannel', [token, channel, username]);
  }

  /// [beforeId] empty = the newest page, otherwise the page right before that message.
  /// The server answers `{messages: [...], hasMore: bool}`; a bare list is accepted too.
  Future<({List<Message> messages, bool? hasMore})> messagesPage(
    String token,
    String channel, {
    String beforeId = '',
    int limit = 40,
  }) async {
    final raw = await _rpc.call('GetMessagesPage', [token, channel, beforeId, limit]);
    if (raw is Map) {
      final more = raw['hasMore'];
      return (
        messages: _maps(raw['messages']).map(Message.fromJson).toList(),
        hasMore: more is bool ? more : null,
      );
    }
    return (messages: _maps(raw).map(Message.fromJson).toList(), hasMore: null);
  }

  // ---- pins, threads, decisions -----------------------------------------------------

  Future<void> pinMessage(String token, String channel, String messageId, String me) async {
    await _rpc.call('PinMessage', [token, channel, messageId, me]);
  }

  Future<void> unpinMessage(String token, String channel, String messageId, String me) async {
    await _rpc.call('UnpinMessage', [token, channel, messageId, me]);
  }

  Future<List<Pin>> pins(String token, String channel) async {
    final raw = await _rpc.call('GetPinnedMessages', [token, channel]);
    return _maps(raw).map(Pin.fromJson).toList();
  }

  Future<ThreadData> thread(String token, String channel, String parentId) async {
    final raw = await _rpc.call('GetThread', [token, channel, parentId]);
    return ThreadData.fromJson(_map(raw));
  }

  Future<Message> sendReply(String token, String me, String channel, String parentId, String text) async {
    final raw = await _rpc.call('SendReply', [token, me, channel, parentId, text]);
    return Message.fromJson(_map(raw));
  }

  Future<void> deleteReply(String token, String channel, String parentId, String replyId, String me) async {
    await _rpc.call('DeleteReply', [token, channel, parentId, replyId, me]);
  }

  Future<List<Decision>> decisions(String token, String channel) async {
    final raw = await _rpc.call('GetDecisions', [token, channel]);
    return _maps(raw).map(Decision.fromJson).toList();
  }

  Future<void> markDecision(String token, String me, String channel, String messageId, String kind) async {
    await _rpc.call('MarkDecision', [token, me, channel, messageId, kind]);
  }

  Future<void> setDecisionDone(String token, String me, String channel, String messageId, bool done) async {
    await _rpc.call('SetDecisionDone', [token, me, channel, messageId, done]);
  }

  Future<void> removeDecision(String token, String me, String channel, String messageId) async {
    await _rpc.call('RemoveDecision', [token, me, channel, messageId]);
  }

  /// Returns the id of the new message.
  Future<String> sendMessage(String token, String user, String text, String channel) async {
    final raw = await _rpc.call('SendMessage', [token, user, text, channel]);
    return raw is String ? raw : '';
  }

  Future<void> toggleReaction(
    String token,
    String messageId,
    String emoji,
    String username,
    String channel,
  ) async {
    await _rpc.call('AddReaction', [token, messageId, emoji, username, channel]);
  }

  Future<Message> editMessage(
    String token,
    String messageId,
    String channel,
    String username,
    String newText,
  ) async {
    final raw = await _rpc.call('EditMessage', [token, messageId, channel, username, newText]);
    return Message.fromJson(_map(raw));
  }

  Future<void> deleteMessage(String token, String messageId, String channel, String username) async {
    await _rpc.call('DeleteMessage', [token, messageId, channel, username]);
  }

  /// STUN / TURN servers for calls (the same list the web app uses).
  Future<List<Map<String, dynamic>>> iceServers(String token) async {
    final raw = await _rpc.call('GetIceServers', [token]);
    if (raw is! String) return const [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded.whereType<Map<String, dynamic>>().toList();
  }

  /// Writes the "call" line into a conversation. [status] is `completed`,
  /// `declined` or `cancelled`.
  Future<void> logCall(String token, String channel, String initiator, String status, int seconds) async {
    await _rpc.call('LogCall', [token, channel, initiator, status, seconds]);
  }

  /// Gives the server this phone's push address.
  Future<void> registerDevice(String token, String username, String deviceToken) async {
    await _rpc.call('RegisterDevice', [token, username, deviceToken]);
  }

  Future<void> unregisterDevice(String token, String username, String deviceToken) async {
    await _rpc.call('UnregisterDevice', [token, username, deviceToken]);
  }

  Future<void> markRead(String token, String username, String channel) async {
    await _rpc.call('MarkChannelRead', [token, username, channel]);
  }

  Future<Map<String, int>> unreadCounts(String token, String username) async {
    final raw = await _rpc.call('GetUnreadCounts', [token, username]);
    final out = <String, int>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String && v is num) out[k] = v.toInt();
      });
    }
    return out;
  }

  Future<List<Message>> search(String token, String username, String query) async {
    final raw = await _rpc.call('SearchMessages', [token, username, query]);
    return _maps(raw).map(Message.fromJson).toList();
  }

  /// [base64Data] is plain base64 (a `data:` prefix is accepted too).
  Future<Message> sendFile(
    String token,
    String user,
    String channel,
    String fileName,
    String mimeType,
    String base64Data,
  ) async {
    final raw = await _rpc.call('SendFile', [token, user, channel, fileName, mimeType, base64Data]);
    return Message.fromJson(_map(raw));
  }

  /// The file as a `data:<mime>;base64,...` URL.
  Future<String> fileData(String token, String fileId) async {
    final raw = await _rpc.call('GetFileData', [token, fileId]);
    if (raw is! String || raw.isEmpty) throw RpcException('The file is empty');
    return raw;
  }

  Future<bool> gifsEnabled(String token) async {
    try {
      return (await _rpc.call('GifsEnabled', [token])) == true;
    } on RpcException {
      return false;
    }
  }

  Future<List<Gif>> searchGifs(String token, String query) async {
    final raw = await _rpc.call('SearchGifs', [token, query]);
    return _maps(raw).map(Gif.fromJson).where((g) => g.url.isNotEmpty).toList();
  }

  Future<void> setAvatar(String token, String user, String base64Data) async {
    await _rpc.call('SetAvatar', [token, user, base64Data]);
  }

  Future<void> removeAvatar(String token, String user) async {
    await _rpc.call('RemoveAvatar', [token, user]);
  }

  /// The OAuth client id the server trusts for the browser, or empty when Google
  /// sign-in is not set up. The phone passes it to Google as `serverClientId`.
  Future<String> googleWebClientId() async {
    try {
      final raw = await _rpc.call('GoogleWebClientID', []);
      return raw is String ? raw : '';
    } on RpcException {
      return '';
    }
  }

  /// The server checks the token belongs to its own Google client, reads the
  /// profile from Google itself, and signs the person in. [signUp] false only
  /// lets existing accounts in.
  Future<Session> loginWithGoogleToken(String accessToken, {required bool signUp}) async {
    final raw = await _rpc.call('LoginWithGoogleToken', [accessToken, signUp]);
    return _sessionFrom(raw, User.fromJson(_map(raw)));
  }
}
