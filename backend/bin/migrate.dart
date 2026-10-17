import 'dart:io';

import 'package:locknote_backend/locknote_backend.dart';

/// Applies pending SQL migrations from `migrations/*.sql`.
///
/// Usage (from the `backend/` folder):
/// ```sh
/// dart run bin/migrate.dart
/// ```
Future<void> main(List<String> args) async {
  final Config config;
  try {
    config = Config.load();
  } on ConfigException catch (error) {
    stderr.writeln(error.message);
    exitCode = 78; // EX_CONFIG
    return;
  }

  final db = Database(config);
  try {
    await db.open(attempts: 1);
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
    return;
  }

  try {
    final applied = await runMigrations(db);
    if (applied.isEmpty) {
      stdout.writeln('Database is up to date — no pending migrations.');
    } else {
      stdout.writeln('Applied ${applied.length} migration(s):');
      for (final name in applied) {
        stdout.writeln('  + $name');
      }
    }
  } catch (error, stackTrace) {
    stderr.writeln('Migration failed: $error');
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    await db.close();
  }
}
