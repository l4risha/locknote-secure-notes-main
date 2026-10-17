import 'package:flutter/material.dart';

import '../models/note.dart';
import '../state/notes_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/note_card.dart';
import '../widgets/note_editor_dialog.dart';

/// Notes page: responsive card grid, live search results, and CRUD actions.
class NotesView extends StatelessWidget {
  const NotesView({
    super.key,
    required this.notes,
    required this.onAddNote,
    required this.onNotify,
  });

  final NotesController notes;
  final VoidCallback onAddNote;
  final void Function(String message, {bool error}) onNotify;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notes,
      builder: (context, _) {
        final firstLoad = !notes.loaded && notes.loading && notes.notes.isEmpty;
        final loadFailed = !notes.loaded && notes.errorMessage != null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (notes.loading && !firstLoad)
              const LinearProgressIndicator(minHeight: 2.5)
            else
              const SizedBox(height: 2.5),
            Expanded(
              child: firstLoad
                  ? const Center(
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                    )
                  : loadFailed
                  ? EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Could not load your notes',
                      message: notes.errorMessage ?? 'Please try again.',
                      actionLabel: 'Retry',
                      onAction: () =>
                          notes.refreshAll().catchError((Object _) => null),
                    )
                  : notes.notes.isEmpty
                  ? _buildEmpty(context)
                  : _buildGrid(context),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    if (notes.isSearching) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matching notes',
        message:
            'Nothing matches "${notes.search.trim()}". Try a different '
            'word from the title or content.',
        actionLabel: 'Clear search',
        onAction: () => notes.setSearch(''),
      );
    }
    return EmptyState(
      icon: Icons.note_alt_rounded,
      title: 'Your notebook is empty',
      message:
          'Create your first note — it stays private to your account '
          'and is only a few keystrokes away.',
      actionLabel: 'Add your first note',
      onAction: onAddNote,
    );
  }

  Widget _buildGrid(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
      child: Row(
        children: [
          Text(
            notes.isSearching
                ? '${notes.notes.length} result${notes.notes.length == 1 ? '' : 's'}'
                : '${notes.notes.length} note${notes.notes.length == 1 ? '' : 's'}',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          if (notes.isSearching) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'for "${notes.search.trim()}"',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontStyle: FontStyle.italic,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
      children: [
        header,
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 340,
            mainAxisExtent: 225,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: notes.notes.length,
          itemBuilder: (context, index) {
            final note = notes.notes[index];
            return NoteCard(
              key: ValueKey(note.id),
              note: note,
              onTap: () => _openEditor(context, note),
              onEdit: () => _openEditor(context, note),
              onDelete: () => _delete(context, note),
            );
          },
        ),
      ],
    );
  }

  Future<void> _openEditor(BuildContext context, Note note) async {
    final saved = await showNoteEditor(context, notes: notes, note: note);
    if (saved == true) onNotify('Note updated.');
  }

  Future<void> _delete(BuildContext context, Note note) async {
    final confirmed = await confirmDeleteNote(context, note);
    if (confirmed != true) return;
    try {
      await notes.deleteNote(note);
      onNotify('Note deleted.');
    } catch (_) {
      onNotify('Could not delete the note. Please try again.', error: true);
    }
  }
}
