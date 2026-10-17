import 'dart:io';

import 'database.dart';

/// Applies every pending file from `migrations/*.sql` in filename order.
///
/// Applied files are recorded in `schema_migrations`, so running the migrator
/// again is a no-op. Each migration file must therefore be written to be safe
/// to re-run (use `IF NOT EXISTS`).
///
/// Returns the names of migrations applied by this call.
Future<List<String>> runMigrations(Database db) async {
  await db.query('''
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name       TEXT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  ''');

  final alreadyApplied = (await db.query('SELECT name FROM schema_migrations'))
      .map((row) => row.toColumnMap()['name'] as String)
      .toSet();

  final directory = findMigrationsDirectory();
  final files = directory
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final applied = <String>[];
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    if (alreadyApplied.contains(name)) continue;

    final sql = await file.readAsString();
    await db.executeScript(sql);
    await db.query(
      'INSERT INTO schema_migrations (name) VALUES (@name) ON CONFLICT DO NOTHING',
      parameters: {'name': name},
    );
    applied.add(name);
  }
  return applied;
}

/// Locates the `migrations/` folder.
///
/// Checked in order, so it works whether commands run from the repository root
/// or from `backend/`:
/// 1. `./migrations` (running inside `backend/`)
/// 2. `./backend/migrations` (running at the repository root)
/// 3. relative to this program's own file (`backend/bin/...`)
Directory findMigrationsDirectory() {
  final candidates = <Directory>[
    Directory('migrations'),
    Directory('backend/migrations'),
    Directory(
      '${File.fromUri(Platform.script).parent.path}${Platform.pathSeparator}..'
      '${Platform.pathSeparator}migrations',
    ),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) return candidate;
  }
  throw StateError(
    'Could not find the migrations directory. Run this from the backend/ '
    'folder (dart run bin/migrate.dart).',
  );
}

/// Deletes expired session rows; called at startup.
Future<void> purgeExpiredSessions(Database db) async {
  await db.query('DELETE FROM sessions WHERE expires_at < now()');
}
