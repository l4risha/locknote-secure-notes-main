import 'dart:convert';

import 'package:shelf/shelf.dart';

/// An error that maps directly onto an HTTP JSON error response.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message,
      {this.code = 'error', this.details});

  final int statusCode;
  final String message;

  /// Stable machine-readable identifier (e.g. `validation_failed`).
  final String code;

  /// Optional per-field messages, used by form validation responses.
  final Map<String, String>? details;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

const Map<String, String> jsonHeaders = {
  'content-type': 'application/json; charset=utf-8'
};

/// Builds a JSON response with the standard envelope used by the API.
Response jsonResponse(Object? body,
    {int status = 200, Map<String, String>? extraHeaders}) {
  return Response(
    status,
    body: jsonEncode(body),
    headers: {...jsonHeaders, ...?extraHeaders},
  );
}

/// Builds the standard error payload: `{"error": "...", "code": "..."}`.
Response errorResponse(
  int status,
  String message, {
  String code = 'error',
  Map<String, String>? details,
}) {
  return jsonResponse(
    <String, Object?>{
      'error': message,
      'code': code,
      if (details != null && details.isNotEmpty) 'details': details,
    },
    status: status,
  );
}

/// Reads and decodes a JSON object request body.
///
/// Throws [ApiException] with 400 for malformed bodies so the error middleware
/// converts it into a proper JSON response.
Future<Map<String, dynamic>> readJsonObject(Request request) async {
  final String raw;
  try {
    raw = await request.readAsString();
  } catch (_) {
    throw ApiException(400, 'Could not read the request body.',
        code: 'invalid_json');
  }

  if (raw.trim().isEmpty) {
    throw ApiException(400, 'Request body must be a JSON object.',
        code: 'invalid_json');
  }

  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException(400, 'Request body must be a JSON object.',
          code: 'invalid_json');
    }
    return decoded;
  } on FormatException {
    throw ApiException(400, 'Request body is not valid JSON.',
        code: 'invalid_json');
  }
}

/// Reads a required string field from a decoded JSON body (non-throwing).
String jsonString(Map<String, dynamic> body, String key) {
  final value = body[key];
  if (value is String) return value;
  if (value == null) return '';
  return value.toString();
}
