import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/note.dart';
import '../state/notes_controller.dart';
import '../theme/app_theme.dart';
import 'app_text_field.dart';
import 'error_banner.dart';
import 'loading_button.dart';

/// Opens the note editor for [note] (or a brand-new note) and returns `true`
/// when something was saved.
Future<bool?> showNoteEditor(
  BuildContext context, {
  required NotesController notes,
  Note? note,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => NoteEditorDialog(controller: notes, note: note),
  );
}

class NoteEditorDialog extends StatefulWidget {
  const NoteEditorDialog({super.key, required this.controller, this.note});

  final NotesController controller;
  final Note? note;

  @override
  State<NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<NoteEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title = TextEditingController(
    text: widget.note?.title ?? '',
  );
  late final TextEditingController _content = TextEditingController(
    text: widget.note?.content ?? '',
  );

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.note != null;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await widget.controller.updateNote(
          widget.note!,
          title: _title.text.trim(),
          content: _content.text,
        );
      } else {
        await widget.controller.createNote(
          title: _title.text.trim(),
          content: _content.text,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      final fieldErrors = error.fields.values.join(' ');
      setState(() {
        _saving = false;
        _error = fieldErrors.isEmpty
            ? error.message
            : '${error.message} $fieldErrors';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Something went wrong while saving. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _isEditing ? Icons.edit_note_outlined : Icons.note_add_outlined,
              color: AppTheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isEditing ? 'Edit note' : 'New note',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            icon: const Icon(
              Icons.close,
              size: 20,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ErrorBanner(message: _error),
                if (_error != null) const SizedBox(height: 14),
                AppTextField(
                  controller: _title,
                  label: 'Title',
                  hint: 'e.g. Exam preparation plan',
                  prefixIcon: Icons.title,
                  autofocus: !_isEditing,
                  textInputAction: TextInputAction.next,
                  maxLength: 120,
                  enabled: !_saving,
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return 'A title is required.';
                    if (text.length > 120) {
                      return 'Keep the title under 120 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _content,
                  label: 'Content',
                  hint: 'Write your note here…',
                  prefixIcon: Icons.notes_outlined,
                  maxLines: 8,
                  maxLength: 20000,
                  enabled: !_saving,
                  validator: (value) {
                    if ((value ?? '').length > 20000) {
                      return 'Content must be under 20,000 characters.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        LoadingButton(
          label: _isEditing ? 'Save changes' : 'Create note',
          icon: Icons.check_rounded,
          loading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}
