import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/dashboard_summary.dart';
import '../models/note.dart';

/// Owns the note collection for the signed-in user: loading, search, CRUD,
/// and the dashboard summary.
///
/// The server always returns only *this user's* notes; the controller never
/// filters ownership itself — it just renders what the API authorizes.
class NotesController extends ChangeNotifier {
  NotesController(this._api);

  final ApiClient _api;

  List<Note> notes = [];
  DashboardSummary? summary;

  /// True while a full (non-silent) refresh is running — drives spinners.
  bool loading = false;

  /// True once the first successful load has completed.
  bool loaded = false;

  /// Current server-side search query.
  String search = '';

  /// Last load error message (cleared on success), for the error state UI.
  String? errorMessage;

  Timer? _debounce;

  bool get hasNotes => notes.isNotEmpty;
  bool get isSearching => search.trim().isNotEmpty;

  /// Loads the user's notes (optionally filtered by [search]).
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      loading = true;
      notifyListeners();
    }
    try {
      final response = await _api.get(
        '/api/notes',
        query: {'search': search.trim()},
      );
      notes = [
        for (final item in (response['notes'] as List? ?? const []))
          Note.fromJson(item as Map<String, dynamic>),
      ];
      errorMessage = null;
      loaded = true;
    } on ApiException catch (error) {
      if (!silent) errorMessage = error.message;
      rethrow;
    } finally {
      if (!silent) loading = false;
      notifyListeners();
    }
  }

  /// Loads the dashboard numbers and recently updated notes.
  Future<void> loadSummary() async {
    try {
      final response = await _api.get('/api/dashboard');
      summary = DashboardSummary.fromJson(response as Map<String, dynamic>);
      errorMessage = null;
      notifyListeners();
    } on ApiException catch (error) {
      errorMessage = error.message;
      rethrow;
    }
  }

  /// Refreshes notes + summary together (initial load and pull-to-refresh).
  Future<void> refreshAll() async {
    loading = true;
    notifyListeners();
    try {
      await Future.wait([load(silent: true), loadSummary()]);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Debounced live search — typing "trip" fires one request ~300ms after the
  /// last keystroke instead of three.
  void setSearch(String value) {
    if (value == search) return;
    search = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      load(silent: true).catchError((Object error) {
        if (error is ApiException) errorMessage = error.message;
        return null;
      });
    });
    notifyListeners();
  }

  Future<Note> createNote({
    required String title,
    required String content,
  }) async {
    final response = await _api.post(
      '/api/notes',
      body: {'title': title, 'content': content},
    );
    final note = Note.fromJson(response['note'] as Map<String, dynamic>);
    notes = [note, ...notes];
    _summaryAdd(note);
    notifyListeners();
    return note;
  }

  Future<Note> updateNote(
    Note note, {
    required String title,
    required String content,
  }) async {
    final response = await _api.put(
      '/api/notes/${note.id}',
      body: {'title': title, 'content': content},
    );
    final updated = Note.fromJson(response['note'] as Map<String, dynamic>);
    notes = [
      for (final existing in notes)
        existing.id == updated.id ? updated : existing,
    ];
    _summaryUpdate(updated);
    notifyListeners();
    return updated;
  }

  Future<void> deleteNote(Note note) async {
    await _api.delete('/api/notes/${note.id}');
    notes = notes.where((existing) => existing.id != note.id).toList();
    final current = summary;
    if (current != null) {
      final remaining = current.totalNotes - 1;
      summary = DashboardSummary(
        totalNotes: remaining < 0 ? 0 : remaining,
        updatedLast7Days: current.updatedLast7Days,
        recentNotes: current.recentNotes
            .where((item) => item.id != note.id)
            .toList(),
      );
    }
    notifyListeners();
  }

  /// Clears state on logout so the next account starts clean.
  void reset() {
    _debounce?.cancel();
    notes = [];
    summary = null;
    loading = false;
    loaded = false;
    search = '';
    errorMessage = null;
    notifyListeners();
  }

  void _summaryAdd(Note note) {
    final current = summary;
    if (current == null) return;
    summary = DashboardSummary(
      totalNotes: current.totalNotes + 1,
      updatedLast7Days: current.updatedLast7Days + 1,
      recentNotes: [note, ...current.recentNotes].take(5).toList(),
    );
  }

  void _summaryUpdate(Note note) {
    final current = summary;
    if (current == null) return;
    summary = DashboardSummary(
      totalNotes: current.totalNotes,
      updatedLast7Days: current.updatedLast7Days,
      recentNotes: [
        note,
        ...current.recentNotes.where((item) => item.id != note.id),
      ].take(5).toList(),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
