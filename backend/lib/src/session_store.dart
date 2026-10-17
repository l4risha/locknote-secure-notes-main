import 'database.dart';
import 'models.dart';
import 'tokens.dart';

/// Creates, verifies, and revokes bearer-token sessions.
///
/// Only the SHA-256 digest of a token is persisted, expiry is checked against
/// the database clock, and logout deletes the row — so a revoked token stops
/// working immediately.
class SessionStore {
  SessionStore(this.db, {required this.ttl});

  final Database db;
  final Duration ttl;

  /// Creates a session for [userId] and returns the **raw** bearer token.
  ///
  /// The raw token is shown to the client exactly once and never stored.
  Future<String> create(int userId) async {
    final token = generateToken();
    await db.query(
      '''
      INSERT INTO sessions (user_id, token_hash, expires_at)
      VALUES (@userId, @tokenHash, now() + make_interval(secs => @seconds))
      ''',
      parameters: {
        'userId': userId,
        'tokenHash': hashToken(token),
        'seconds': ttl.inSeconds,
      },
    );
    return token;
  }

  /// Returns the user behind a token, or `null` if the token is unknown or
  /// expired.
  Future<AuthUser?> findUserByToken(String token) async {
    final rows = await db.query(
      '''
      SELECT u.id AS id, u.name AS name, u.email AS email
      FROM sessions s
      INNER JOIN users u ON u.id = s.user_id
      WHERE s.token_hash = @tokenHash AND s.expires_at > now()
      ''',
      parameters: {'tokenHash': hashToken(token)},
    );
    if (rows.isEmpty) return null;

    final row = rows.first.toColumnMap();
    return AuthUser(
      id: row['id'] as int,
      name: row['name'] as String,
      email: row['email'] as String,
    );
  }

  /// Invalidates a token (server-side logout).
  Future<void> revoke(String token) async {
    await db.query(
      'DELETE FROM sessions WHERE token_hash = @tokenHash',
      parameters: {'tokenHash': hashToken(token)},
    );
  }
}
