import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_storage.dart';

/// Central API client: Bearer access attach + single-flight refresh-and-retry.
/// Mirrors `refreshAccessTokenIfRequired` from the researched app: exactly one
/// in-flight refresh; concurrent 401s wait for it instead of stampeding.
class ApiClient {
  ApiClient({String? baseUrl, AuthStorage? storage})
      : baseUrl =
            baseUrl ??
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://10.0.2.2:8080',
            ),
        // Memory-only by default: sessions die with the process, so every
        // cold start forces a fresh login (max-security mode).
        storage = storage ?? MemoryAuthStorage();

  final String baseUrl;
  final AuthStorage storage;
  String? _access;
  String? _refresh;
  Future<bool>? _refreshing;

  /// Staff mode: act on an owner's book (cf. accesscontrol). Null = own book.
  int? bookOwnerId;

  Future<void> init() async {
    final s = await storage.read();
    _access = s.access;
    _refresh = s.refresh;
  }

  bool get isLoggedIn => _access != null && _access!.isNotEmpty;

  Future<void> setSession({
    required String access,
    required String refresh,
  }) async {
    _access = access;
    _refresh = refresh;
    await storage.write(access: access, refresh: refresh);
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    _refreshing = null;
    bookOwnerId = null;
    await storage.clear();
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (isLoggedIn) 'Authorization': 'Bearer $_access',
    if (bookOwnerId != null) 'X-Book-Owner-Id': '$bookOwnerId',
  };

  dynamic _decode(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.isEmpty) return <String, dynamic>{};
      return jsonDecode(r.body);
    }
    throw ApiException(r.statusCode, r.body);
  }

  /// Public call (no token): OTP request/verify, refresh.
  Future<dynamic> postPublic(String path, Map<String, dynamic> body) async {
    final r = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(r);
  }

  Future<bool> _refreshLocked() {
    final cur = _refreshing;
    if (cur != null) return cur;
    final fut = _doRefresh();
    _refreshing = fut;
    fut.whenComplete(() => _refreshing = null);
    return fut;
  }

  Future<bool> _doRefresh() async {
    final rt = _refresh;
    if (rt == null || rt.isEmpty) return false;
    try {
      final r = await http.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': rt}),
      );
      if (r.statusCode != 200) return false;
      final j = jsonDecode(r.body) as Map;
      await setSession(
        access: j['access'] as String,
        refresh: j['refresh'] as String,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> _send(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) {
    final uri = Uri.parse('$baseUrl$path');
    switch (method) {
      case 'GET':
        return http.get(uri, headers: _headers);
      case 'DELETE':
        return http.delete(uri, headers: _headers);
      case 'PATCH':
        return http.patch(uri, headers: _headers, body: jsonEncode(body));
      default:
        return http.post(uri, headers: _headers, body: jsonEncode(body));
    }
  }

  /// Authenticated call: on 401, refresh once (single-flight) and retry once.
  Future<dynamic> _authed(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    http.Response r = await _send(method, path, body);
    if (r.statusCode != 401) return _decode(r);
    final ok = await _refreshLocked();
    if (!ok) {
      await clear();
      throw SessionExpired();
    }
    r = await _send(method, path, body);
    if (r.statusCode == 401) {
      await clear();
      throw SessionExpired();
    }
    return _decode(r);
  }

  Future<dynamic> get(String path) => _authed('GET', path, null);
  Future<dynamic> post(String path, Map<String, dynamic> body) =>
      _authed('POST', path, body);
  Future<dynamic> patch(String path, Map<String, dynamic> body) =>
      _authed('PATCH', path, body);
  Future<dynamic> del(String path) => _authed('DELETE', path, null);

  /// Non-JSON GET (invoice HTML) with the same refresh-and-retry.
  Future<String> getRaw(String path) async {
    http.Response r = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
    );
    if (r.statusCode == 401) {
      final ok = await _refreshLocked();
      if (!ok) {
        await clear();
        throw SessionExpired();
      }
      r = await http.get(Uri.parse('$baseUrl$path'), headers: _headers);
      if (r.statusCode == 401) {
        await clear();
        throw SessionExpired();
      }
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return r.body;
    throw ApiException(r.statusCode, r.body);
  }
}

class ApiException implements Exception {
  ApiException(this.status, this.body);
  final int status;
  final String body;

  /// Extracts the backend `{error: ...}` code when present.
  String get code {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is String) return j['error'] as String;
    } catch (_) {}
    return 'request_failed';
  }

  @override
  String toString() => 'ApiException($status): $body';
}

class SessionExpired implements Exception {
  @override
  String toString() => 'Session expired. Please log in again.';
}
