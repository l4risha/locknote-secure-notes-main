import 'package:shelf/shelf.dart';

import 'http_utils.dart';
import 'models.dart';
import 'session_store.dart';

/// Extracts the `Authorization: Bearer <token>` value, if present.
String? bearerToken(Request request) {
  final header = request.headers['authorization'] ?? '';
  if (!header.startsWith('Bearer ')) return null;
  final token = header.substring('Bearer '.length).trim();
  return token.isEmpty ? null : token;
}

/// Resolves the caller behind a request.
///
/// Every protected endpoint calls this — the server never trusts that a client
/// "belongs" to a user just because it says so. Throws 401 when the token is
/// missing, unknown, or expired.
Future<AuthUser> requireAuth(Request request, SessionStore sessions) async {
  final token = bearerToken(request);
  if (token == null) {
    throw ApiException(
      401,
      'You must be signed in to do that.',
      code: 'unauthenticated',
    );
  }
  final user = await sessions.findUserByToken(token);
  if (user == null) {
    throw ApiException(
      401,
      'Your session has expired. Please sign in again.',
      code: 'session_expired',
    );
  }
  return user;
}
