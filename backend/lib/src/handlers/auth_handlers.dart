import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

import '../auth.dart';
import '../config.dart';
import '../database.dart';
import '../http_utils.dart';
import '../login_limiter.dart';
import '../passwords.dart';
import '../session_store.dart';
import '../validation.dart';

/// /api/auth/* endpoints: register, login, logout, and me.
class AuthHandlers {
  AuthHandlers({
    required this.db,
    required this.sessions,
    required this.config,
  });

  final Database db;
  final SessionStore sessions;
  final Config config;

  // Tracks failed login attempts while this server is running.
  final LoginAttemptLimiter _limiter = LoginAttemptLimiter();

  /// POST /api/auth/register
  Future<Response> register(Request request) async {
    final body = await readJsonObject(request);
    final name = jsonString(body, 'name');
    final email = jsonString(body, 'email');
    final password = jsonString(body, 'password');

    final errors = validateRegister(
      name: name,
      email: email,
      password: password,
    );

    if (errors.isNotEmpty) {
      throw ApiException(
        422,
        'Please fix the highlighted fields.',
        code: 'validation_failed',
        details: errors,
      );
    }

    final trimmedName = name.trim();
    final normalizedEmail = normalizeEmail(email);

    final passwordHash = hashPassword(
      password,
      iterations: config.pbkdf2Iterations,
    );

    try {
      await db.query(
        '''
        INSERT INTO users (name, email, password_hash)
        VALUES (@name, @email, @passwordHash)
        ''',
        parameters: {
          'name': trimmedName,
          'email': normalizedEmail,
          'passwordHash': passwordHash,
        },
      );
    } on ServerException catch (error) {
      if (error.code == '23505') {
        throw ApiException(
          409,
          'An account with that email already exists.',
          code: 'email_taken',
          details: {
            'email': 'This email is already registered. Try signing in.',
          },
        );
      }

      rethrow;
    }

    // Registration does not create a session or return a token.
    return jsonResponse(
      {
        'message': 'Account created successfully. Please sign in.',
      },
      status: 201,
    );
  }

  /// POST /api/auth/login
  Future<Response> login(Request request) async {
    final body = await readJsonObject(request);
    final email = jsonString(body, 'email');
    final password = jsonString(body, 'password');
    final normalizedEmail = normalizeEmail(email);

    final errors = validateLogin(
      email: email,
      password: password,
    );

    if (errors.isNotEmpty) {
      throw ApiException(
        422,
        'Please fix the highlighted fields.',
        code: 'validation_failed',
        details: errors,
      );
    }

    // Check the lock before querying/verifying the password.
    final locked = _limiter.lockedSeconds(normalizedEmail);

    if (locked != null) {
      throw ApiException(
        429,
        lockedMessage(locked),
        code: 'login_locked',
      );
    }

    final rows = await db.query(
      'SELECT id, name, email, password_hash '
      'FROM users WHERE lower(email) = @email',
      parameters: {'email': normalizedEmail},
    );

    if (rows.isEmpty) {
      // Keep hashing work similar for unknown email addresses.
      hashPassword(
        password,
        iterations: config.pbkdf2Iterations,
      );

      final remaining = _limiter.recordFailure(normalizedEmail);

      if (remaining == 0) {
        final seconds = _limiter.lockedSeconds(normalizedEmail) ?? 30;

        throw ApiException(
          429,
          lockedMessage(seconds),
          code: 'login_locked',
        );
      }

      throw ApiException(
        401,
        failedMessage(remaining),
        code: 'invalid_credentials',
      );
    }

    final user = rows.first.toColumnMap();
    final storedHash = user['password_hash'] as String;

    if (!verifyPassword(password, storedHash)) {
      final remaining = _limiter.recordFailure(normalizedEmail);

      if (remaining == 0) {
        final seconds = _limiter.lockedSeconds(normalizedEmail) ?? 30;

        throw ApiException(
          429,
          lockedMessage(seconds),
          code: 'login_locked',
        );
      }

      throw ApiException(
        401,
        failedMessage(remaining),
        code: 'invalid_credentials',
      );
    }

    // Successful login clears the failed-attempt counter.
    _limiter.recordSuccess(normalizedEmail);

    // Preserve the existing session creation.
    final token = await sessions.create(user['id'] as int);

    return jsonResponse({
      'token': token,
      'user': {
        'id': user['id'],
        'name': user['name'],
        'email': user['email'],
      },
    });
  }

  /// POST /api/auth/logout
  Future<Response> logout(Request request) async {
    final token = bearerToken(request);

    if (token == null) {
      throw ApiException(
        401,
        'You must be signed in to do that.',
        code: 'unauthenticated',
      );
    }

    await sessions.revoke(token);

    return jsonResponse({'message': 'Signed out.'});
  }

  /// GET /api/auth/me
  Future<Response> me(Request request) async {
    final user = await requireAuth(request, sessions);
    return jsonResponse({'user': user.toJson()});
  }
}
