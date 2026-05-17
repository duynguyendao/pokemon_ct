import 'dart:convert';
import 'package:http/http.dart' as http;

class ExitAntySession {
  final String sessionId;
  final String baseUrl;
  final String? token;

  const ExitAntySession({
    required this.sessionId,
    required this.baseUrl,
    this.token,
  });
}

class ExitAntyService {
  final String host;
  final int port;
  final String token;

  ExitAntyService({this.host = '127.0.0.1', required this.port, this.token = ''});

  String get _base => 'http://$host:$port';

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  Future<bool> isRunning() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/status'), headers: _headers)
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return body['value']?['ready'] == true || res.statusCode == 200;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<ExitAntySession?> createSession({
    String? userAgent,
    Map<String, dynamic>? exitantyOptions,
  }) async {
    try {
      final caps = <String, dynamic>{
        'alwaysMatch': {
          if (userAgent != null) 'exitanty:userAgent': userAgent,
          ...?exitantyOptions,
        },
      };
      final res = await http
          .post(
            Uri.parse('$_base/session'),
            headers: _headers,
            body: jsonEncode({'capabilities': caps}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final id = body['value']?['sessionId'] as String?;
        if (id != null) {
          return ExitAntySession(sessionId: id, baseUrl: _base, token: token);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> navigate(ExitAntySession session, String url) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/session/${session.sessionId}/url'),
            headers: _headers,
            body: jsonEncode({'url': url}),
          )
          .timeout(const Duration(seconds: 15));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String?> getCurrentUrl(ExitAntySession session) async {
    try {
      final res = await http
          .get(
            Uri.parse('$_base/session/${session.sessionId}/url'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return body['value'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> executeScript(
    ExitAntySession session,
    String script, [
    List<dynamic> args = const [],
  ]) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_base/session/${session.sessionId}/execute/sync'),
            headers: _headers,
            body: jsonEncode({'script': script, 'args': args}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return body['value'];
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getScreenshot(ExitAntySession session) async {
    try {
      final res = await http
          .get(
            Uri.parse('$_base/session/${session.sessionId}/screenshot'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return body['value'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteSession(ExitAntySession session) async {
    try {
      await http
          .delete(
            Uri.parse('$_base/session/${session.sessionId}'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}
