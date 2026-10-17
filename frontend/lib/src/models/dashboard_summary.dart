import 'note.dart';

/// Aggregated numbers shown on the dashboard (`GET /api/dashboard`).
class DashboardSummary {
  const DashboardSummary({
    required this.totalNotes,
    required this.updatedLast7Days,
    required this.recentNotes,
  });

  final int totalNotes;
  final int updatedLast7Days;
  final List<Note> recentNotes;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) =>
      DashboardSummary(
        totalNotes: (json['totalNotes'] as num?)?.toInt() ?? 0,
        updatedLast7Days: (json['updatedLast7Days'] as num?)?.toInt() ?? 0,
        recentNotes: [
          for (final item in (json['recentNotes'] as List? ?? const []))
            Note.fromJson(item as Map<String, dynamic>),
        ],
      );
}
