/// The authenticated user attached to a request after token verification.
class AuthUser {
  const AuthUser({required this.id, required this.name, required this.email});

  final int id;
  final String name;
  final String email;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'email': email};
}

/// Columns selected whenever a note row is returned to a client.
const String noteSelectColumns =
    'id, user_id, title, content, created_at, updated_at';

/// Converts a `notes` table row (from `toColumnMap()`) into the JSON shape
/// used by the Flutter app: camelCase keys and ISO-8601 UTC timestamps.
Map<String, Object?> noteToJson(Map<String, dynamic> row) {
  return <String, Object?>{
    'id': row['id'],
    'title': row['title'],
    'content': row['content'],
    'createdAt': (row['created_at'] as DateTime).toUtc().toIso8601String(),
    'updatedAt': (row['updated_at'] as DateTime).toUtc().toIso8601String(),
  };
}
