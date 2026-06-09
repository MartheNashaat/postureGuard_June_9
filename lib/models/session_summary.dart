class SessionSummary {
  final int? id;
  final String sessionId;
  final DateTime date;
  final int durationSeconds;
  final double goodPosturePercent;
  final int longestStreakSeconds;
  final DateTime? worstMomentTimestamp;

  const SessionSummary({
    this.id,
    required this.sessionId,
    required this.date,
    required this.durationSeconds,
    required this.goodPosturePercent,
    required this.longestStreakSeconds,
    this.worstMomentTimestamp,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'session_id': sessionId,
        'date': date.toIso8601String(),
        'duration_seconds': durationSeconds,
        'good_posture_percent': goodPosturePercent,
        'longest_streak': longestStreakSeconds,
        'worst_moment_timestamp':
            worstMomentTimestamp?.millisecondsSinceEpoch,
      };

  factory SessionSummary.fromMap(Map<String, dynamic> map) => SessionSummary(
        id: map['id'] as int?,
        sessionId: map['session_id'] as String,
        date: DateTime.parse(map['date'] as String),
        durationSeconds: map['duration_seconds'] as int,
        goodPosturePercent: (map['good_posture_percent'] as num).toDouble(),
        longestStreakSeconds: map['longest_streak'] as int,
        worstMomentTimestamp: map['worst_moment_timestamp'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                map['worst_moment_timestamp'] as int)
            : null,
      );

  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '${minutes}m ${seconds}s';
  }
}
