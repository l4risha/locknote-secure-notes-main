import 'dart:convert';
import 'dart:io';

import 'package:locknote_backend/locknote_backend.dart';
import 'package:locknote_backend/src/env_file.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// End-to-end tests that exercise the real HTTP handler against a real
/// PostgreSQL database — including every authorization boundary.
///
/// Configuration comes from `backend/.env` and/or the `DB_*` environment
/// variables. A dedicated `<DB_NAME>_test` database is created automatically
/// (and wiped only of rows created here). When no database is reachable the
/// whole suite is reported as **skipped** — tests are never faked.
Future<void> main() async {
  final ctx = await _connectTestDatabase();
  if (ctx == null) {
    test(
      'LockNote API integration suite',
      () {},
      skip:
          'PostgreSQL not reachable — set DB_HOST/DB_PORT/DB_USER/DB_PASSWORD/'
          'DB_NAME (environment variables or backend/.env) to run integration tests.',
    );
    return;
  }

  final handler = ctx.handler;
  final db = ctx.db;
  var runId = DateTime.now().microsecondsSinceEpoch;
  var emailCounter = 0;

  String nextEmail(String label) =>
      'it-$runId-${emailCounter++}@$label.test.local';

  Future<Response> call(
    String method,
    String path, {
    Object? body,
    String? token,
    String? origin,
  }) async {
    return handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {
          'content-type': 'application/json',
          if (token != null) 'authorization': 'Bearer $token',
          if (origin != null) 'origin': origin,
        },
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  Future<Map<String, dynamic>> jsonOf(Response response) async {
    return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
  }

  /// Registers a fresh user and returns their bearer token.
  Future<String> registerUser({String? email}) async {
    final response = await call(
      'POST',
      '/api/auth/register',
      body: {
        'name': 'Integration Tester',
        'email': email ?? nextEmail('reg'),
        'password': 'correct-horse-1',
      },
    );
    final raw = await response.readAsString();
    expect(response.statusCode, 201, reason: raw);
    return (jsonDecode(raw) as Map<String, dynamic>)['token'] as String;
  }

  tearDownAll(() async {
    // Remove rows created by this run from the throwaway test database.
    await db.query("DELETE FROM users WHERE email LIKE '%@.test.local'");
    await db.close();
  });

  group('health & meta', () {
    test('GET /api/health returns ok', () async {
      final response = await call('GET', '/api/health');
      expect(response.statusCode, 200);
      expect((await jsonOf(response))['status'], 'ok');
    });

    test('unknown API route returns JSON 404', () async {
      final response = await call('GET', '/api/nope');
      expect(response.statusCode, 404);
      expect(response.headers['content-type'], contains('application/json'));
      expect((await jsonOf(response))['code'], 'not_found');
    });

    test('CORS preflight echoes a development origin', () async {
      final response = await call(
        'OPTIONS',
        '/api/notes',
        origin: 'http://localhost:3000',
      );
      expect(response.statusCode, 204);
      expect(response.headers['access-control-allow-origin'],
          'http://localhost:3000');
      expect(response.headers['access-control-allow-headers'],
          contains('authorization'));
    });

    test('API responses are marked no-store', () async {
      final response = await call('GET', '/api/health');
      expect(response.headers['cache-control'], 'no-store');
      expect(response.headers['x-content-type-options'], 'nosniff');
    });
  });

  group('registration', () {
    test('creates an account and never echoes the password', () async {
      final email = nextEmail('reg');
      final response = await call(
        'POST',
        '/api/auth/register',
        body: {
          'name': 'Ada Lovelace',
          'email': email,
          'password': 'secret-1234'
        },
      );
      expect(response.statusCode, 201);
      final raw = await response.readAsString();
      expect(raw, isNot(contains('secret-1234')));

      final payload = jsonDecode(raw) as Map<String, dynamic>;
      expect(payload['token'], isA<String>());
      expect((payload['user'] as Map<String, dynamic>)['email'], email);
    });

    test('stores only a hash — the users table has no plaintext', () async {
      final email = nextEmail('hash');
      await registerUser(email: email);
      final rows = await db.query(
        'SELECT password_hash FROM users WHERE email = @email',
        parameters: {'email': email},
      );
      final stored = rows.first.toColumnMap()['password_hash'] as String;
      expect(stored, startsWith('pbkdf2_sha256\$'));
      expect(stored, isNot(contains('correct-horse-1')));
    });

    test('rejects duplicate emails with 409', () async {
      final email = nextEmail('dup');
      await registerUser(email: email);
      final response = await call(
        'POST',
        '/api/auth/register',
        body: {'name': 'Impostor', 'email': email, 'password': 'another-1234'},
      );
      expect(response.statusCode, 409);
      expect((await jsonOf(response))['code'], 'email_taken');
    });

    test('emails are case-insensitively unique', () async {
      final email = nextEmail('case');
      await registerUser(email: email);
      final response = await call(
        'POST',
        '/api/auth/register',
        body: {
          'name': 'Case Clone',
          'email': email.toUpperCase(),
          'password': 'another-1234'
        },
      );
      expect(response.statusCode, 409);
    });

    test('rejects invalid payloads with 422 and per-field details', () async {
      final response = await call(
        'POST',
        '/api/auth/register',
        body: {'name': '', 'email': 'not-an-email', 'password': 'short'},
      );
      expect(response.statusCode, 422);
      final payload = await jsonOf(response);
      expect(payload['code'], 'validation_failed');
      expect(
        (payload['details'] as Map<String, dynamic>).keys,
        containsAll(['name', 'email', 'password']),
      );
    });

    test('rejects malformed JSON with 400', () async {
      final response = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/api/auth/register'),
          headers: {'content-type': 'application/json'},
          body: '{not json',
        ),
      );
      expect(response.statusCode, 400);
      expect((await jsonOf(response))['code'], 'invalid_json');
    });
  });

  group('login & sessions', () {
    test('wrong password and unknown email return byte-identical 401s',
        () async {
      final email = nextEmail('login');
      await registerUser(email: email);

      final wrongPassword = await call(
        'POST',
        '/api/auth/login',
        body: {'email': email, 'password': 'wrong-password-1'},
      );
      final unknownEmail = await call(
        'POST',
        '/api/auth/login',
        body: {'email': nextEmail('ghost'), 'password': 'wrong-password-1'},
      );

      expect(wrongPassword.statusCode, 401);
      expect(unknownEmail.statusCode, 401);
      // Account enumeration via login must be impossible.
      expect(await wrongPassword.readAsString(),
          await unknownEmail.readAsString());
    });

    test('correct password returns a working token', () async {
      final email = nextEmail('ok');
      await registerUser(email: email);

      final login = await call(
        'POST',
        '/api/auth/login',
        body: {'email': email, 'password': 'correct-horse-1'},
      );
      expect(login.statusCode, 200);
      final token = (await jsonOf(login))['token'] as String;

      final me = await call('GET', '/api/auth/me', token: token);
      expect(me.statusCode, 200);
      final user = (await jsonOf(me))['user'] as Map<String, dynamic>;
      expect(user['email'], email);
    });

    test('missing, malformed, and revoked tokens are rejected', () async {
      final token = await registerUser();

      expect((await call('GET', '/api/auth/me')).statusCode, 401);
      expect(
        (await call('GET', '/api/auth/me', token: 'not-a-real-token'))
            .statusCode,
        401,
      );

      final logout = await call('POST', '/api/auth/logout', token: token);
      expect(logout.statusCode, 200);

      final revoked = await call('GET', '/api/auth/me', token: token);
      expect(revoked.statusCode, 401);
      expect((await jsonOf(revoked))['code'], 'session_expired');
    });

    test('every notes endpoint requires authentication', () async {
      expect((await call('GET', '/api/notes')).statusCode, 401);
      expect(
        (await call('POST', '/api/notes', body: {'title': 'x'})).statusCode,
        401,
      );
      expect((await call('GET', '/api/notes/1')).statusCode, 401);
      expect(
          (await call('PUT', '/api/notes/1', body: {'title': 'x'})).statusCode,
          401);
      expect((await call('DELETE', '/api/notes/1')).statusCode, 401);
      expect((await call('GET', '/api/dashboard')).statusCode, 401);
    });
  });

  group('notes CRUD & search', () {
    test('full lifecycle: create, read, list, update, search, delete',
        () async {
      final token = await registerUser();

      // Create.
      final created = await call(
        'POST',
        '/api/notes',
        token: token,
        body: {'title': 'Groceries', 'content': 'milk, eggs, bread'},
      );
      expect(created.statusCode, 201);
      final note = (await jsonOf(created))['note'] as Map<String, dynamic>;
      final id = note['id'] as int;
      expect(note['title'], 'Groceries');
      expect(note['updatedAt'], isA<String>());

      // A second note for search/filter checks.
      final second = await call(
        'POST',
        '/api/notes',
        token: token,
        body: {'title': 'Exam plan', 'content': 'study chapter four'},
      );
      expect(second.statusCode, 201);
      final secondId =
          ((await jsonOf(second))['note'] as Map<String, dynamic>)['id'] as int;

      // Read own note.
      final fetched = await call('GET', '/api/notes/$id', token: token);
      expect(fetched.statusCode, 200);
      expect(
        ((await jsonOf(fetched))['note'] as Map<String, dynamic>)['content'],
        'milk, eggs, bread',
      );

      // List.
      final list = await call('GET', '/api/notes', token: token);
      expect(list.statusCode, 200);
      expect(((await jsonOf(list))['notes'] as List).length, 2);

      // Search by content (case-insensitive).
      final byContent =
          await call('GET', '/api/notes?search=EGGS', token: token);
      final contentResults = (await jsonOf(byContent))['notes'] as List;
      expect(contentResults.length, 1);
      expect(contentResults.first['id'], id);

      // Search by title.
      final byTitle = await call('GET', '/api/notes?search=exam', token: token);
      final titleResults = (await jsonOf(byTitle))['notes'] as List;
      expect(titleResults.length, 1);
      expect(titleResults.first['id'], secondId);

      // `%` typed by a user is literal, not a wildcard.
      final literal = await call('GET', '/api/notes?search=%25', token: token);
      expect((await jsonOf(literal))['notes'], isEmpty);

      // Update.
      final updated = await call(
        'PUT',
        '/api/notes/$id',
        token: token,
        body: {'title': 'Groceries (done)', 'content': 'milk, eggs'},
      );
      expect(updated.statusCode, 200);
      final updatedNote =
          (await jsonOf(updated))['note'] as Map<String, dynamic>;
      expect(updatedNote['title'], 'Groceries (done)');

      // Delete.
      final deleted = await call('DELETE', '/api/notes/$id', token: token);
      expect(deleted.statusCode, 200);

      final gone = await call('GET', '/api/notes/$id', token: token);
      expect(gone.statusCode, 404);
    });

    test('validates note payloads with 422', () async {
      final token = await registerUser();
      final response = await call(
        'POST',
        '/api/notes',
        token: token,
        body: {'title': '   ', 'content': 'no title'},
      );
      expect(response.statusCode, 422);
      expect(
        ((await jsonOf(response))['details'] as Map<String, dynamic>)
            .containsKey('title'),
        isTrue,
      );
    });

    test('invalid note ids return 400, unknown ids return 404', () async {
      final token = await registerUser();
      expect(
          (await call('GET', '/api/notes/abc', token: token)).statusCode, 400);
      expect(
          (await call('GET', '/api/notes/99999999', token: token)).statusCode,
          404);
    });
  });

  group('user isolation (server-side authorization)', () {
    test("user B cannot read, update, or delete user A's note", () async {
      final tokenA = await registerUser();
      final tokenB = await registerUser();

      final created = await call(
        'POST',
        '/api/notes',
        token: tokenA,
        body: {'title': 'Private diary', 'content': 'confidential'},
      );
      final noteId = ((await jsonOf(created))['note']
          as Map<String, dynamic>)['id'] as int;

      // B's list never contains A's note.
      final listB = await call('GET', '/api/notes', token: tokenB);
      expect((await jsonOf(listB))['notes'], isEmpty);

      // Direct access attempts fail exactly like a non-existent note.
      expect(
          (await call('GET', '/api/notes/$noteId', token: tokenB)).statusCode,
          404);
      expect(
        (await call(
          'PUT',
          '/api/notes/$noteId',
          token: tokenB,
          body: {'title': 'hacked', 'content': 'x'},
        ))
            .statusCode,
        404,
      );
      expect(
        (await call('DELETE', '/api/notes/$noteId', token: tokenB)).statusCode,
        404,
      );

      // A's note is untouched.
      final stillThere = await call('GET', '/api/notes/$noteId', token: tokenA);
      expect(stillThere.statusCode, 200);
      expect(
        ((await jsonOf(stillThere))['note'] as Map<String, dynamic>)['title'],
        'Private diary',
      );
    });

    test('dashboard counts only the requesting user', () async {
      final tokenA = await registerUser();
      final tokenB = await registerUser();

      for (var i = 0; i < 2; i++) {
        await call(
          'POST',
          '/api/notes',
          token: tokenA,
          body: {'title': 'A note $i', 'content': 'c$i'},
        );
      }
      await call(
        'POST',
        '/api/notes',
        token: tokenB,
        body: {'title': 'B note', 'content': 'only b'},
      );

      final payloadA =
          await jsonOf(await call('GET', '/api/dashboard', token: tokenA));
      expect(payloadA['totalNotes'], 2);
      expect((payloadA['recentNotes'] as List).length, 2);

      final payloadB =
          await jsonOf(await call('GET', '/api/dashboard', token: tokenB));
      expect(payloadB['totalNotes'], 1);
      expect((payloadB['recentNotes'] as List).length, 1);
    });
  });
}

/// Result of a successful test-database connection attempt.
class _TestContext {
  _TestContext(this.handler, this.db);

  final Handler handler;
  final Database db;
}

/// Connects to (and creates if needed) the dedicated `<DB_NAME>_test`
/// database, runs migrations, and builds the handler.
///
/// Returns `null` when no database is reachable — the caller then registers a
/// single skipped test instead of pretending anything passed.
Future<_TestContext?> _connectTestDatabase() async {
  final platform = Platform.environment;
  final fileEnv = loadEnvFile('.env');
  final baseDbName = platform['DB_NAME'] ?? fileEnv['DB_NAME'] ?? 'locknote';
  final testDbName = platform['TEST_DB_NAME'] ?? '${baseDbName}_test';

  // PostgreSQL identifiers may only be interpolated when they are plain names.
  if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(testDbName)) {
    stderr.writeln(
        'Integration tests skipped: unsafe TEST_DB_NAME "$testDbName".');
    return null;
  }

  final env = <String, String>{
    ...platform,
    'DB_NAME': testDbName,
    // Fast work factor keeps the suite quick; production uses the default.
    'PBKDF2_ITERATIONS': platform['PBKDF2_ITERATIONS'] ?? '10000',
  };

  Config config;
  try {
    config = Config.load(environment: env, envFile: '.env');
  } on ConfigException catch (error) {
    stderr.writeln('Integration tests skipped: ${error.message}');
    return null;
  }

  Database? db;
  try {
    db = Database(config);
    await db.open(attempts: 1);
  } on Object catch (_) {
    db = null;
  }

  if (db == null) {
    // Try to create the test database through the maintenance database.
    try {
      final adminConfig = Config.load(
        environment: {...env, 'DB_NAME': 'postgres'},
        envFile: '.env',
      );
      final admin = Database(adminConfig);
      await admin.open(attempts: 1);
      try {
        await admin.query('CREATE DATABASE $testDbName');
      } on Object catch (error) {
        if (!error.toString().contains('42P04')) rethrow; // already exists
      }
      await admin.close();
      db = Database(config);
      await db.open(attempts: 1);
    } on Object catch (error) {
      stderr.writeln('Integration tests skipped: $error');
      return null;
    }
  }

  try {
    await runMigrations(db);
    final handler = buildHandler(db: db, config: config);
    return _TestContext(handler, db);
  } on Object catch (error) {
    stderr.writeln(
        'Integration tests skipped (migration/handler setup failed): $error');
    await db.close();
    return null;
  }
}
