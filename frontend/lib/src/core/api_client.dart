import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Configuration for the backend base URL.
///
/// * `--dart-define=API_BASE_URL=http://localhost:8080` — dev: Flutter
///   dev-server on one port, API on another (CORS enabled on the server).
/// * `--dart-define=API_BASE_URL=` (empty) — production: the Flutter build is
///   served *by the backend*, so API calls use the same origin.
///
/// Defaults to the local development backend.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

/// A failed API call, carrying everything the UI needs to react:
/// HTTP status, a human-readable message, a machine code, and optional
/// per-field validation errors from the server.
class ApiException implements Exception {
  ApiException(
    this.statusCode,
    this.message, {
    this.code = 'error',
    this.fields = const {},
  });

  final int statusCode;
  final String message;
  final String code;
  final Map<String, String> fields;

  /// True when the server rejected the token (missing/expired session).
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

/// Thin typed wrapper around the LockNote REST API.
///
/// Every request carries `Authorization: Bearer <token>` when a session is
/// active, and every failure is normalised into an [ApiException] so screens
/// can show consistent error messages.
class ApiClient {
  ApiClient({this.baseUrl = apiBaseUrl, http.Client? client})
    : _client = client ?? http.Client();

  /// Empty [baseUrl] means "same origin as the page".
  final String baseUrl;
  final http.Client _client;

  /// Session token attached to every request after login/register.
  String? token;

  /// Called once whenever the server answers 401, so the app can bounce the
  /// user back to the login screen (session expired / revoked).
  void Function()? onUnauthorized;

  /// Overall request timeout so a dead backend never hangs the UI forever.
  static const Duration timeout = Duration(seconds: 20);

  Uri _uri(String path, [Map<String, String>? query]) {
    final Uri base = baseUrl.trim().isEmpty
        ? Uri
              .base // Same-origin deployment (build served by the backend).
        : Uri.parse(baseUrl);
    final uri = base.replace(path: _join(base.path, path));
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  String _join(String basePath, String path) {
    final left = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    final right = path.startsWith('/') ? path : '/$path';
    return '$left$right';
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final request = http.Request(method, _uri(path, query));
    request.headers['accept'] = 'application/json';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final currentToken = token;
    if (currentToken != null) {
      request.headers['authorization'] = 'Bearer $currentToken';
    }

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(
        0,
        'The server took too long to respond. Please try again.',
        code: 'timeout',
      );
    } on http.ClientException catch (error) {
      throw ApiException(
        0,
        'Could not reach the server. Is the backend running? (${error.message})',
        code: 'network_error',
      );
    } catch (_) {
      throw ApiException(
        0,
        'Network error — could not reach the server.',
        code: 'network_error',
      );
    }

    return _handleResponse(method, path, response);
  }

  dynamic _handleResponse(String method, String path, http.Response response) {
    final raw = utf8.decode(response.bodyBytes, allowMalformed: true);
    dynamic decoded;
    if (raw.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        decoded = null;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final map = decoded is Map<String, dynamic>
        ? decoded
        : const <String, dynamic>{};
    final fields = <String, String>{};
    if (map['details'] is Map) {
      (map['details'] as Map).forEach((key, value) {
        fields['$key'] = '$value';
      });
    }

    final exception = ApiException(
      response.statusCode,
      (map['error'] as String?) ??
          'The server could not complete $method $path '
              '(HTTP ${response.statusCode}).',
      code: (map['code'] as String?) ?? 'error',
      fields: fields,
    );

    if (exception.isUnauthorized) {
      token = null;
      onUnauthorized?.call();
    }
    return Future<dynamic>.error(exception);
  }
}
