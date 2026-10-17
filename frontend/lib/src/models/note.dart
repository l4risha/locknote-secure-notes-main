/// A personal note as returned by `/api/notes`.
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: (json['id'] as num).toInt(),
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );

  Map<String, Object?> toJson() => {'title': title, 'content': content};

  Note copyWith({String? title, String? content}) => Note(
    id: id,
    title: title ?? this.title,
    content: content ?? this.content,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  /// First non-empty lines of the body — used as a card preview.
  String get preview {
    final lines = content
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    final text = lines.take(3).join(' • ');
    return text.isEmpty ? 'No additional text' : text;
  }

  /// Friendly relative timestamp: "Just now", "3h ago", "12 Mar".
  String get updatedLabel {
    final now = DateTime.now();
    final difference = now.difference(updatedAt.toLocal());
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = updatedAt.toLocal();
    return '${local.day} ${months[local.month - 1]}';
  }
}
