import 'package:shelf/shelf.dart';

import '../auth.dart';
import '../database.dart';
import '../http_utils.dart';
import '../models.dart';
import '../session_store.dart';
import '../validation.dart';

/// `/api/notes/*` and `/api/dashboard`.
///
/// Every statement filters on `user_id = @userId`, so one account can never
/// read, edit, or delete another account's notes — even when guessing IDs.
class NotesHandlers {
  NotesHandlers({required this.db, required this.sessions});

  final Database db;
  final SessionStore sessions;

  /// GET /api/notes?search=`<query>`
  ///
  /// Returns the signed-in user's notes, newest update first. When `search`
  /// is provided it matches title **or** content, case-insensitively.
  Future<Response> list(Request request) async {
    final user = await requireAuth(request, sessions);
    final search = (request.url.queryParameters['search'] ?? '').trim();

    final rows = await db.query(
      '''
      SELECT $noteSelectColumns
      FROM notes
      WHERE user_id = @userId
        AND (title ILIKE @pattern ESCAPE '\\' OR content ILIKE @pattern ESCAPE '\\')
      ORDER BY updated_at DESC, id DESC
      ''',
      parameters: {'userId': user.id, 'pattern': toLikePattern(search)},
    );

    return jsonResponse({
      'notes': rows.map((row) => noteToJson(row.toColumnMap())).toList(),
    });
  }

  /// POST /api/notes
  Future<Response> create(Request request) async {
    final user = await requireAuth(request, sessions);
    final body = await readJsonObject(request);
    final title = jsonString(body, 'title');
    final content = jsonString(body, 'content');

    final errors = validateNote(title: title, content: content);
    if (errors.isNotEmpty) {
      throw ApiException(
        422,
        'Please fix the highlighted fields.',
        code: 'validation_failed',
        details: errors,
      );
    }

    final rows = await db.query(
      '''
      INSERT INTO notes (user_id, title, content)
      VALUES (@userId, @title, @content)
      RETURNING $noteSelectColumns
      ''',
      parameters: {
        'userId': user.id,
        'title': title.trim(),
        'content': content,
      },
    );

    return jsonResponse({'note': noteToJson(rows.first.toColumnMap())},
        status: 201);
  }

  /// GET `/api/notes/<id>`
  Future<Response> get(Request request, String id) async {
    final user = await requireAuth(request, sessions);
    final noteId = _parseId(id);

    final rows = await db.query(
      '''
      SELECT $noteSelectColumns
      FROM notes
      WHERE id = @id AND user_id = @userId
      ''',
      parameters: {'id': noteId, 'userId': user.id},
    );
    if (rows.isEmpty) throw _noteNotFound();

    return jsonResponse({'note': noteToJson(rows.first.toColumnMap())});
  }

  /// PUT `/api/notes/<id>`
  Future<Response> update(Request request, String id) async {
    final user = await requireAuth(request, sessions);
    final noteId = _parseId(id);

    final body = await readJsonObject(request);
    final title = jsonString(body, 'title');
    final content = jsonString(body, 'content');

    final errors = validateNote(title: title, content: content);
    if (errors.isNotEmpty) {
      throw ApiException(
        422,
        'Please fix the highlighted fields.',
        code: 'validation_failed',
        details: errors,
      );
    }

    final rows = await db.query(
      '''
      UPDATE notes
      SET title = @title, content = @content, updated_at = now()
      WHERE id = @id AND user_id = @userId
      RETURNING $noteSelectColumns
      ''',
      parameters: {
        'id': noteId,
        'userId': user.id,
        'title': title.trim(),
        'content': content,
      },
    );
    if (rows.isEmpty) throw _noteNotFound();

    return jsonResponse({'note': noteToJson(rows.first.toColumnMap())});
  }

  /// DELETE `/api/notes/<id>`
  Future<Response> delete(Request request, String id) async {
    final user = await requireAuth(request, sessions);
    final noteId = _parseId(id);

    final rows = await db.query(
      'DELETE FROM notes WHERE id = @id AND user_id = @userId RETURNING id',
      parameters: {'id': noteId, 'userId': user.id},
    );
    if (rows.isEmpty) throw _noteNotFound();

    return jsonResponse({'message': 'Note deleted.', 'id': noteId});
  }

  /// GET /api/dashboard
  ///
  /// Summary data for the dashboard: totals plus the five most recently
  /// updated notes, both computed in SQL so they stay correct for large
  /// accounts.
  Future<Response> dashboard(Request request) async {
    final user = await requireAuth(request, sessions);

    final totals = (await db.query(
      '''
      SELECT count(*)::int AS total,
             count(*) FILTER (WHERE updated_at > now() - interval '7 days')::int AS recent
      FROM notes
      WHERE user_id = @userId
      ''',
      parameters: {'userId': user.id},
    ))
        .first
        .toColumnMap();

    final recentRows = await db.query(
      '''
      SELECT $noteSelectColumns
      FROM notes
      WHERE user_id = @userId
      ORDER BY updated_at DESC, id DESC
      LIMIT 5
      ''',
      parameters: {'userId': user.id},
    );

    return jsonResponse({
      'totalNotes': totals['total'],
      'updatedLast7Days': totals['recent'],
      'recentNotes':
          recentRows.map((row) => noteToJson(row.toColumnMap())).toList(),
    });
  }

  int _parseId(String raw) {
    final id = int.tryParse(raw.trim());
    if (id == null || id < 1) {
      throw ApiException(400, 'Invalid note id.', code: 'bad_request');
    }
    return id;
  }

  ApiException _noteNotFound() {
    return ApiException(404, 'Note not found.', code: 'not_found');
  }
}
