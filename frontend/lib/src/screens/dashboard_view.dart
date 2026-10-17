import 'package:flutter/material.dart';

import '../models/note.dart';
import '../state/notes_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/note_card.dart';
import '../widgets/note_editor_dialog.dart';
import '../widgets/stat_card.dart';

/// Dashboard: greeting, KPI cards, and recently updated notes.
class DashboardView extends StatelessWidget {
  const DashboardView({
    super.key,
    required this.notes,
    required this.userName,
    required this.onAddNote,
    required this.onOpenNotes,
  });

  final NotesController notes;
  final String userName;
  final VoidCallback onAddNote;
  final VoidCallback onOpenNotes;

  @override
  Widget build(BuildContext context) {
    final summary = notes.summary;
    final loading = notes.loading && summary == null;
    final failed = notes.errorMessage != null && summary == null;

    return RefreshIndicator(
      onRefresh: () => notes.refreshAll().catchError((Object _) => null),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          _Greeting(userName: userName),
          const SizedBox(height: 22),
          if (loading)
            const _LoadingBlock()
          else if (failed)
            EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load your dashboard',
              message:
                  notes.errorMessage ??
                  'Please check your connection and try again.',
              actionLabel: 'Retry',
              onAction: () => notes.refreshAll().catchError((Object _) => null),
            )
          else if (summary != null) ...[
            _StatsRow(
              totalNotes: summary.totalNotes,
              updatedThisWeek: summary.updatedLast7Days,
              onAddNote: onAddNote,
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                const Text(
                  'Recently updated',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onOpenNotes,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('View all notes'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (summary.recentNotes.isEmpty)
              Container(
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const EmptyState(
                  icon: Icons.edit_note_rounded,
                  title: 'Nothing here yet',
                  message: 'Create your first note and it will show up here with its last-updated time.',
                ),
              )
            else
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final note in summary.recentNotes)
                    SizedBox(
                      width: _cardWidth(context),
                      child: NoteCard(
                        note: note,
                        onTap: () => _openEditor(context, note),
                        onEdit: () => _openEditor(context, note),
                        onDelete: () => _delete(context, note),
                      ),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  double _cardWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1500) return 300;
    if (width >= 1100) return 280;
    return double.infinity; // Full-width cards on medium/mobile layouts.
  }

  Future<void> _openEditor(BuildContext context, Note note) async {
    final saved = await showNoteEditor(context, notes: notes, note: note);
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Note updated.')));
    }
  }

  Future<void> _delete(BuildContext context, Note note) async {
    final confirmed = await confirmDeleteNote(context, note);
    if (confirmed != true || !context.mounted) return;
    try {
      await notes.deleteNote(note);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Note deleted.')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Could not delete the note. Please try again.'),
            ),
          );
      }
    }
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.userName});

  final String userName;

  @override
  Widget build(BuildContext context) {
    final firstName = userName.trim().isEmpty
        ? 'there'
        : userName.trim().split(RegExp(r'\s+')).first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hello, $firstName 👋',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Here is an overview of your secure notes.',
          style: TextStyle(fontSize: 14.5, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.totalNotes,
    required this.updatedThisWeek,
    required this.onAddNote,
  });

  final int totalNotes;
  final int updatedThisWeek;
  final VoidCallback onAddNote;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final cards = [
      StatCard(
        icon: Icons.description_rounded,
        label: 'Total notes',
        value: '$totalNotes',
        tint: AppTheme.primary,
        caption: totalNotes == 0
            ? 'Create your first one →'
            : 'stored securely',
      ),
      StatCard(
        icon: Icons.timelapse_rounded,
        label: 'Updated (7 days)',
        value: '$updatedThisWeek',
        tint: AppTheme.accent,
        caption: 'recent activity',
      ),
      _QuickAddCard(onAddNote: onAddNote),
    ];

    if (width >= 900) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: cards[0]),
          const SizedBox(width: 16),
          Expanded(child: cards[1]),
          const SizedBox(width: 16),
          Expanded(child: cards[2]),
        ],
      );
    }
    return Column(
      children: [
        cards[0],
        const SizedBox(height: 14),
        cards[1],
        const SizedBox(height: 14),
        cards[2],
      ],
    );
  }
}

class _QuickAddCard extends StatelessWidget {
  const _QuickAddCard({required this.onAddNote});

  final VoidCallback onAddNote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt_rounded, color: Colors.white, size: 24),
          const SizedBox(height: 12),
          const Text(
            'Quick capture',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Jot something down before you forget it.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: onAddNote,
            icon: const Icon(Icons.add_rounded, size: 17),
            label: const Text('Add note'),
          ),
        ],
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 90),
      child: Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}
