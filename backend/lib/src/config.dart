import 'dart:io';

import 'env_file.dart';
import 'passwords.dart';

/// Thrown when required configuration is missing or malformed.
///
/// The message is safe to print: it never contains secret values.
class ConfigException implements Exception {
  ConfigException(this.message);
  final String message;

  @override
  String toString() => 'Configuration error: $message';
}

/// All application configuration, sourced from environment variables.
///
/// Precedence: real process environment > `.env` file > built-in default.
/// Database credentials and secrets are **never** hard-coded — they must come
/// from the environment, otherwise startup fails fast with a clear message.
class Config {
  const Config({
    required this.dbHost,
    required this.dbPort,
    required this.dbName,
    required this.dbUser,
    required this.dbPassword,
    required this.dbSslMode,
    required this.host,
    required this.port,
    required this.allowedOrigins,
    required this.staticDir,
    required this.sessionTtl,
    required this.pbkdf2Iterations,
    required this.autoMigrate,
  });

  final String dbHost;
  final int dbPort;
  final String dbName;
  final String dbUser;
  final String dbPassword;

  /// One of: `disable`, `require`, `verify-full` (see README).
  final String dbSslMode;

  final String host;
  final int port;

  /// Browser origins allowed to call the API. Empty = allow any origin.
  final List<String> allowedOrigins;

  /// Optional directory with a built Flutter web app to serve alongside the API.
  final String? staticDir;

  final Duration sessionTtl;
  final int pbkdf2Iterations;
  final bool autoMigrate;

  /// Reads configuration from the process environment, overlaid on `.env`.
  ///
  /// Precedence: [environment] (defaults to the real process environment)
  /// overrides values read from [envFile].
  static Config load(
      {Map<String, String>? environment, String envFile = '.env'}) {
    final effective = environment ?? Platform.environment;
    final values = <String, String>{...loadEnvFile(envFile), ...effective};

    String require(String key) {
      final value = values[key]?.trim() ?? '';
      if (value.isEmpty) {
        throw ConfigException(
          'missing required variable $key. '
          'Copy backend/.env.example to backend/.env and fill it in, '
          'or export the variable in your shell.',
        );
      }
      return value;
    }

    int parseInt(String key, int fallback) {
      final raw = values[key]?.trim() ?? '';
      if (raw.isEmpty) return fallback;
      final parsed = int.tryParse(raw);
      if (parsed == null || parsed < 0) {
        throw ConfigException(
            '$key must be a non-negative integer (got "$raw").');
      }
      return parsed;
    }

    bool parseBool(String key, bool fallback) {
      final raw = values[key]?.trim().toLowerCase() ?? '';
      if (raw.isEmpty) return fallback;
      if (raw == 'true' || raw == '1' || raw == 'yes') return true;
      if (raw == 'false' || raw == '0' || raw == 'no') return false;
      throw ConfigException('$key must be true or false (got "$raw").');
    }

    final sslMode = (values['DB_SSL'] ?? 'prefer').trim().toLowerCase();
    const validSslModes = {
      'disable',
      'allow',
      'prefer',
      'require',
      'verify-ca',
      'verify-full'
    };
    if (!validSslModes.contains(sslMode)) {
      throw ConfigException(
          'DB_SSL must be one of ${validSslModes.join(', ')} (got "$sslMode").');
    }

    final iterationsRaw = values['PBKDF2_ITERATIONS']?.trim() ?? '';
    var iterations = defaultPbkdf2Iterations;
    if (iterationsRaw.isNotEmpty) {
      final parsed = int.tryParse(iterationsRaw);
      if (parsed == null || parsed < 1000) {
        throw ConfigException('PBKDF2_ITERATIONS must be an integer >= 1000.');
      }
      iterations = parsed;
    }

    final sessionHours = parseInt('SESSION_TTL_HOURS', 720);
    if (sessionHours < 1) {
      throw ConfigException('SESSION_TTL_HOURS must be at least 1.');
    }

    final origins = (values['ALLOWED_ORIGINS'] ?? '')
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    final staticDirRaw = values['STATIC_DIR']?.trim() ?? '';

    return Config(
      dbHost: require('DB_HOST'),
      dbPort: parseInt('DB_PORT', 5432),
      dbName: require('DB_NAME'),
      dbUser: require('DB_USER'),
      dbPassword: require('DB_PASSWORD'),
      dbSslMode: sslMode,
      host: values['SERVER_HOST']?.trim().isNotEmpty == true
          ? values['SERVER_HOST']!.trim()
          : '0.0.0.0',
      port: parseInt('SERVER_PORT', 8080),
      allowedOrigins: origins,
      staticDir: staticDirRaw.isEmpty ? null : staticDirRaw,
      sessionTtl: Duration(hours: sessionHours),
      pbkdf2Iterations: iterations,
      autoMigrate: parseBool('AUTO_MIGRATE', true),
    );
  }
}
