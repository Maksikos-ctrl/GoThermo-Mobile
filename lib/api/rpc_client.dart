import 'dart:convert';

import 'package:http/http.dart' as http;

/// What the server (or the network) said went wrong, in words for a person.
class RpcException implements Exception {
  RpcException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Calls GoThermo server methods: `POST /rpc/<Method>` with the arguments as a
/// JSON array. The same protocol the web and desktop apps use.
class RpcClient {
  RpcClient({required String baseUrl, http.Client? client})
      : baseUrl = _trimSlash(baseUrl),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  static String _trimSlash(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Future<dynamic> call(
    String method,
    List<Object?> args, {
    Map<String, String> headers = const {},
  }) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse('$baseUrl/rpc/$method'),
            headers: {'Content-Type': 'application/json', ...headers},
            body: jsonEncode(args),
          )
          .timeout(const Duration(seconds: 20));
    } on Exception {
      throw RpcException('Cannot reach the server at $baseUrl');
    }

    Map<String, dynamic> body = const {};
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } on FormatException {
      throw RpcException('Unexpected answer from the server (${res.statusCode})');
    }

    final err = body['error'];
    if (err is String && err.isNotEmpty) throw RpcException(err);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw RpcException('Server error (${res.statusCode})');
    }
    return body['result'];
  }
}
