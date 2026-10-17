import 'package:flutter/material.dart';

import '../models/note.dart';
import '../theme/app_theme.dart';

/// A note preview card: title, body preview, timestamp, and quick actions.
///
/// The whole card is tappable (opens the editor); edit/delete buttons appear
/// on hover for pointer devices and are always visible on touch layouts.
class NoteCard extends StatefulWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 170),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hovered
                  ? AppTheme.primary.withValues(alpha: 0.45)
                  : AppTheme.border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hovered ? 0.07 : 0.03),
                blurRadius: _hovered ? 16 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.sticky_note_2_outlined,
                      size: 16,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      note.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        height: 1.25,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Note actions',
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'edit') widget.onEdit();
                      if (value == 'delete') widget.onDelete();
                    },
                    icon: const Icon(
                      Icons.more_horiz_rounded,
                      size: 20,
                      color: AppTheme.textSecondary,
                    ),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit note')),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete note'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Text(
                  note.preview,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.schedule,
                    size: 14,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Updated ${note.updatedLabel}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  _ActionChip(
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit',
                    onTap: widget.onEdit,
                    visible: _hovered,
                  ),
                  const SizedBox(width: 4),
                  _ActionChip(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete',
                    danger: true,
                    onTap: widget.onDelete,
                    visible: _hovered,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.visible,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool visible;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.red.shade600 : AppTheme.primary;
    return SizedBox(
      width: 30,
      height: 30,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Icon(
            icon,
            size: 17,
            color: visible ? color : Colors.transparent,
          ),
        ),
      ),
    );
  }
}
