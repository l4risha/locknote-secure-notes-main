import 'dart:io';

import 'package:locknote_backend/locknote_backend.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Entry point of the LockNote API server.
///
/// Configuration comes exclusively from environment variables (optionally
/// loaded from a git-ignored `.env` file) — see `.env.example`.
Future<void> main(List<String> args) async {
  final Config config;
  try {
    config = Config.load();
  } on ConfigException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln('Copy backend/.env.example to backend/.env and fill it in.');
    exitCode = 78; // EX_CONFIG
    return;
  }

  final db = Database(config);
  stderr.writeln(
    'Connecting to PostgreSQL at ${config.dbHost}:${config.dbPort}/${config.dbName} ...',
  );
  try {
    await db.open();
  } on StateError catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(
        'Is PostgreSQL running? See README.md for setup instructions.');
    exitCode = 1;
    return;
  }

  if (config.autoMigrate) {
    final applied = await runMigrations(db);
    if (applied.isEmpty) {
      stderr.writeln('Migrations: database is up to date.');
    } else {
      stderr.writeln('Migrations applied: ${applied.join(', ')}');
    }
  }
  await purgeExpiredSessions(db);

  final handler = buildHandler(db: db, config: config);
  final server = await shelf_io.serve(handler, config.host, config.port);

  stderr.writeln('');
  stderr.writeln(
      'LockNote API listening on http://${config.host}:${server.port}');
  stderr.writeln(
      '  health check : http://${config.host}:${server.port}/api/health');
  stderr.writeln(
    config.staticDir == null
        ? '  mode         : API only (set STATIC_DIR to also serve the built Flutter app)'
        : '  mode         : API + static UI from ${config.staticDir}',
  );
  stderr.writeln('  press Ctrl+C to stop');

  Future<void> shutdown(String signal) async {
    stderr.writeln('\nReceived $signal, shutting down...');
    await server.close(force: true);
    await db.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown('SIGINT'));
  // Wala supported ang SIGTERM sa Windows, mao nang i-skip didto
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => shutdown('SIGTERM'));
  }
}