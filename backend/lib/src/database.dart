import 'package:postgres/postgres.dart';

import 'config.dart';

/// Thin wrapper around a single PostgreSQL connection.
///
/// All query helpers go through this class so the whole application uses
/// **parameterized statements** (`Sql.named` + `parameters:`) — user input is
/// never string-concatenated into SQL, which prevents SQL injection.
class Database {
  Database(this.config);

  final Config config;
  Connection? _connection;

  /// Maps the `DB_SSL` configuration value onto the driver's TLS modes.
  SslMode get _sslMode => switch (config.dbSslMode) {
        'require' => SslMode.require,
        'verify-full' => SslMode.verifyFull,
        _ => SslMode.disable,
      };

  /// Opens the connection, retrying a few times (useful when the database
  /// container is still starting up).
  Future<void> open(
      {int attempts = 5, Duration delay = const Duration(seconds: 2)}) async {
    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        _connection = await Connection.open(
          Endpoint(
            host: config.dbHost,
            port: config.dbPort,
            database: config.dbName,
            username: config.dbUser,
            password: config.dbPassword,
          ),
          settings: ConnectionSettings(
            sslMode: _sslMode,
            connectTimeout: const Duration(seconds: 10),
            applicationName: 'locknote',
          ),
        );
        return;
      } catch (error) {
        lastError = error;
        if (attempt < attempts) {
          await Future<void>.delayed(delay);
        }
      }
    }
    throw StateError(
      'Could not connect to PostgreSQL at ${config.dbHost}:${config.dbPort}/${config.dbName} '
      'as ${config.dbUser} after $attempts attempts. Last error: $lastError',
    );
  }

  Future<void> close() async {
    final connection = _connection;
    _connection = null;
    if (connection != null && connection.isOpen) {
      await connection.close();
    }
  }

  Connection get _requireConnection {
    final connection = _connection;
    if (connection == null || !connection.isOpen) {
      throw StateError('Database connection is not open. Call open() first.');
    }
    return connection;
  }

  /// Executes a statement with named `@parameters` (SQL-injection safe).
  ///
  /// ```dart
  /// await db.query('SELECT * FROM notes WHERE user_id = @userId',
  ///     parameters: {'userId': 1});
  /// ```
  Future<Result> query(String sql,
      {Map<String, Object?> parameters = const {}}) {
    if (parameters.isEmpty) {
      return _requireConnection.execute(sql);
    }
    return _requireConnection.execute(Sql.named(sql), parameters: parameters);
  }

  /// Runs several SQL statements as one atomic script (used by migrations).
  ///
  /// Uses PostgreSQL's simple query protocol, which — unlike the parameterized
  /// path above — accepts multiple statements in a single call. Migration
  /// files contain only static SQL, never user input.
  Future<Result> executeScript(String sql) {
    return _requireConnection.execute(sql, queryMode: QueryMode.simple);
  }

  /// Runs [action] inside a database transaction; commits on success and
  /// rolls back if it throws.
  Future<T> transaction<T>(Future<T> Function(TxSession session) action) {
    return _requireConnection.runTx(action);
  }
}
