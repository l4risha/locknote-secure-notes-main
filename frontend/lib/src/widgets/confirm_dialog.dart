import 'package:flutter/material.dart';

import '../models/note.dart';
import '../theme/app_theme.dart';

/// Asks "really delete?" before removing a note. Returns true on confirm.
Future<bool?> confirmDeleteNote(BuildContext context, Note note) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Delete this note?',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(
          '"${note.title}" will be permanently deleted. This cannot be undone.',
          style: const TextStyle(height: 1.5, color: AppTheme.textSecondary),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep note'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade600,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}
